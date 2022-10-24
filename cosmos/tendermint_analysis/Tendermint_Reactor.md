# Tendermint Reactor

## Reactor 概述

>Reactor  直译是反应器(组件)，可以理解为异步式编程，关注数据处理，方便各模块之间数据交互。里面有各种各样的异步反应(功能)，按照内存池，区块，见证人和共识处理分类各自承载了的对应业务的一些方法逻辑, 它是和整个P2P网络进行交互的组件， 在Tendermint中有5个Reactor实例分别是Mempool,Blockchain,Csonsensus,Evidence,Pex. 

## Mempool Reactor

> 内存池的作用是为了保存从其他peer或者自身接收到的还未被打包的交易

Mempool 文件结构

`mempool
├── bench_test.go
├── cache_test.go
├── clist_mempool.go // mempool 的链表实现逻辑 最重要的属性就是双向链表txs
├── clist_mempool_test.go
├── codec.go
├── doc.go
├── errors.go
├── mempool.go	// mempool 接口定义
├── metrics.go
├── reactor.go  // mempool 的reactor实现逻辑
└── reactor_test.go`

​				其中doc.go 文件中的注释解释了主要功能和实现方式

> ```
> // The mempool pushes new txs onto the proxyAppConn.
> 内存池向应用推送新的交易数据
> // It gets a stream of (req, res) tuples from the proxy.
> 内存池从应用代理处获取原始交易信息
> // The mempool stores good txs in a concurrent linked-list.
> // Multiple concurrent go-routines can traverse this linked-list
> // safely by calling .NextWait() on each element.
> 
> // So we have several go-routines:
> // 1. Consensus calling Update() and Reap() synchronously
> // 2. Many mempool reactor's peer routines calling CheckTx()
> // 3. Many mempool reactor's peer routines traversing the txs linked list
> // 4. Another goroutine calling GarbageCollectTxs() periodically
> 
> // To manage these goroutines, there are three methods of locking.
> // 1. Mutations to the linked-list is protected by an internal mtx (CList is goroutine-safe)
> // 2. Mutations to the linked-list elements are atomic
> // 3. CheckTx() calls can be paused upon Update() and Reap(), protected by .proxyMtx
> 
> // Garbage collection of old elements from mempool.txs is handlde via
> // the DetachPrev() call, which makes old elements not reachable by
> // peer broadcastTxRoutine() automatically garbage collected.
> 1. 共识引擎调用Update()和Reap*()方法去更新内存池中的交易
> 2. 内存池中的交易池使用双向链表保存交易数据
> 3. 内存池在每次收到交易会首先放到交易cache中， 然后将交易提交给应用(通过ABCI), 应用的Check_tx决定交易是否可以放入交易池
> 
> ```

```
func NewCListMempool(
	config *cfg.MempoolConfig,
	proxyAppConn proxy.AppConnMempool,
	height int64,
	options ...CListMempoolOption,
) *CListMempool {
	mempool := &CListMempool{
		config:        config,
		proxyAppConn:  proxyAppConn, // 设置应用连接属性
		txs:           clist.New(), // goroutine-safe的双向链表结构，用来存储检查过的交易数据， 可以理解为交易池
		height:        height,
		rechecking:    0,
		recheckCursor: nil,
		recheckEnd:    nil,
		logger:        log.NewNopLogger(),
		metrics:       NopMetrics(),
	}
	if config.CacheSize > 0 {
		mempool.cache = newMapTxCache(config.CacheSize) // 内存池缓存 
	} else {
		mempool.cache = nopTxCache{}
	}
	// 设置了代理连接的回调函数为globalCb(req *abci.Request, res *abci.Response)
	// 内存池在收到交易后会把交易提交给APP 根据APP的返回来决定后续这个交易
	// 所以在APP处理完提交的交易后回调mempool.globalCb进而让mempool来继续决定当前交易如何处理
	// 以 abci echo命令举例 abci/client/local_client.go:54 最后返回了 app.callback()的结果
	// 在 appConnConsensus 中也有SetResponseCallback接口
	proxyAppConn.SetResponseCallback(mempool.globalCb)
	for _, option := range options {
		option(mempool)
	}
	return mempool
}
// 在new 内存池的时候 options 有3个分别是 
mempl.WithMetrics(memplMetrics),
mempl.WithPreCheck(sm.TxPreCheck(state)),
mempl.WithPostCheck(sm.TxPostCheck(state)),
在 app checktx返回之后 调用
```

 doc.go注释中提到了 「 Consensus calling Update() and Reap() synchronously」共识引擎同步调用更新和获取方法

