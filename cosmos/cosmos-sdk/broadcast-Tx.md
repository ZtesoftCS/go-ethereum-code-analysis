### Tx数据流转流程

客户端通过调用`rpc/client`包提供的`BroadcastTxCommmit()`把交易提交给节点，节点在`rpc/core/mempool.go`文件中处理提交的交易。处理流程如下：
1. 首先对交易的状态进行订阅。
2. 然后通过调用`mempool/mempool.go:CheckTx()`方法把交易传给ABCI APP，APP会对这个tx进行正确性验证。传递tx需要借助`proxy/multi_app_conn.go`文件的代理方法。
3. 然后等待tx所在块block已经被验证确认的消息，等待超时时间为两分钟。对订阅的tx事件进行回调的处理在`state/execution.go:fireEvents()`方法里面，这个方法在`(blockExec *BlockExecutor) ApplyBlock()`方法的最后面调用，也就意味着块信息已经和ABCI APP通知过了。
4. 在`NewMempool()`方法中会调用`proxyAppConn.SetResponseCallback(mempool.resCb)`方法，此方法会把`mempool.resCb`方法注册到`abci/client`对象里面，用来实现异步结果处理。在`(mem *Mempool) resCbNormal()`方法中，如果是CheckTx异步请求的结果的话，会把tx通过`mem.txs.PushBack(memTx)`方法放到内存池中。此内存池其实也就是一个自定义的list，没有对tx进行排优先级。
5. `(memR *MempoolReactor) broadcastTxRoutine()`方法会不停的按照list顺序遍历内存池，把得到的tx通过`peer`包发送给别的节点。
6. 
