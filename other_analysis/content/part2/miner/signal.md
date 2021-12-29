---
title: "以太坊挖矿信号监控"
menuTitle: "挖矿信号"
date: 2019-07-31T22:58:46+08:00
draft: false
weight: 20302
---

挖矿的核心集中在 worker 中。worker 采用Go语言内置的 chain 跨进程通信方式。在不同工作中，根据信号处理不同工作。

下图是实例化 worker 时，启动的四个循环，分别监听不同信号来处理不同任务。

![以太坊Miner下监听信号](https://img.learnblockchain.cn/book_geth/image-20190721235307204.png!de)

## 挖矿工作信号

首先是在 newWorkLoop 中监控新挖矿任务。分别监控了三种信号，不管接收到三种中的哪种信号都会触发新一轮挖矿。

但根据信号类型，会告知内部需要重新开启挖矿的原因。如果已经在挖矿中，那么在开启新一轮挖矿前，会将旧工作终止。

如上图，当前的信号类型有：

1. start 信号：

   start信号属于开启挖矿的信号。这个我在上一篇[启动挖矿]({{< ref "start.md" >}})中，已经有简单介绍。每次在 miner.Start() 时将会触发新挖矿任务。

   ```go
   clearPending(w.chain.CurrentBlock().NumberU64())
   timestamp = time.Now().Unix()
   commit(false, commitInterruptNewHead)
   ```

2. chainHead信号：

   节点接收到了新的区块。比如，你原本是是在下一个新区块上挖矿，区块高度是 1000。此时你从网络上收到了一个合法的区块，高度也一样。这样，你就不需要再花力气和别人竞争了，赶快投入到下一个区块的挖矿竞争，才是有意义的。

   ```go
   clearPending(head.Block.NumberU64())
   timestamp = time.Now().Unix()
   commit(false, commitInterruptNewHead)
   ```

3. timer 信号：

   一个时间timer，默认每三秒检查执行一次检查。如果当下正在挖矿中，那么需要检查是否有新交易。如果有新交易，则需要放弃当前交易处理，重新开始一轮挖矿。这样可以使得愿意支付更多手续费的交易能被优先处理。

   ```go
   if w.isRunning() && (w.config.Clique == nil || w.config.Clique.Period > 0) {
      if atomic.LoadInt32(&w.newTxs) == 0 {
         timer.Reset(recommit)
         continue
      }
      commit(true, commitInterruptResubmit)
   }
   ```

这三类信号最终都聚集在新一轮挖矿上。那么是如何处理的呢？上图中，挖矿工作在 mainLoop 监控中一直等待 newWork信号。此处的三个工作信息，都通过 commit 方法，发送 newWork 信号。

```go
commit := func(noempty bool, s int32) {
   if interrupt != nil {
      atomic.StoreInt32(interrupt, s)
   }
   interrupt = new(int32)
   w.newWorkCh <- &newWorkReq{interrupt: interrupt, noempty: noempty, timestamp: timestamp}
   timer.Reset(recommit)
   atomic.StoreInt32(&w.newTxs, 0)
}
```

newWork 信号数据中有三个字段：

1. interrupt：这是一个数字指针，也就不管新work信号还是旧work信号，都能一直跟踪相同的一个全局唯一的任务终止信号值`interrupt`。 如果是需要终止旧任务，只需要更新信号值`atomic.StoreInt32(interrupt, s)`后，work 内部便会感知到，从而终止挖矿工作。
2. noempty：是否不能为空块。默认情况下是允许挖空块的，但是明知有交易需要处理，则不允许挖空块（见 timer信号）。
3. timestamp：记录的是当前操作系统时间，最终会被用作区块的区块时间戳。


## 动态估算交易处理时长

再回到 timer 信号上。geth 程序启动时，timmer 计时器默认是三秒。但这个时间间隔不是一成不变的，会根据挖矿时长来动态调整。

为什么是默认值是三秒呢？也就是说，系统默认有三秒时间来处理交易，一笔转账交易执行时间是毫秒级的。如果三秒后，仍有新交易未处理完毕，则需要重来，将根据新的交易排序，将愿意支付更多手续费的交易优先处理。

在挖矿timer计时器中，不能固定为三秒钟，这样时间可能太短。采用动态估算的方式也许更加有效。 动态估算的计算公式分两部分：先是计算出一个比例ratio=燃料剩余率，再加工计算出一个新的计时器时间。

```go
新时间间隔 = 当前时间间隔 * (1-基准增长率) + 基准增长率 * ( 当前时间间隔/燃料剩余率 )
	        = 当前时间间隔 * (1-0.1) + 0.1 * ( 当前时间间隔/燃料剩余率 )
```

这里的基准增长率是一个常量 0.1 ，通过公式可以看出，是否能有10%的时间延长，取决于燃料剩余率。剩余燃料越多，增长越小，最低是接近90%的负值长。剩余燃料越少，增长越快，最大有近60%的增长。当然也不能一直增长下去，这里有一个15秒的上限值。

**动态估算**是发生在本次处理到期后，根据一定策略估算出一个新计时器。当正在处理一笔交易时，将检查终止信息值`interrupt`，如果刚好遇上时间到期，则需要调整计时器❶。以太坊是根据燃料实际执行情况来参与动态估算。首先计算直接等于剩余燃料在区块总燃料中的占比❷。这种计算方式完全是根据单个gas的基础用时，来推导剩余gas可以处理多长时间的交易。

```go
//miner/worker.go:729
if interrupt != nil && atomic.LoadInt32(interrupt) != commitInterruptNone {
   if atomic.LoadInt32(interrupt) == commitInterruptResubmit { //❶
      ratio := float64(w.current.header.GasLimit-w.current.gasPool.Gas())/ float64(w.current.header.GasLimit)  //❷
      if ratio < 0.1 {
         ratio = 0.1
      }
      w.resubmitAdjustCh <- &intervalAdjust{//❸
         ratio: ratio,
         inc:   true,
      }
   }
   return atomic.LoadInt32(interrupt) == commitInterruptNewHead
}
```

在计算出时间增长率后，发送一个自动更新计时器时间的信号 resubmitAdjust。要求按剩余率调整计时器❸。在接收到信号后❹，根据剩余率重新计算计时器时间❺。

```go
//miner/worker.go:379
case adjust := <-w.resubmitAdjustCh: //❹
   if adjust.inc {
      recalcRecommit(float64(recommit.Nanoseconds())/adjust.ratio, true)//❺
   } else {
      recalcRecommit(float64(minRecommit.Nanoseconds()), false)
   }
```

重新计算计时器时间间隔后，将会下一个计时器上生效。

同时，还支持矿工通过调用RPC API `{"method": "miner_setRecommitInterval", "params": [interval]} `来直接修改计时器间隔。调用API后，将会在 worker 中产生信号。

```go
//miner/worker.go:244
func (w *worker) setRecommitInterval(interval time.Duration) {
   w.resubmitIntervalCh <- interval
}
```

而在 newWorkLoop 监控中，将监控该信号。发现信号后，立即重置计时器的时间间隔。

```go
//miner/worker.go:366
case interval := <-w.resubmitIntervalCh:
   if interval < minRecommitInterval {
      interval = minRecommitInterval
   }
   minRecommit, recommit = interval, interval
```