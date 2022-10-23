
### 全节点开启

`cosmos-sdk/server`包的`start.go`有两个方法，分别以两种模式进行启动，一种是把tendermint当作lib包含起来，一起启动。另外一种是tendermint作为单独的一个程序启动，app通过socket和tendermint进行通信。

#### TM-lib模式
调用`tendermint/tendermint/node/node.go:NewNode()`方法，此方法做了很多工作，具体如下：
1. 从数据中后去state对象，如果在数据库中没有找到此对象，则从genesis创世文件中产生此对象并持久化到数据库。
2. 调用`tendermint/proxy/multi_app_conn.go:NewAppConns()`方法创建appConn对象，然后调用此对象的`Start()`方法，此方法非常关键，会创建三个对象，分别为：mempool,query,consensus，因为是TM-lib模式，所以这三个对象不走socket和ABCI APP通信，而是直接调用自定义的ABCI APP方法。然后再进行握手，握手的意思是TM和ABCI APP的数据库进行同步的意思。握手的具体实现在`tendermint/consensus/relay.go`文件中定义。
3. 然后检查privValidator是否是外部定义的？好像验证者可以是外部一定独立程序，通过socket和TM通讯？
4. 检查自己是否是验证者。检查的方法就是看自己的地址是否在state对象包含的validatorSet中。
5. 创建MempoolReactor，处理peer节点传来的tx，其中一个重要的步骤就是调用ABCI APP自己定义的CheckTX方法。
6. 创建EvidenceReactor，记录validator的犯罪证据，证据最主要包括一些作案当时的区块高度，验证人集合等。详细情况待研究。
7. 创建BlockchainReactor，这个reactor比较重要，里面实现了BeginBlockTx，DevliverTx，Commit等方法的调用。
8. 创建ConsensusReactor，这个reactor实现了对订阅的处理，TM共识算法在投票等阶段会通过这边的订阅来通知外部。
9. 然后处理PEX，PEX是peer exchange的缩写，在这边引入来一个trustMetric的概念，应该是用来处节点之间连接的问题。具体情况待研究，
10. 哪些阶段可以连接，哪些节点不可以连接，可以通过config.FilterPeers来配置。
11. 然后处理TxIndexer，用来对每天一个Tx进行索引的。例如：给tx一个tag，或者多个tag，然后以tag为key，tx为值进行key/value的持久化。tx的tag应该是可以任意的，常用的应该是tx的hash。
12. 开启profile server，用来进行性能测试的，

最后启动`start()`方法，在此方法中会调用`startRPC()`方法来启动TM对外的rpc服务。在startRPC方法中会调用`ConfigRPC()`方法，此方法会把node对象的很多属性对象设置到`tendermint/rpc/core/pipe.go`包中，rpc-core才是真正提供rpc服务的包。

#### tendermint启动时依赖App

tendermint启动时会建立三个socket连接，分别为：mempool,query,consensus，具体流程如下：`tendermint/tendermint/node/node.go`的`NewNode()`方法调用`proxyApp.Start()`，此方法`(app *multiAppConn) OnStart()`会创建三个client对象，也就是对应上面的三个连接。`mempool`和`consensus`是在tendermint core运行时主动调用app的，用来进行tx的验证等，但是`query`不一样，它是在外界调用tendermint core时用来调用app来获取数据的。`mempool`调用发生在`tendermint/tendermint/mempool/reactor.go`文件的`(memR *MempoolReactor) BroadcastTx()`方法里面。而`consensus`调用发生在`tendermint/tendermint/state/execution.go`文件的`execBlockOnProxyApp()`方法里面。
