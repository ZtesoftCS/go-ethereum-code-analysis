---
title: "交易入队列"
date: 2019-07-31T22:58:46+08:00
weight: 20203
---

这是关于以太坊交易池的第三篇文章，第一篇是[整体概况以太坊交易池]({{< ref "/part2/miner">}})，第二篇是讲解[以太坊本地交易存储]({{< ref "txJournal.md" >}})。而第三篇文章详解一笔交易时如何进入交易池，以及影响。内容较多，请坐好板凳。

交易进入交易池分三步走：校验、入队列、容量检查。拿 AddLocalTx举例。核心代码集中在交易池的`func (pool *TxPool) add(tx *types.Transaction, local bool) (bool, error)`方法。

## 校验交易合法性

任何交易进入交易池之前均需要校验交易数据的合法性。如果交易校验失败则拒绝此交易。

```go
//core/tx_pool.go:662
if err := pool.validateTx(tx, local); err != nil {
   log.Trace("Discarding invalid transaction", "hash", hash, "err", err)
   invalidTxCounter.Inc(1)
   return false, err
}
```

那么是如何进行校验的呢？代码逻辑集中在`func (pool *TxPool) validateTx(tx *types.Transaction, local bool) error`方法中。

首先是防止DOS攻击，不允许交易数据超过32KB。

```go
if tx.Size() > 32*1024 {
   return ErrOversizedData
}
```

接着不允许交易的转账金额为负数，实际上这次判断难以命中，原因是从外部接收的交易数据属RLP编码，是无法处理负数的。当然这里做一次校验，更加保险。

```go
if tx.Value().Sign() < 0 {
   return ErrNegativeValue
}
```

交易在虚拟机中执行时将消耗GAS，为了防止程序错误，允许用户在交易中携带一个GAS上限，防止意外发生。同样，为了避免区块总消耗异常，和控制区块数据大小。也同样存在区块GAS上限。而区块中的GAS量是每笔交易执行消耗GAS之和，故不可能一笔交易的GAS上限超过区块GAS限制。一旦超过，这笔交易不可能会打包到区块中，则可在交易池中直接拒绝超过限制的交易。

```go
if pool.currentMaxGas < tx.Gas() {
   return ErrGasLimit
}
```



每笔交易都需要携带[交易签名]({{< ref "part3/sign-and-valid.md" >}})信息，并从签名中解析出签名者地址。只有合法的签名才能成功解析出签名者。一旦解析失败拒绝此交易。

```
from, err := types.Sender(pool.signer, tx)
if err != nil {
   return ErrInvalidSender
}
```

既然知道是交易发送者(签名者)，那么该发送者也可能是来自于交易池所标记的local账户。因此当交易不是local交易时，还进一步检查是否属于local账户。

```go
local = local || pool.locals.contains(from)
```



如果不是local交易，那么交易的GasPrice 也必须不小于交易池设定的最低GasPrice。这样的限制检查，允许矿工自行决定GasPrice。有些矿工，可能只愿意处理愿意支付高手续费的交易。当然local交易则忽略，避免将本地产生的交易拦截。

```go
if !local && pool.gasPrice.Cmp(tx.GasPrice()) > 0 {
   return ErrUnderpriced
}
```

以太坊中每个[账户]({{< ref "part1/account.md" >}})都有一个数字类型的 Nonce 字段。是一个有序数字，一次比一次大。虚拟机每执行一次该账户的交易，则新 Nonce 将在此交易的Nonce上加1。如果使用恰当，该 Nonce 可间接表示已打包了 Nonce 笔该账户交易。既然不会变小，那么在交易池中不允许出现交易的Nonce 小于此账户当前Nonce的交易。

```go
if pool.currentState.GetNonce(from) > tx.Nonce() {
   return ErrNonceTooLow
}
```



如果交易被打包到区块中，应该花费多少手续费呢？虽然无法知道最终花费多少，但至少花费多少手续费是可预知的。手续费加上本次交易转移的以太币数量，将会从该账户上扣除。那么账户至少需要转移多少以太坊是明确的。

因此在交易池中，将检查该账户余额，只有账户资产充足时，才允许交易继续，否则在虚拟机中执行交易，交易也必将失败。

```go
if pool.currentState.GetBalance(from).Cmp(tx.Cost()) < 0 {
   return ErrInsufficientFunds
}
```

我们不但知道最低花费，也可以知道将最低花费多少GAS。因此也检查交易所设置的Gas上限是否正确。一旦交易至少需要2万Gas，而交易中设置的Gas上限确是 1万GAS。那么交易必然失败，且剩余了 1万GAS。

```go
intrGas, err := IntrinsicGas(tx.Data(), tx.To() == nil, pool.homestead)
if err != nil {
   return err
}
if tx.Gas() < intrGas {
   return ErrIntrinsicGas
}
```

因此，在最后。如果交易GAS上限低于已知的最低GAS开销，则拒绝这笔必将失败的交易。



## 交易入队列

在交易池中并不是一个队列管理数据，而是由多个数据集一起管理交易。

