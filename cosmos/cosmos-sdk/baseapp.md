### BaseApp 类型包含许多基于 Cosmos SDK 的应用程序的重要参数

```
    type BaseApp struct { // nolint: maligned
    // initialized on creation
    logger log.Logger
    name string // application name from abci.Info
    db dbm.DB // common DB backend
    cms sdk.CommitMultiStore // Main (uncached) state
    storeLoader StoreLoader // function to handle store loading, may be overridden with SetStoreLoader()
    router sdk.Router // handle any kind of legacy message
    queryRouter sdk.QueryRouter // router for redirecting query calls
    grpcQueryRouter *GRPCQueryRouter // router for redirecting gRPC query calls
    msgServiceRouter *MsgServiceRouter // router for redirecting Msg service messages
    interfaceRegistry types.InterfaceRegistry
    txDecoder sdk.TxDecoder // unmarshal []byte into sdk.Tx
    anteHandler sdk.AnteHandler // ante handler for fee and auth
    postHandler sdk.AnteHandler // post handler, optional, e.g. for tips
    initChainer sdk.InitChainer // initialize state with validators and state blob
    beginBlocker sdk.BeginBlocker // logic to run before any txs
    endBlocker sdk.EndBlocker // logic to run after all txs, and to determine valset changes
    addrPeerFilter sdk.PeerFilter // filter peers by address and port
    idPeerFilter sdk.PeerFilter // filter peers by node ID
    fauxMerkleMode bool // if true, IAVL MountStores uses MountStoresDB for simulation speed.

        // manages snapshots, i.e. dumps of app state at certain intervals
        snapshotManager *snapshots.Manager

        // volatile states:
        //
        // checkState is set on InitChain and reset on Commit
        // deliverState is set on InitChain and BeginBlock and set to nil on Commit
        checkState   *state // for CheckTx
        deliverState *state // for DeliverTx

        // an inter-block write-through cache provided to the context during deliverState
        interBlockCache sdk.MultiStorePersistentCache

        // absent validators from begin block
        voteInfos []abci.VoteInfo

        // paramStore is used to query for ABCI consensus parameters from an
        // application parameter store.
        paramStore ParamStore

        // The minimum gas prices a validator is willing to accept for processing a
        // transaction. This is mainly used for DoS and spam prevention.
        minGasPrices sdk.DecCoins

        // initialHeight is the initial height at which we start the baseapp
        initialHeight int64

        // flag for sealing options and parameters to a BaseApp
        sealed bool

        // block height at which to halt the chain and gracefully shutdown
        haltHeight uint64

        // minimum block time (in Unix seconds) at which to halt the chain and gracefully shutdown
        haltTime uint64

        // minRetainBlocks defines the minimum block height offset from the current
        // block being committed, such that all blocks past this offset are pruned
        // from Tendermint. It is used as part of the process of determining the
        // ResponseCommit.RetainHeight value during ABCI Commit. A value of 0 indicates
        // that no blocks should be pruned.
        //
        // Note: Tendermint block pruning is dependant on this parameter in conunction
        // with the unbonding (safety threshold) period, state pruning and state sync
        // snapshot parameters to determine the correct minimum value of
        // ResponseCommit.RetainHeight.
        minRetainBlocks uint64

        // application's version string
        version string

        // application's protocol version that increments on every upgrade
        // if BaseApp is passed to the upgrade keeper's NewKeeper method.
        appVersion uint64

        // recovery handler for app.runTx method
        runTxRecoveryMiddleware recoveryMiddleware

        // trace set will return full stack traces for errors in ABCI Log field
        trace bool

        // indexEvents defines the set of events in the form {eventType}.{attributeKey},
        // which informs Tendermint what to index. If empty, all events will be indexed.
        indexEvents map[string]struct{}

        // abciListeners for hooking into the ABCI message processing of the BaseApp
        // and exposing the requests and responses to external consumers
        abciListeners []ABCIListener

    }
```

1. CommitMultiStore：这是应用程序的主存储，它保存在每个块结束时提交的规范状态。此存储未缓存，这意味着它不用于更新应用程序的易失（未提交）状态。 CommitMultiStore 是一个多存储，即存储的存储。应用程序的每个模块都使用多存储中的一个或多个 KVStore 来持久化它们的状态子集.CommitMultiStore 使用 db 来处理数据持久性

