### eth源码交易发送接收,校验存储分析：

```
创建合约指的是将合约部署到区块链上，这也是通过发送交易来实现。在创建合约的交易中，to字段要留空不填，在data字段中指定合约的二进制代码，
from字段是交易的发送者也是合约的创建者。

执行合约的交易

调用合约中的方法，需要将交易的to字段指定为要调用的合约的地址，通过data字段指定要调用的方法以及向该方法传递的参数。

所有对账户的变动操作都会先提交到stateDB里面，这个类似一个行为数据库，或者是缓存，最终执行需要提交到底层的数据库当中,底层数据库是levelDB（K,V数据库）

core/interface.go定义了stateDB的接口

ProtocolManager主要成员包括：
peertSet{}类型成员用来缓存相邻个体列表，peer{}表示网络中的一个远端个体。
通过各种通道(chan)和事件订阅(subscription)的方式，接收和发送包括交易和区块在内的数据更新。当然在应用中，订阅也往往利用通道来实现事件通知。
ProtocolManager用到的这些通道的另一端，可能是其他的个体peer，也可能是系统内单例的数据源比如txPool，或者是事件订阅的管理者比如event.Mux。
Fetcher类型成员累积所有其他个体发送来的有关新数据的宣布消息，并在自身对照后，安排相应的获取请求。
Downloader类型成员负责所有向相邻个体主动发起的同步流程。

func(pm *ProtocolManager) Start()

以上这四段相对独立的业务流程的逻辑分别是：
1.广播新出现的交易对象。txBroadcastLoop()会在txCh通道的收端持续等待，一旦接收到有关新交易的事件，会立即调用BroadcastTx()函数广播给那些尚无该交易对象的相邻个体。
2.广播新挖掘出的区块。minedBroadcastLoop()持续等待本个体的新挖掘出区块事件，然后立即广播给需要的相邻个体。当不再订阅新挖掘区块事件时，这个函数才会结束等待并返回。很有意思的是,在收到新挖掘出区块事件后，minedBroadcastLoop()会连续调用两次BroadcastBlock()，两次调用仅仅一个bool型参数@propagate不一样，当该参数为true时，会将整个新区块依次发给相邻区块中的一小部分；而当其为false时，仅仅将新区块的Hash值和Number发送给所有相邻列表。
3.定时与相邻个体进行区块全链的强制同步。syncer()首先启动fetcher成员，然后进入一个无限循环，每次循环中都会向相邻peer列表中“最优”的那个peer作一次区块全链同步。发起上述同步的理由分两种：如果有新登记(加入)的相邻个体，则在整个peer列表数目大于5时，发起之；如果没有新peer到达，则以10s为间隔定时的发起之。这里所谓"最优"指的是peer中所维护区块链的TotalDifficulty(td)最高，由于Td是全链中从创世块到最新头块的Difficulty值总和，所以Td值最高就意味着它的区块链是最新的，跟这样的peer作区块全链同步，显然改动量是最小的，此即"最优"。
4.将新出现的交易对象均匀的同步给相邻个体。txsyncLoop()主体也是一个无限循环，它的逻辑稍微复杂一些：首先有一个数据类型txsync{p, txs},包含peer和tx列表；通道txsyncCh用来接收txsync{}对象；txsyncLoop()每次循环时，如果从通道txsyncCh中收到新数据，则将它存入一个本地map[]结构，k为peer.ID，v为txsync{}，并将这组tx对象发送给这个peer；每次向peer发送tx对象的上限数目100*1024，如果txsync{}对象中有剩余tx，则该txsync{}对象继续存入map[]并更新tx数目；如果本次循环没有新到达txsync{},则从map[]结构中随机找出一个txsync对象，将其中的tx组发送给相应的peer，重复以上循环。

以上四段流程就是ProtocolManager向相邻peer主动发起的通信过程。尽管上述各函数细节从文字阅读起来容易模糊，不过最重要的内容还是值得留意下的：本个体(peer)向其他peer主动发起的通信中，按照数据类型可分两类：交易tx和区块block；而按照通信方式划分，亦可分为广播新的单个数据和同步一组同类型数据，这样简单的两两配对，便可组成上述四段流程。

在上文的介绍中，出现了多处有关p2p通信协议的结构类型，比如eth.peer，p2p.Peer，Server等等。这里不妨对这些p2p通信协议族的结构一并作个总解。以太坊中用到的p2p通信协议族的结构类型，大致可分为三层：

第一层处于pkg eth中，可以直接被eth.Ethereum，eth.ProtocolManager等顶层管理模块使用，在类型声明上也明显考虑了eth.Ethereum的使用特点。典型的有eth.peer{}, eth.peerSet{}，其中peerSet是peer的集合类型，而eth.peer代表了远端通信对象和其所有通信操作，它封装更底层的p2p.Peer对象以及读写通道等。
第二层属于pkg p2p，可认为是泛化的p2p通信结构，比较典型的结构类型包括代表远端通信对象的p2p.Peer{}, 封装自更底层连接对象的conn{}，通信用通道对象protoRW{}, 以及启动监听、处理新加入连接或断开连接的Server{}。这一层中，各种数据类型的界限比较清晰，尽量不出现揉杂的情况，这也是泛化结构的需求。值得关注的是p2p.Protocol{}，它应该是针对上层应用特意开辟的类型，主要作用包括容纳应用程序所要求的回调函数等，并通过p2p.Server{}在新连接建立后，将其传递给通信对象peer。从这个类型所起的作用来看，命名为Protocol还是比较贴切的，尽管不应将其与TCP/IP协议等既有概念混淆。

第三层处于golang自带的网络代码包中，也可分为两部分：第一部分pkg net，包括代表网络连接的<Conn>接口，代表网络地址的<Addr>以及它们的实现类；第二部分pkg syscall，包括更底层的网络相关系统调用类等，可视为封装了网络层(IP)和传输层(TCP)协议的系统实现。

```



```
Receiptroot我们刚刚在区块头有看到，那他具体包含的是什么呢？它是一个交易的结果，主要包括了poststate,交易所花费的gas,bloom和logs

blockchain无结构化查询需求，仅hash查询,key/value数据库最方便,底层用levelDB存储，性能好

stateDB用来存储世界状态
Core/state/statedb.go

注意：1. StateDB完整记录Transaction的执行情况； 2. StateDB的重点是StateObjects； 3. StateDB中的 stateObjects，Account的Address为 key，记录其Balance、nonce、code、codeHash ，以及tire中的 {string:Hash}等信息；

所有的结构凑明朗了，那具体的验证过程是怎么样的呢
Core/state_processor.go
Core/state_transition.go
Core/block_validator.go

StateProcessor 1. 调用StateTransition，验证（执行）Transaction； 2. 计算Gas、Recipt、Uncle Reward

StateTransition
1. 验证（执行）Transaction；
3. 扣除transaction.data.payload计算数据所需要消耗的gas；
4. 在vm中执行code（生成contract or 执行contract）；vm执 行过程中，其gas会被自动消耗。如果gas不足，vm会自 选退出；
5. 将多余的gas退回到sender.balance中；
6. 将消耗的gas换成balance加到当前env.Coinbase()中；

BlockValidator
1. 验证UsedGas
2. 验证Bloom
3. 验证receiptSha
4. 验证stateDB.IntermediateRoot

/core/vm/evm.go
交易的转帐操作由Context对象中的TransferFunc类型函数来实现，类似的函数类型，还有CanTransferFunc, 和GetHashFunc。
core/vm/contract.go
合约是evm用来执行指令的结构体

入口：/cmd/geth/main.go/main

```