### 全节点开启

`cosmos-sdk/server`包的`start.go`有两个方法，分别以两种模式进行启动，一种是把 tendermint 当作 lib 包含起来，一起启动。另外一种是 tendermint 作为单独的一个程序启动，app 通过 socket 和 tendermint 进行通信。

#### TM-lib 模式

调用`tendermint/tendermint/node/node.go:NewNode()`方法，此方法做了很多工作，具体如下：

1. 从数据中后去 state 对象，如果在数据库中没有找到此对象，则从 genesis 创世文件中产生此对象并持久化到数据库。
2. 调用`tendermint/proxy/multi_app_conn.go:NewAppConns()`方法创建 appConn 对象，然后调用此对象的`Start()`方法，此方法非常关键，会创建三个对象，分别为：mempool,query,consensus，因为是 TM-lib 模式，所以这三个对象不走 socket 和 ABCI APP 通信，而是直接调用自定义的 ABCI APP 方法。然后再进行握手，握手的意思是 TM 和 ABCI APP 的数据库进行同步的意思。握手的具体实现在`tendermint/consensus/relay.go`文件中定义。
3. 然后检查 privValidator 是否是外部定义的？好像验证者可以是外部一定独立程序，通过 socket 和 TM 通讯？
4. 检查自己是否是验证者。检查的方法就是看自己的地址是否在 state 对象包含的 validatorSet 中。
5. 创建 MempoolReactor，处理 peer 节点传来的 tx，其中一个重要的步骤就是调用 ABCI APP 自己定义的 CheckTX 方法。
6. 创建 EvidenceReactor，记录 validator 的犯罪证据，证据最主要包括一些作案当时的区块高度，验证人集合等。详细情况待研究。
7. 创建 BlockchainReactor，这个 reactor 比较重要，里面实现了 BeginBlockTx，DevliverTx，Commit 等方法的调用。
8. 创建 ConsensusReactor，这个 reactor 实现了对订阅的处理，TM 共识算法在投票等阶段会通过这边的订阅来通知外部。
9. 然后处理 PEX，PEX 是 peer exchange 的缩写，在这边引入来一个 trustMetric 的概念，应该是用来处节点之间连接的问题。具体情况待研究，
10. 哪些阶段可以连接，哪些节点不可以连接，可以通过 config.FilterPeers 来配置。
11. 然后处理 TxIndexer，用来对每天一个 Tx 进行索引的。例如：给 tx 一个 tag，或者多个 tag，然后以 tag 为 key，tx 为值进行 key/value 的持久化。tx 的 tag 应该是可以任意的，常用的应该是 tx 的 hash。
12. 开启 profile server，用来进行性能测试的，

最后启动`start()`方法，在此方法中会调用`startRPC()`方法来启动 TM 对外的 rpc 服务。在 startRPC 方法中会调用`ConfigRPC()`方法，此方法会把 node 对象的很多属性对象设置到`tendermint/rpc/core/pipe.go`包中，rpc-core 才是真正提供 rpc 服务的包。

#### tendermint 启动时依赖 App

tendermint 启动时会建立 4 个 socket 连接，分别为：mempool,query,consensus，snapshot 具体流程如下：`tendermint/tendermint/node/node.go`的`DefaultNewNode()`方法调用`newNode`, 然后调用`createAndStartProxyAppConns()`得到 proxyApp，`proxyApp.Start()`，此方法`(app *multiAppConn) OnStart()`会创建 4 个 client 对象，也就是对应上面的 4 个连接。

`mempool`和`consensus`是在 tendermint core 运行时主动调用 app 的，用来进行 tx 的验证等，但是`query`不一样，它是在外界调用 tendermint core 时用来调用 app 来获取数据的。`mempool`调用发生在`tendermint/tendermint/mempool/reactor.go`文件的`(memR *MempoolReactor) BroadcastTx()`方法里面。而`consensus`调用发生在`tendermint/tendermint/state/execution.go`文件的`execBlockOnProxyApp()`方法里面。