2. Msg Service Router：msgServiceRouter 便于将 sdk.Msg 请求路由到相应的模块 Msg 服务进行处理。这里的 sdk.Msg 是指需要由服务处理以更新应用程序状态的事务组件，而不是实现应用程序与底层共识引擎之间接口的 ABCI 消息。

3. gRPC 查询路由器：grpcQueryRouter 有助于将 gRPC 查询路由到适当的模块以进行处理。这些查询本身不是 ABCI 消息，而是中继到相关模块的 gRPC 查询服务。

4. TxDecoder：用于解码底层 Tendermint 引擎中继的原始交易字节。

5. AnteHandler：该处理程序用于在收到交易时处理签名验证、费用支付和其他消息前执行检查。它在 CheckTx/RecheckTx 和 DeliverTx 期间执行。

6. InitChainer、BeginBlocker 和 EndBlocker：这些是应用程序从底层 Tendermint 引擎接收到 InitChain、BeginBlock 和 EndBlock ABCI 消息时执行的函数。

7. checkState：此状态在 CheckTx 期间更新，并在 Commit 时重置。

8. DeliverState：此状态在 DeliverTx 期间更新，并在 Commit 时设置为 nil，并在 BeginBlock 上重新初始化。

9. voteInfos：这个参数携带缺少预提交的验证者列表，要么是因为他们没有投票，要么是因为提议者没有包括他们的投票。此信息由 Context 携带，应用程序可以将其用于各种事情，例如惩罚缺席的验证者。

10. minGasPrices：这个参数定义了节点接受的最低 gas 价格。这是一个本地参数，意味着每个全节点可以设置不同的 minGasPrices。 CheckTx 时在 AnteHandler 中使用，主要作为垃圾邮件防护机制。只有当交易的 gas 价格大于 minGasPrices 中的最低 gas 价格之一时，交易才会进入内存池（例如，如果 minGasPrices == 1uatom,1photon，则交易的 gas-price 必须大于 1uatom 或 1photon）。

### BaseApp 维护两个主要的 volatile 状态和一个根或主状态。主状态是应用程序的规范状态，易失状态 checkState 和 DeliverState 用于处理在提交期间进行的主状态之间的状态转换。

1. 在内部，只有一个 CommitMultiStore，我们称之为主状态或根状态。从这个根状态，我们使用一种称为存储分支的机制（由 CacheWrap 函数执行）派生出两个易失状态。类型可以说明[如下](./img/baseapp_state_types.png)

2. 在 InitChain 期间，两个 volatile 状态 checkState 和 DeliverState 通过分支根 CommitMultiStore 来设置。任何后续读取和写入都发生在 CommitMultiStore 的分支版本上。为了避免不必要的主状态往返，对分支存储的所有读取都被缓存。[see picture](./img/baseapp_state-initchain.png)

3. 在 CheckTx 期间，基于根存储的最后提交状态的 checkState 用于任何读取和写入。这里我们只执行 AnteHandler 并验证事务中的每条消息都存在一个服务路由器。注意，当我们执行 AnteHandler 时，我们会分支已经分支的 checkState。这有副作用，如果 AnteHandler 失败，状态转换将不会反映在 checkState 中——即 checkState 仅在成功时更新。[see picture](./img/baseapp_state-checktx.png)

4. 在 BeginBlock 期间，deliverState 设置为在后续 DeliverTx ABCI 消息中使用。 DeliverState 基于来自根存储的最后提交状态并且是分支的。请注意，deliverState 在提交时设置为 nil。[see picture](./img/baseapp_state-begin_block.png)

5. DeliverTx 的状态流几乎与 CheckTx 相同，只是状态转换发生在 DeliverState 上并且事务中的消息被执行。与 CheckTx 类似，状态转换发生在双分支状态——deliverState。成功的消息执行导致写入被提交到 deliverState。请注意，如果消息执行失败，来自 AnteHandler 的状态转换将保持不变。[see picture](./img/baseapp_state-deliver_tx.png)

6. 在 Commit 期间，deliverState 中发生的所有状态转换最终都会写入根 CommitMultiStore，而根 CommitMultiStore 又会提交到磁盘并产生新的应用程序根哈希。这些状态转换现在被认为是最终的。最后，checkState 设置为新提交的状态，deliverState 设置为 nil 以在 BeginBlock 上重置。[see picture](./img/baseapp_state-commit.png)

```

```
