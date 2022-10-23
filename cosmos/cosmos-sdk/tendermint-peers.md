### Tendermint Peers

这个文档说明peer是如何被标示和它们如何相互连接的，关于peer间的发现机制的具体细节请参考peer exchange（PEX）reactor文档。

#### 节点标示
Tendermint peer将以公钥的形式保持长期持久身份。每个peer有一个ID，peer.ID == peer.Pubkey.Address(),这个地址是以go-crypto包格式展现的。

单独一个peer ID可以有多个IP地址。当尝试去连接一个peer时，我们用PeerURL：<ID>@<IP>:<PORT>格式。我们将尝试连接到IP:PORT上的peer，并通过身份验证加密验证它是否拥有对应于<ID>的私钥。这将防止中间人攻击在peer层。

Peer也可以直接进行连接而不用ID确认，也就是说，直接用IP：PORT方法是连接。在这种情况下，验证必须在Tendermint以外进行，例如：通过VPN。

#### 连接
所有的p2p连接都是基于TCP的，为了成功建立TCP连接，需要进行两次握手：一次用来验证加密，一次用来进行Tendermint版本验证。两次握手都有可以配置的超时时间（超时时间应该很短）。

#### 认证加密握手
Tendermint采用Diffie-Helman密钥交换算法实现来端对端的密钥交换，利用NACL SecretBox 来进行加密，具体流程如下：

1. 生成一个短暂的ED25519密钥对。
2. 把公钥发送给对等节点。
3. 等待接受对等节点的公钥。
4. 利用对等节点的公钥和自己的私钥生成Diffie-Hellman的共享密钥。
5. 生成两个随机数用来加密（对发送和接受加密）的流程如下：
    * 按照字母顺序对公钥排序并把它们连接起来。
    * 利用RIPEMD160对拼接结果进行hash。
    * 加上4个空字节（把hash结果扩展成24个字节）。
    * 得到的结果就是第一个随机数Nonce1。
    * 反转Nonce1的最后一个bit就得到了第二个随机数Nonce2。
    * 如果我们有比较小的临时公钥的话，就用Nonce1来进行接受，用Nonce2来进行发送，如果临时公钥比较大的话，就相反。
6. 从现在开始所有的通信都是经过共享密钥和nonce加密过的，每次nonce都会加2。
7. 现在我们有了加密通道，但是还需要进行验证。
8. 产生一个共同的挑战去签名：
    * 对排序（从小到大）并连接起来的临时公钥进行SHA256.
9. 用我们自己的私钥对这个公共的挑战进行签名。
10. 发送经过go-wire编码过的公钥和签名给peer。
11. 等待接受对方的公钥和签名。
12. 用对方公钥对公共的挑战的签名进行检验。

如果这是一个呼出的连接（就是说我们拨打的节点），我们用节点的ID，认证节点的公钥是否和我们的拨打的ID进行匹配，也就是说：peer.PubKey.Address() == <ID>

从现在开始连接是认证过的，所有的传输都是加密的。

注意：只有拨打者能认证节点的ID，但是这正是我们所关心，因为我们希望确保我们加入的网络节点是我们想加入的节点网络（而不是被中间人所劫持的）。

#### 节点过滤
在继续之前，我们会检查新节点是否和我们自己或者已经存在的节点同样的ID，如果是这样子的话，我们断开连接。

我们同样可以通过ABCI APP管理的白名单的方式来检查节点的地址和公钥，如果白名单是开启的，且peer是不符合的，连接会的终止。

#### Tendermint 版本握手
Tendermint 版本握手允许节点互换它们的Nodeinfo：
```
type NodeInfo struct {
  ID         p2p.ID
  Moniker    string
  Network    string
  RemoteAddr string
  ListenAddr string
  Version    string
  Channels   []int8
  Other      []string
}
```
如果有以下情况，连接会断开：
1. peer.NodeInfo.ID != perrConn.ID
2. peer.NodeInfo.Version 不是按照x.x.x格式。
3. peer.NodeInfo.Version主版本号好和我们的主版本号好不一样。
4. peer.NodeInfo.Version的次版本号和我们的主版本号好不一样。
5. peer.NodeInfo.Network和我们的主版本号好不一样。
6. peer.Channels不和我们的Channels相关联。

到这个的话，如果连接还没有断开，那表明节点是有效的，它会被通过switch利用reactor的AddPeer方法加入到所有的reactor中。注意每个reactor也许可能处理多个channels。

#### 连接激活
一旦一个节点给添加，所有进入的消息都是通过reactor的Receive方法进行处理的，对外发出的消息会直接通过reactor的每个peer直接发出。典型的reactor会对每个peer都保持一个goroutine的方式来处理。
