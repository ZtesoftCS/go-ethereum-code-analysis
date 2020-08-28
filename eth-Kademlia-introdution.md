#概述
Kademlia（简称Kad）是一种分布式哈希表技术，用于建立p2p网络拓扑结构。

基本原理就是以两个节点ID的异或值作为两节点间的距离d，每个节点都将其他节点的信息存储到称之为K桶的表结构中，该表结构按照d的为1的最高bit位分层（可理解为桶索引），每层中存储最多K个节点信息。如下： 
  
|  I  |  距离范围  |     邻居     |
|:---:|:---------:|:-----------:|
|  0  |[2^0, 2^1 )  | (IP,UDP,NodeID)  <br>...|
|  i  |[2^i, 2^i+1 )  | (IP,UDP,NodeID)  <br>...|

节点查找时，通过询问距离自己最近的a个节点，让对方返回距离目标最近的a个节点，重复这个过程直到找到目标节点或者能问的都问了一遍。


参考资料：  
[references/Kademlia协议原理简介.pdf](references/Kademlia协议原理简介.pdf)  
[https://www.jianshu.com/p/f2c31e632f1d](https://www.jianshu.com/p/f2c31e632f1d)

#以太坊中的实现概述
##几个概念
1. 计算距离的ID值，位数代表了有多少个K桶，经典算法中是160位的。在以太坊中，NodeID为节点的PublicKey，__参与距离计算的是NodeID的sha3哈希值，长度256位__。
2. K桶的项数不超过K，K值是为平衡系统性能和网络负载而设置的一个常数，但必须是偶数。eth中K=16。
3. 查找邻居节点时，返回节点数最多是a个，a也是为了系统优化而定的参数，eth中 a=3。

##数据结构及存储
* p2p模块使用独立的leveldb持久化存储所有的邻居节点信息，从而节点重新启动时能直接利用历史上已找到的节点。
* 存储的key为NodeID，value为Node结构体，包含IP、UDP、TCP、ID（即NodeID）等信息。

##p2p网络维护的实现
table.go主要实现了p2p的Kademlia协议。其中定义了K桶的结构并实现节点的维护策略。

###启动过程
节点启动时，初始化配置信息后，会启动p2p server，在server启动过程中，会执行udp对象创建、table对象创建、监听udp端口等处理。table对象创建中就包含了启动goroutine执行节点发现及维护的服务。

1. 从leveldb中随机选取若干种子节点（新节点第一次启动时，使用启动参数或源码中提供的启动节点作为种子节点），出入桶结构中（内存）；
2. 启动后台过期goroutine，负责从leveldb中删除过期的数据（stale data）；
3. 启动loop，后台执行节点刷新、重验证等处理。下面写的步骤就在这个goroutine中；主要就是doRefresh：
4. 加载种子节点
5. 以自身为目标执行查找
6. 循环3遍：随机生成目标，执行查找。

###邻居节点发现流程 table.lookup
~~~
1. 在本地K桶中查找距离target最近的一批节点，最多bucketSize个（16个）；记为result；（节点加入result的逻辑：从列表中查找节点i，使得d(i,target) > d(n,target)；如果列表中还有空间，直接加入节点n；如果找到了有效的i，则用n替换i位置的节点）
2. 如果步骤1没有找到节点，则等待刷新完成（遗留：这里尚未看懂）；
3. 从result中并发发起alpha个（3个）查询，向对方询问距离target最近的若干节点（udp.findnode）；
4. 若查询失败，更新失败节点信息，若该节点总失败次数达到maxFindnodeFailures次（5次），则从本地移除该节点信息；
5. 若查询成功，对返回的节点执行bondall处理（__注意：这里会执行更新K桶的操作，不管pingpong是否成功，都会加入K桶。__如果某个节点总是连不上，会被刷新机制删掉的），去掉不在线节点；对在线节点建立连接；
6. 对在线节点，如果未见过，则按照步骤1的规则加入result中；
7. 循环从3开始的步骤，直到result中的所有节点都查询过了；
8. 返回result中的节点。
~~~  
###节点连接及本地K桶维护流程 table.bond
在lookup中会对返回的节点执行bondall处理，bondall中主要是对每个节点执行bond处理。  
bond确保本地节点和给定的远程节点有一个连接，如果连接成功，会放到本地一个连接table中。在执行findnode之前，必须有连接已建立。活跃的连接数有一定限制，以便限制网络负载占用。

不管pingpong是否成功，节点都会更新到本地K桶中。
~~~
1. 如果节点有一段时间没出现了或者对他执行findnode失败过，则执行pingpong；
2. 无论前述步骤是否执行或执行是否成功，都执行更新节点到K桶的处理。
~~~  

__节点n更新到本地K桶：__

1. 获取n对应的K桶：设距离为d，计算log2(d)。实现上是获取d二进制表示时的最高位1所在的位置。若结果≤ bucketMinDistance（239），返回K[0]，否则返回 K[结果-bucketMinDistance-1];
2. 如果n在K桶中已经存在，则将其移到最前面；否则如果K桶未满，则加进去；
3. 如果n没进入K桶中，则将其维护进候选列表中。

~~~
// add attempts to add the given node its corresponding bucket. If the
// bucket has space available, adding the node succeeds immediately.
// Otherwise, the node is added if the least recently active node in
// the bucket does not respond to a ping packet.
//
// The caller must not hold tab.mutex.
func (tab *Table) add(new *Node) {
	tab.mutex.Lock()
	defer tab.mutex.Unlock()

	b := tab.bucket(new.sha)
	if !tab.bumpOrAdd(b, new) {
		// Node is not in table. Add it to the replacement list.
		tab.addReplacement(b, new)
	}
}
~~~