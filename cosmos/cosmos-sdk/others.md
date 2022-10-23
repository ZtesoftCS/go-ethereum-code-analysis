#### 如何加入到同一个网络

网络是根据以下两个参数进行区分：

1. chain-id
2. genesis.json

#### P2P的连接

每个peer对象都有一个MConnection对象，MConnection对象复用一个TCP连接，几个具有优先级的Channel对接入的流进行处理，每个channel都具有一个全局的ID，每个Channel的ID和优先级都是在MConnection初始化时确定的。

MConnection对象支持以下三种消息类型：
1. Ping
2. Pong
3. Msg

Ping，Pong消息内容只有一个byte大小的数据，分别是0x1和0x2.

当一个节点在MConnection对象经过`pingTimeout`的时间后

### tendermint的默认配置

所有的默认都在`tendermint/tendermint/config/config.go`文件里面，配置文件的模版在`tendermint/tendermint/config/toml.go`里面。

### 数据库
ABCI APP对象有两个个state对象：deliverState和setCheckState。setCheckState在每个块被commit以后就会更新成最新的块状态，而deliverState则会在每个块commit以后重置为nil。
防止出现数据不一致的情况，写数据都是首先写到cache中，然后在用Write()方法写到数据库中。

### ABCI

tendermint/abci包含了clien包和server包，client包里面有三种类型的客户端封装：socket，grpc，和local本地调用，local本地调用会直接调用cosomos-sdk/baseapp包提供的方法来达到tendermint和ABCI APP的通信。server包是ABCI APP启动时用来启动ABCI服务器的。client包下面的socketclient，grpcclient就是对server包下面启动的服务调用的封装。

而cosmos-sdk/client是对tendermint-rpc服务调用的封装和对数据库的直接调用。cosmos-sdk/server包只是用来启动一个node的，node的启动会包含rpc服务的启动。

### 创建块
创建节点对象时会首先检查数据库里面的genesis信息，如果数据库中没有相关信息就会从genesis.json文件中读取创始块信息，并把此信息存储到db中。然后一个Handshaker对象，此对象在proxyApp.start()方法中会调用Handshake()方法，此方法会调用ReplayBlocks()方法，此方法会检查当前节点的状态，如果没有一个区块高度为0的话，就会调用app.InitChainSync()方法进行初ABCI APP的块高比较低的话，就开始调用(h *Handshaker) ReplayBlocks()方法进行同步，同步的具体方法是：execBlockOnProxyApp()，这个方法就会调用ABCI APP的BeginBlock,DeliverTx,EndBlock,Commit等等方法来把块同步到ABCI APP的数据库上。