共识引擎和内存池的关系，应该是从共识引擎内存池取出交易-->执行交易--->打包交易--->共识引擎告诉内存池应该移除的交易。 `Reap`作用就是从内存池中取出交易

```
func (mem *CListMempool) ReapMaxTxs(max int) types.Txs {
	// 加并发锁
	mem.proxyMtx.Lock()
	// 解锁
	defer mem.proxyMtx.Unlock()

	if max < 0 {
		max = mem.txs.Len()
	}

	for atomic.LoadInt32(&mem.rechecking) > 0 {
		// TODO: Something better?
		// 内存检查延缓
		time.Sleep(time.Millisecond * 10)
	}

	txs := make([]types.Tx, 0, tmmath.MinInt(mem.txs.Len(), max))
	// 从链表中循环获取交易数据 
	for e := mem.txs.Front(); e != nil && len(txs) <= max; e = e.Next() {
		memTx := e.Value.(*mempoolTx)
		txs = append(txs, memTx.tx)
	}
	return txs
}
```

​	CheckTx方法把新的交易提交给APP， 然后决定是否被加入内存池中, CheckTx在何处被调用在下面。

``` 
func (mem *CListMempool) CheckTx(tx types.Tx, cb func(*abci.Response), txInfo TxInfo) (err error) {
	// 并发加锁
	mem.proxyMtx.Lock()
	// use defer to unlock mutex because application (*local client*) might panic
	defer mem.proxyMtx.Unlock()
	// 内存池几个配置值
	var (
		memSize  = mem.Size()
		txsBytes = mem.TxsBytes()
		txSize   = len(tx)
	)
	// 超过内存池大小 或者 交易大小超过设置最大值 返回error
	if memSize >= mem.config.Size ||
		int64(txSize)+txsBytes > mem.config.MaxTxsBytes {
		return ErrMempoolIsFull{
			memSize, mem.config.Size,
			txsBytes, mem.config.MaxTxsBytes}
	}
	
	// The size of the corresponding amino-encoded TxMessage
	// can't be larger than the maxMsgSize, otherwise we can't
	// relay it to peers.
	// 比较大小
	if txSize > mem.config.MaxTxBytes {
		return ErrTxTooLarge{mem.config.MaxTxBytes, txSize}
	}

	if mem.preCheck != nil {
		if err := mem.preCheck(tx); err != nil {
			return ErrPreCheck{err}
		}
	}

	// CACHE 加入内存池cache 如果cache中存在此交易则返回false
	if !mem.cache.Push(tx) {
		// Record a new sender for a tx we've already seen.
		// Note it's possible a tx is still in the cache but no longer in the mempool
		// (eg. after committing a block, txs are removed from mempool but not cache),
		// so we only record the sender for txs still in the mempool.
		if e, ok := mem.txsMap.Load(txKey(tx)); ok {
			memTx := e.(*clist.CElement).Value.(*mempoolTx)
			memTx.senders.LoadOrStore(txInfo.SenderID, true)
			// TODO: consider punishing peer for dups,
			// its non-trivial since invalid txs can become valid,
			// but they can spam the same tx with little cost to them atm.

		}

		return ErrTxInCache
	}
	// END CACHE

	// WAL
	if mem.wal != nil {
		// TODO: Notify administrators when WAL fails
		_, err := mem.wal.Write([]byte(tx))
		if err != nil {
			mem.logger.Error("Error writing to WAL", "err", err)
		}
		_, err = mem.wal.Write([]byte("\n"))
		if err != nil {
			mem.logger.Error("Error writing to WAL", "err", err)
		}
	}
	// END WAL

	// NOTE: proxyAppConn may error if tx buffer is full
	// 查看应用状态 在localClient中忽略了这个检查
	if err = mem.proxyAppConn.Error(); err != nil {
		return err
	}
	// 通过abci interface 把交易传给proxyAppCon 的 checktx 异步接口
	reqRes := mem.proxyAppConn.CheckTxAsync(abci.RequestCheckTx{Tx: tx})
	// 设置请求 cb 为之前初始化内存池时的cb
	reqRes.SetCallback(mem.reqResCb(tx, txInfo.SenderID, txInfo.SenderP2PID, cb))

	return nil
}
```

