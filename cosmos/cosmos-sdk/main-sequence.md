# 总体流程

#CheckTX
rpc端口接受到要广播的请求，会调用ABCI APP的CheckTX方法，但不是直接调用，而是通过mempool包调用，ABCI APP会在CheckTX方法中检验Tx是否合法并返回检查结果，mempool根据返回的结果来决定是否把tx放进内存池，而mempoolReactor会在broadcastTxRoutine()方法中不停的读取内存池中的交易并发送给相连节点。

#BeginBlock....

`tendermint/consensus`包处理共识逻辑，在共识完毕时调用`state.go:finalizeCommit()`方法把块加入链，并更新状态信息。`finalizeCommit`方法体中最主要调用`tendermint/state/excution.go:ApplyBlock()`来和ABCI APP进行通信。具体步骤是首先调用`execBlockOnProxyApp()`方法，此方法会按照顺序的调用BeginBlock，DeliverTx,EndBlock方法来和ABCI通信，最后通过调用Commit方法通知ABCI APP更新提交状态。





