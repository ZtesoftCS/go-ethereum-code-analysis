---
title: "以太坊挖矿逻辑流程"
menuTitle: "挖矿流程"
date: 2019-07-31T22:58:46+08:00
draft: false
weight: 20303
---

上一篇文章中，有介绍是如何发出挖矿工作信号的。当有了挖矿信号后，就可以开始挖矿了。

先回头看看，在讲解[挖矿的第一篇文章]({{< ref "/part2/miner" >}})中，有讲到挖矿流程。这篇文章将讲解挖矿中的各个环节。

![以太坊挖矿流程](https://img.learnblockchain.cn/book_geth/image-20190721114625930.png!de)

## 挖矿代码方法介绍

在继续了解挖矿过程之前，先了解几个miner方法的作用。

+ commitTransactions：提交交易到当前挖矿的上下文环境(environment)中。上下文环境中记录了当前挖矿工作信息，如当前挖矿高度、已提交的交易、当前State等信息。
+ updateSnapshot：更新 environment 快照。快照中记录了区块内容和区块StateDB信息。相对于把当前 environment 备份到内存中。这个备份对挖矿没什么用途，只是方便外部查看 PendingBlock。
+ commitNewWork：重新开始下一个区块的挖矿的第一个环节“构建新区块”。这个是整个挖矿业务处理的一个核心，值得关注。
+ commit： 提交新区块工作，发送 PoW 计算信号。这将触发竞争激烈的 PoW 寻找Nonce过程。

## 挖矿工作管理

什么时候可以进行挖矿？如下图所述，挖矿启动工作时由 mainLoop 中根据三个信号来管理。首先是新工作启动信号(newWorkCh)、再是根据新交易信号(txsCh)和最长链链切换信号(chainSideCh)来管理挖矿。

![挖矿工作信号](https://img.learnblockchain.cn/book_geth/image-20190725220835554.png!de)

三种信号，三种管理方式。

### 新工作启动信号

这个信号，意思非常明确。一旦收到信号，立即开始挖矿。

```go
//miner/worker.go:409
case req := <-w.newWorkCh:
   w.commitNewWork(req.interrupt, req.noempty, req.timestamp)
```

这个信号的来源，已经在上一篇文章 [挖矿工作信号监控]({{< ref "signal.md" >}})中讲解。信号中的各项信息也来源与外部，这里仅仅是忠实地传递意图。

### 新交易信号

在[交易池]({{< ref "/part2/txpool" >}})文章中有讲到，交易池在将交易推入交易池后，将向事件订阅者发送 NewTxsEvent。在 miner 中也订阅了此事件。

```go
worker.txsSub = eth.TxPool().SubscribeNewTxsEvent(worker.txsCh)
```

当接收到新交易信号时，将根据挖矿状态区别对待。当尚未挖矿(`!w.isRunning()`)，但可以挖矿`w.current != nil`时❶，将会把交易提交到待处理中。

```go
//miner/worker.go:451
case ev := <-w.txsCh:
   if !w.isRunning() && w.current != nil {//❶
      w.mu.RLock()
      coinbase := w.coinbase
      w.mu.RUnlock()

      txs := make(map[common.Address]types.Transactions)
      for _, tx := range ev.Txs {//❷
         acc, _ := types.Sender(w.current.signer, tx)
         txs[acc] = append(txs[acc], tx)
      }
      txset := types.NewTransactionsByPriceAndNonce(w.current.signer, txs)//❸
      w.commitTransactions(txset, coinbase, nil)//❹
      w.updateSnapshot()//❺
   } else {
      if w.config.Clique != nil && w.config.Clique.Period == 0 {//❻
         w.commitNewWork(nil, false, time.Now().Unix())
      }
   }
   atomic.AddInt32(&w.newTxs, int32(len(ev.Txs)))//❼
```

首先，将新交易按发送者分组❷后，根据交易价格和Nonce值排序❸。形成一个有序的交易集后，依次提交每笔交易❹。最新完毕后将最新的执行结果进行快照备份❺。当正处于 PoA挖矿，右允许无间隔出块时❻，则将放弃当前工作，重新开始挖矿。

最后，不管何种情况都对新交易数计加❼。但实际并未使用到数据量，仅仅是充当是否有进行中交易的一个标记。

总得来说，新交易信息并不会干扰挖矿。而仅仅是继续使用当前的挖矿上下文，提交交易。也不用考虑交易是否已处理， 因为当交易重复时，第二次提交将会失败。

###最长链链切换信号

当一个区块落地成功后，有可能是在另一个分支上。当此分支的挖矿难度大于当前分支时，将发生最长链切换。此时 miner 将需要订阅从信号，以便更新叔块信息。

```go
//miner/worker.go:412
case ev := <-w.chainSideCh:
   if _, exist := w.localUncles[ev.Block.Hash()]; exist {//❶
      continue
   }
   if _, exist := w.remoteUncles[ev.Block.Hash()]; exist {
      continue
   }
   if w.isLocalBlock != nil && w.isLocalBlock(ev.Block) {//❷
      w.localUncles[ev.Block.Hash()] = ev.Block
   } else {
      w.remoteUncles[ev.Block.Hash()] = ev.Block
   }
   if w.isRunning() && w.current != nil && w.current.uncles.Cardinality() < 2 {//❸
      start := time.Now()
      if err := w.commitUncle(w.current, ev.Block.Header()); err == nil {//❹
         var uncles []*types.Header
         w.current.uncles.Each(func(item interface{}) bool {
            //...
         })
         w.commit(uncles, nil, true, start)//❺
      }
   }
```

短时间内，分支切换可能是频繁的。挖矿一直再相互竞争。如果接受到的区块，已经在叔块集中则忽略❶，没有则记录到叔块中❷。因为区块奖励是包含叔块奖励的，因此如果还在挖矿中，而叔块数量不到2个时❸。可以不再处理交易，一旦此区块加入叔块集成功❹，则直接结束交易处理，立刻将当前已处理的交易组装成区块，生成此区块的 PoW 计算信号❺。

## 挖矿流程环节

当开始新区块挖矿时，第一步就是构建区块，打包出包含交易的区块。在打包区块中，是按逻辑顺序依次组装各项信息。如果你对区块内容不清楚，请先查阅文章[区块结构]({{< ref "part1/block.md" >}})。

### 设置新区块基本信息

挖矿是在竞争挖下一个区块，需要把最新高度的区块作为父块来确定新区块的基本信息❶。

```go
//miner/worker.go:829
parent := w.chain.CurrentBlock()//❶

if parent.Time() >= uint64(timestamp) {//❷
   timestamp = int64(parent.Time() + 1)
}
if now := time.Now().Unix(); timestamp > now+1 {
   wait := time.Duration(timestamp-now) * time.Second
   log.Info("Mining too far in the future", "wait", common.PrettyDuration(wait))
   time.Sleep(wait)//❸
}
num := parent.Number()
header := &types.Header{//❹
   ParentHash: parent.Hash(),
   Number:     num.Add(num, common.Big1),
   GasLimit:   core.CalcGasLimit(parent, w.gasFloor, w.gasCeil),
   Extra:      w.extra,
   Time:       uint64(timestamp),
}
if w.isRunning() {
		if w.coinbase == (common.Address{}) {
			log.Error("Refusing to mine without etherbase")
			return
		}
		header.Coinbase = w.coinbase//❺
}
```

先根据父块时间戳调整新区块的时间戳。如果新区块时间戳还小于父块时间戳，则直接在父块时间戳上加一秒。一种情是，新区块链时间戳比当前节点时间还快时，则需要稍做休眠❸，避免新出块属于未来。这也是区块时间戳可以作为区块链时间服务的一种保证。

有了父块，新块的基本信息是确认的。分别是父块哈希、新块高度、燃料上限、挖矿自定义数据、区块时间戳❹。

为了接受区块奖励，还需要设置一个不为空的矿工账户 Coinbase ❺。一个区块的挖矿难度是根据父块动态调整的，因此在正式处理交易前，需要根据共识算法设置新区块的挖矿难度❻。

```go
if err := w.engine.Prepare(w.chain, header); err != nil {//❻
   log.Error("Failed to prepare header for mining", "err", err)
   return
}
```

至此，区块头信息准备就绪。

### 准备上下文环境

为了方便的共享当前新区块的信息，是专门定义了一个  environment ，专用于记录和当前挖矿工作相关内容。为即将开始的挖矿，先创建一份新的上下文环境信息。

```go
	err := w.makeCurrent(parent, header)
	if err != nil {
		log.Error("Failed to create mining context", "err", err)
		return
	}
```

上下文环境信息中，记录着此新区块信息，分别有：

1. state：  状态DB，这个状态DB继承自父块。每笔交易的处理，实际上是在改变这个状态DB。
2. ancestors： 祖先区块集，用于检测叔块是否合法。
3. family:  近亲区块集，用于检测叔块是否合法。
4. uncles：已合法加入的叔块集。
5. tcount：    当请挖矿周期内已提交的交易数。
6. gasPool： 新区块可用燃料池。
7. header： 新区块区块头。
8. txs:     已提交的交易集合。
9. receipts： 已提交交易产生的交易回执集合。

`makeCurrent`方法就是在初始化好上述信息。Cd3ecj6#QG4Q3hzEU

### 选择叔块

前面不断将非分支上的区块存放在叔块集中。在打包新块选择叔块时，将从叔块集中选择适合的叔块。

```go
//miner/worker.go:886
uncles := make([]*types.Header, 0, 2)
commitUncles := func(blocks map[common.Hash]*types.Block) {
   for hash, uncle := range blocks {//❷
      if uncle.NumberU64()+staleThreshold <= header.Number.Uint64() {
         delete(blocks, hash)
      }
   }
   for hash, uncle := range blocks {
      if len(uncles) == 2 {//❸
         break
      }
      if err := w.commitUncle(env, uncle.Header()); err != nil {
      } else {
         uncles = append(uncles, uncle.Header())
      }
   }
}
commitUncles(w.localUncles)//❶
commitUncles(w.remoteUncles)
```

叔块集分本地矿工打包区块和其他挖矿打包的区块。优先选择自己挖出的区块❶。选择时，将先删除太旧的区块，只从最近的7(staleThreshold)个高度中选择❷，但最多选择两个叔块放入新区块中❸。为什么不多选几个呢？这个不太清楚如何确定的。共识校验中叔块上限是2。

怎样的叔块才能够被选择呢？在 commitUncle 时将根据当前新区块的高度、父区块信息来决定是否加入。

```go
//miner/worker.go:645
func (w *worker) commitUncle(env *environment, uncle *types.Header) error {
   hash := uncle.Hash()
   //...
   if env.header.ParentHash == uncle.ParentHash {//❹
      return errors.New("uncle is sibling")
   }
   //...
   env.uncles.Add(uncle.Hash())
   return nil
}
```

唯一需要确认的是叔块必须在另一个分支上❹。总得来说，叔块是最近7个高度内上的区块，，且和当前新区块不在同一分支上、且不能重复包含在祖先块中。

![以太坊挖矿选择叔块](https://img.learnblockchain.cn/book_geth/image-20190726235839046.png!de)

### 提交交易

区块头已准备就绪，此刻开始从交易池拉取待处理的交易。将交易根据交易发送者分为两类，本地账户交易 localTxs 和外部账户交易 remoteTxs。本地交易优先不仅在交易池交易排队如此，在交易打包到区块中也是如此。本地交易优先，先将本地交易提交❸，再将外部交易提交❹。

```go
//miner/worker.go:917
pending, err := w.eth.TxPool().Pending()//❶
//...
localTxs, remoteTxs := make(map[common.Address]types.Transactions), pending//❷
for _, account := range w.eth.TxPool().Locals() {
   if txs := remoteTxs[account]; len(txs) > 0 {
      delete(remoteTxs, account)
      localTxs[account] = txs
   }
}
if len(localTxs) > 0 {//❸
   txs := types.NewTransactionsByPriceAndNonce(w.current.signer, localTxs)
   if w.commitTransactions(txs, w.coinbase, interrupt) {
      return
   }
}
if len(remoteTxs) > 0 {//❹
   txs := types.NewTransactionsByPriceAndNonce(w.current.signer, remoteTxs)
   if w.commitTransactions(txs, w.coinbase, interrupt) {
      return
   }
}
```

交易处理完毕后，便可进入下一个环节。

### 提交区块

在交易处理完毕时，会获得交易回执和变更了区块状态。这些信息已经实时记录在上下文环境 environment 中。

将 environment 中的数据整理，便可根据共识规则构建一个区块。

```go
//miner/worker.go:959
s := w.current.state.Copy()
block, err := w.engine.Finalize(w.chain, w.current.header, s, w.current.txs, uncles, w.current.receipts)
```

有了区块，就剩下最重要也是最核心的一步，执行 PoW 运算寻找 Nonce。这里并不是立刻开始寻找，而是发送一个PoW计算任务信号。

```go
//miner/worker.go:968
select {
case w.taskCh <- &task{receipts: receipts, state: s, block: block, createdAt: time.Now()}:
//...
}
```

### PoW计算寻找Nonce

之所以称之为挖矿，也是因为寻找Nonce的精髓所在。这是一道数学题，只能暴力破解，不断尝试不同的数字。直到找出一个符合要求的数字，这个数字称之为Nonce。寻找Nonce的过程，称之为挖矿。

寻找Nonce是需要时间的，耗时主要由区块难度决定。在代码设计上，以太坊是在 taskLoop 方法中，一直等待 task ❶。

```go
//miner/worker.go:508
case task := <-w.taskCh://❶
   //...
   sealHash := w.engine.SealHash(task.block.Header())//❷
   if sealHash == prev {
      continue
   }
   interrupt()//❹
   stopCh, prev = make(chan struct{}), sealHash

   if w.skipSealHook != nil && w.skipSealHook(task) {
      continue
   }
   w.pendingMu.Lock()
   w.pendingTasks[w.engine.SealHash(task.block.Header())] = task//❸
   w.pendingMu.Unlock()

   if err := w.engine.Seal(w.chain, task.block, w.resultCh, stopCh); err != nil {
      log.Warn("Block sealing failed", "err", err)
   }
```

当接收到挖矿任务后，先计算出这个区块所对应的一个哈希摘要❷，并登记此哈希对应的挖矿任务❸。登记的用途是方便查找该区块对应的挖矿任务信息，同时在开始新一轮挖矿时，会取消旧的挖矿工作，并从pendingTasks 中删除标记。以便快速作废挖矿任务。

随后，在共识规则下开始寻找Nonce，一旦找到Nonce，则发送给 resutlCh。同时，如果想取消挖矿任务，只需要关闭 stopCh。而在每次开始挖矿寻找Nonce前，便会关闭 stopCh 将当前进行中的挖矿任务终止❹。

```go
//miner/worker.go:500
interrupt := func() {
   if stopCh != nil {
      close(stopCh)
      stopCh = nil
   }
}
```

### 等待挖矿结果 Nonce

上一步已经开始挖矿，寻找Nonce。下一步便是等待挖矿结束，在 resultLoop 中，一直在等待执行结果❶。

```go
//miner/worker.go:542
select {
case block := <-w.resultCh: //❶
   if block == nil {
      continue
   }
   if w.chain.HasBlock(block.Hash(), block.NumberU64()) {//❷
      continue
   }
   var (
      sealhash = w.engine.SealHash(block.Header())
      hash     = block.Hash()
   )
```

 一旦找到Nonce，则说明挖出了新区块。

### 存储与广播挖出的新块

 挖矿结果已经是一个包含正确Nonce 的新区块。在正式存储新区块前，需要检查区块是否已经存在，存在则不继续处理❷。

```go
//miner/worker.go:556
w.pendingMu.RLock()
task, exist := w.pendingTasks[sealhash]
w.pendingMu.RUnlock()
if !exist {  //❸
   continue
}
var (
   receipts = make([]*types.Receipt, len(task.receipts))
   logs     []*types.Log
)
for i, receipt := range task.receipts { //❹
   receipt.BlockHash = hash
   receipt.BlockNumber = block.Number()
   receipt.TransactionIndex = uint(i)

   receipts[i] = new(types.Receipt)
   *receipts[i] = *receipt
   for _, log := range receipt.Logs {
      log.BlockHash = hash
   }
   logs = append(logs, receipt.Logs...)
}
```

也许挖矿任务已被取消，如果Pending Tasks 中不存在区块对应的挖矿任务信息，则说明任务已被取消，就不需要继续处理❸。从挖矿任务中，整理交易回执，补充缺失信息，并收集所有区块事件日志信息❹。

```go
//miner/worker.go:584
stat, err := w.chain.WriteBlockWithState(block, receipts, task.state)//
if err != nil {
   log.Error("Failed writing block to chain", "err", err)
   continue
}
//...
w.mux.Post(core.NewMinedBlockEvent{Block: block})//❻
```

随后，将区块所有信息写入本地数据库❺，对外发送挖出新块事件❻。在 eth 包中会监听并订阅此事件。

```go
//eth/handler.go:771
func (pm *ProtocolManager) minedBroadcastLoop() {
   for obj := range pm.minedBlockSub.Chan() {
      if ev, ok := obj.Data.(core.NewMinedBlockEvent); ok {
         pm.BroadcastBlock(ev.Block, true) //❼
         pm.BroadcastBlock(ev.Block, false) //❽
      }
   }
}
```

一旦接受到事件，则立即将广播。首随机广播给部分节点❼，再重新广播给不存在此区块的其他节点❽。

```go
//miner/worker.go:595
var events []interface{}
switch stat {
case core.CanonStatTy:
   events = append(events, core.ChainEvent{Block: block, Hash: block.Hash(), Logs: logs})
   events = append(events, core.ChainHeadEvent{Block: block})
case core.SideStatTy:
   events = append(events, core.ChainSideEvent{Block: block})
}
w.chain.PostChainEvents(events, logs)//❾
w.unconfirmed.Insert(block.NumberU64(), block.Hash())//⑩
```

同时，也需要通知程序内部的其他子系统，发送事件。新存储的区块，有可能导致切换链分支。如果变化，则队伍是发送 ChainSideEvent 事件。如果没有切换，则说明新区块仍然在当前的最长链上。对外发送 ChainEvent 和 ChainHeadEvent事件❾。新区块并非立即稳定，暂时存入到未确认区块集中。可这个 unconfirmed 仅仅是记录，但尚未具体使用。

## 总结

至此，已经讲解完以太坊挖出一个新区块所经历的各个环节。下面是一张流程图是对挖矿环节的细化，可以边看图便对比阅读此文。同时在讲解时，并没有涉及共识内部逻辑、以及提交交易到虚拟机执行内容。这些内容不是挖矿流程的重点，共识部分将在一下次讲解共识时细说。

![以太坊挖矿流程细节](https://img.learnblockchain.cn/book_geth/image-20190728005050579.png!de)