交易被简单判断之后加入了cache，然后提交给给app， proxyAppConn是一个ABCI接口，通过之前ABCI的分析得知这个ABCI的实例化对象是 localClient，CheckTxAsync代码如下

```

func (app *localClient) CheckTxAsync(req types.RequestCheckTx) *ReqRes {
	app.mtx.Lock()
	defer app.mtx.Unlock()

	res := app.Application.CheckTx(req)
	return app.callback(
		types.ToRequestCheckTx(req),
		types.ToResponseCheckTx(res),
	)
}
app cb回调下面的方法
func (mem *CListMempool) resCbRecheck(req *abci.Request, res *abci.Response) {
	....
	// gas 费检查
	if mem.postCheck != nil {
			postCheckErr = mem.postCheck(tx, r.CheckTx)
		}
	// 根据app checktx返回的状态来操作是否要从内存池中删除交易
	if (r.CheckTx.Code == abci.CodeTypeOK) && postCheckErr == nil {
			// Good, nothing to do.
		} else {
			// Tx became invalidated due to newly committed block.
			mem.logger.Info("Tx is no longer valid", "tx", txID(tx), "res", r, "err", postCheckErr)
			// NOTE: we remove tx from the cache because it might be good later
			mem.removeTx(tx, mem.recheckCursor, true)
		}
	....
}
```

p2p/peer.go:386 因为mempool实现了Reactor，所以MConnecttion中当收到peer发送的消息之后调用了各个Reactor 的 Receive( )方法。

```
err := memR.mempool.CheckTx(msg.Tx, nil, txInfo) // 调用 mempool 的checktx方法 试图将交易加入本地交易池
```

```
func (memR *MempoolReactor) AddPeer(peer p2p.Peer) {
 // 启动一个goroutine 试图把内存池中的交易实时广播到对应的peer
	go memR.broadcastTxRoutine(peer)
}
各个 AddPeer 在此处 p2p/switch.go:810  被addPeer调用
而 addPeer 最终是在 Switch OnStart -> acceptRoutine -> addPeer  p2p/switch.go:234 被调用
这就是完整的调用链
```



## Consensus Reactor

共识reactor包含了用于管理Tendermint内部共识状态机的ConsensusState服务，State结构体。switch start时会把reactor开启，在consensus reactor的AddPeer方法中会创建一个广播的goroutine用来开启ConsensusState服务。因为每个peer都被加到了共识reactor中，它会创建（和管理）相对应的节点状态。会为每个peer开启以下三个routine：Gossip Data Routine，Gossip Data Routine，QueryMaj23Routine

```
// Begin routines for this peer.
	go conR.gossipDataRoutine(peer, peerState)
	go conR.gossipVotesRoutine(peer, peerState)
	go conR.queryMaj23Routine(peer, peerState)

```

consensus reactor会负责对来自于peer的信息进行解码，还有根据消息的类型和数据进行相关的处理，处理通常是更新相应peer的state状态，还有对一些消息（ProposalMessage, ProposalPOLMessage, BlockPartMessage, VoteMessage）进行转发给ConsensusState模块进行进一步的处理