![ethereum-tx-pool-txManager](https://img.learnblockchain.cn/book_geth/image-20190617002144274.png)

如上图所示，交易池先采用一个 txLookup (内部为map）跟踪所有交易。同时将交易根据本地优先，价格优先原则将交易划分为两部分 queue 和 pending。而这两部交易则按账户分别跟踪。

 在进入交易队列前，将判断所有交易队列 all 是否已经达到上限。如果到达上限，则需要从交易池或者当前交易中移除优先级最低交易 。

```go
//core/tx_pool.go:668
if uint64(pool.all.Count()) >= pool.config.GlobalSlots+pool.config.GlobalQueue { //❶
   if !local && pool.priced.Underpriced(tx, pool.locals) {//❷
      log.Trace("Discarding underpriced transaction", "hash", hash, "price", tx.GasPrice())
      underpricedTxCounter.Inc(1)
      return false, ErrUnderpriced
   }
   drop := pool.priced.Discard(pool.all.Count()-int(pool.config.GlobalSlots+pool.config.GlobalQueue-1), pool.locals) //❸
   for _, tx := range drop {
      log.Trace("Discarding freshly underpriced transaction", "hash", tx.Hash(), "price", tx.GasPrice())
      underpricedTxCounter.Inc(1)
      pool.removeTx(tx.Hash(), false)
   }
}
```

那么哪些交易的优先级最低呢？首先，本地交易是受保护的，因此如果交易来自remote 时，将检查该交易的价格是否是整个交易池中属于最低价格的。如果是，则拒绝该交易❷。否则在加入此交易前，将从交易队列 all 中删除价格最低的一部分交易❸。为了高效获得不同价格的交易，交易池已经将交易按价格从低到高实施排列存储在 ` pool.priced`中。

解决交易容量问题后，这笔交易过关斩将，立马将驶入交易内存池中。上图中，交易是有根据 from 分组管理，且一个 from 又分非可执行交易队列（queue）和可执行交易队列（pending）。新交易默认是要在非可执行队列中等待指示，但是一种情况时，如果该 from 的可执行队列中存在一个相同 nonce 的交易时，需要进一步识别是否能替换❹。

怎样的交易才能替换掉已在等待执行的交易呢？以太坊早起的默认设计是，只要价格(gasPrice)高于原交易，则允许替换。但是17年7月底在 [#15401](https://github.com/ethereum/go-ethereum/pull/15401)被改进。人们愿意支付更多手续费的原因有两种情况，一是急于处理交易，但如果真是紧急交易，那么在发送交易之处，会使用高于推荐的gasprice来处理交易。另一种情况时，以太坊价格下跌，人们愿意支付更多手续费。上调多少手续费是合理的呢？以太币下跌10%，那么便可以上调10%的手续费，毕竟对于用户来说，手续费的面值是一样的。交易池的默认配置（pool.config.PriceBump）是10%，只有上调10%手续费的交易才允许替换掉已在等待执行的交易❺。一旦可以替换，则替换掉旧交易❺，移除旧交易❻，并将交易同步存储到 all 交易内存池中。

```go
//core/tx_pool.go:685
if list := pool.pending[from]; list != nil && list.Overlaps(tx) {//❹
   inserted, old := list.Add(tx, pool.config.PriceBump)//❺
   if !inserted {
      pendingDiscardCounter.Inc(1)
      return false, ErrReplaceUnderpriced
   }
   if old != nil { //❻
      pool.all.Remove(old.Hash())
      pool.priced.Removed()
      pendingReplaceCounter.Inc(1)
   }
   pool.all.Add(tx)
   pool.priced.Put(tx)
   pool.journalTx(from, tx)
   //...
   return old != nil, nil
}
replace, err := pool.enqueueTx(hash, tx)//❼
if err != nil {
	return false, err
}
```

检查完是否需要替换 pending 交易后，则将交易存入非可执行队列❼。同样，在进入非可执行队列之前，也要检查是否需要替换掉相同 nonce 的交易❽。

```go
func (pool *TxPool) enqueueTx(hash common.Hash, tx *types.Transaction) (bool, error) {
   //...
   inserted, old := pool.queue[from].Add(tx, pool.config.PriceBump) //❽
   if !inserted {
      queuedDiscardCounter.Inc(1)
      return false, ErrReplaceUnderpriced
   }
   if old != nil {
      pool.all.Remove(old.Hash())
      pool.priced.Removed()
      queuedReplaceCounter.Inc(1)
   }
   if pool.all.Get(hash) == nil {
      pool.all.Add(tx)
      pool.priced.Put(tx)
   }
   return old != nil, nil
}
```

最后，如果交易属于本地交易还需要额外关照。如果交易属于本地交易，但是本地账户集中不存在此 from 时，更新本地账户集❾，避免交易无法被存储⑩。另外，如果已开启存储本地交易，则实时存储本地交易⑪。

```
// core/tx_pool.go:715
if local {
   if !pool.locals.contains(from) {
      log.Info("Setting new local account", "address", from)
      pool.locals.add(from)//❾
   }
}
pool.journalTx(from, tx)
//....
//core/tx_pool.go:757
func (pool *TxPool) journalTx(from common.Address, tx *types.Transaction) {
	// Only journal if it's enabled and the transaction is local
	if pool.journal == nil || !pool.locals.contains(from) {//⑩
		return
	}
	if err := pool.journal.insert(tx); err != nil {//⑪
		log.Warn("Failed to journal local transaction", "err", err)
	}
}
```

至此，一笔交易经过千山万水，进入了交易内存池，等待执行。

另外，不难看出，priced 队列是在交易进入队列内存池时便被编排到priced 队列，已让 priced 队列是对 all 交易内存池的同步排序。且交易是在进入pending 队列或者 queue 队列后，才同步更新到 all 交易内存池中。

这里不打算讲解 pending 和 queue 队列的内部实现，请自行研究。因为忽略技术细节不会影响你对以太坊各个技术点，模块的理解。下一讲讲解交易池内存容量处理。







