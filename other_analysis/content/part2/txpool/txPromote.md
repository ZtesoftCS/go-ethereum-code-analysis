---
title: "交易队列与容量内存限制"
menuTitle: "内存限制"
date: 2019-07-31T22:58:46+08:00 
weight: 20204
---

在交易存入交易池后，将影响pending格局。原因是在交易排队等待处理时，需要确定交易优先级。 如果交易池已有一万笔交易排队，该如何按优先级排队来处理呢？如果第一万零一笔交易刚刚加入交易池，需要优先处理此交易吗？如果待执行交易已经有十笔交易被执行完毕，如何从队列中转移一部分交易来添补空缺呢？如果交易将超过交易池配置上限呢？

不管如果变化，以太坊以不变应万变。用统一的优先级规则来应当各种情况，只要有交易加入或者清理出交易池都将立即激活对可执行交易队列的更新（promoteExecutables）。

规则是：删除无效和超上限交易、转移一部分、容量控制。虽然概括为一句话，但逻辑的整个处理确是整个交易池中最复杂的部分，也是最核心部分。



## 删除旧交易

当新区块来到时，很有可能包含交易内存池中一些账户的交易。一旦存在，则意味着账户的 nonce 和账户余额被存在变动。而只有高于当前新 nonce 交易才能被执行，且账户余额不足以支撑交易执行时，交易也将执行失败。

因此，在新区块来到后，删除所有低于新nonce的交易❶。 再根据账户可用余额，来移除交易开销（amount+gasLimit*gasPrice）高于此余额的交易❷。

```go
//core/tx_pool.go:982
for _, tx := range list.Forward(pool.currentState.GetNonce(addr)) {//❶
   hash := tx.Hash()
   log.Trace("Removed old queued transaction", "hash", hash)
   pool.all.Remove(hash)
   pool.priced.Removed()
}
drops, _ := list.Filter(pool.currentState.GetBalance(addr), pool.currentMaxGas)//❷
for _, tx := range drops {
	hash := tx.Hash()
	log.Trace("Removed unpayable queued transaction", "hash", hash)
	pool.all.Remove(hash)
	pool.priced.Removed()
	queuedNofundsCounter.Inc(1)
}
```

## 转移交易或释放

在非可执行队列中的交易有哪些可以转移到可执行队列呢？因为交易 nonce 的缘故，如果queue队列中存在低于 pending 队列的最小nonce的交易❸，则可直接转移到pending中❹。

```
for _, tx := range list.Ready(pool.pendingState.GetNonce(addr)) {//
   hash := tx.Hash()
   if pool.promoteTx(addr, hash, tx) {//❹
      log.Trace("Promoting queued transaction", "hash", hash)
      promoted = append(promoted, tx)
   }
}
```

转移后，该账户的交易可能超过所允许的排队交易笔数，如果超过则直接移除超过上限部分的交易❺。当然这仅仅针对remote交易。

```
if !pool.locals.contains(addr) {
   for _, tx := range list.Cap(int(pool.config.AccountQueue)) {//❺
      hash := tx.Hash()
      pool.all.Remove(hash)
      pool.priced.Removed() 
      //...
   }
}
```

至此，每个账户的非可执行交易更新完毕。随后，需要检查可执行交易队列情况。



## 检查pending 交易数量

[交易池配置]({{< ref "./txPool.md" >}}#交易池配置)有设置总pending量上限(pool.config.GlobalSlots)。如果超过上限❶，则分两种策略移除超限部分。

```go
pending := uint64(0)
for _, list := range pool.pending {
   pending += uint64(list.Len())
}
if pending > pool.config.GlobalSlots {//❶
	//...
}
```

优先从超上限(pool.config.AccountSlots)的账户❷中移除交易。在移除交易时，并非将某个账户的交易全部删除，而是每个账户轮流❸删除一笔交易❹，直到低于交易上限❺。同时，还存在一个特殊删除策略，并非直接轮流每个账户，而是通过一个动态阀值控制❻，阀值控制遍历顺序，存在一定的随机性。

```go
//core/tx_pool.go:1032
spammers := prque.New(nil)
for addr, list := range pool.pending { 
   if !pool.locals.contains(addr) && uint64(list.Len()) > pool.config.AccountSlots {
      spammers.Push(addr, int64(list.Len()))//❷
   }
} 
offenders := []common.Address{}
for pending > pool.config.GlobalSlots && !spammers.Empty() {
   offender, _ := spammers.Pop()
   offenders = append(offenders, offender.(common.Address))

   if len(offenders) > 1 { 
      threshold := pool.pending[offender.(common.Address)].Len()//❻
 
      for pending > pool.config.GlobalSlots && pool.pending[offenders[len(offenders)-2]].Len() > threshold { //❺
         for i := 0; i < len(offenders)-1; i++ {//❸
            list := pool.pending[offenders[i]]
            for _, tx := range list.Cap(list.Len() - 1) {//❹ 
              //delete tx
            }
            pending--
         }
      }
   }
}
```

如果仍然还超限，则继续采用直接遍历方式❼，删除交易，直到低于限制❽。

```go
//core/tx_pool.go:1073
if pending > pool.config.GlobalSlots && len(offenders) > 0 {
   for pending > pool.config.GlobalSlots && uint64(pool.pending[offenders[len(offenders)-1]].Len()) > pool.config.AccountSlots {//❽
      for _, addr := range offenders {//❼
         list := pool.pending[addr]
         for _, tx := range list.Cap(list.Len() - 1) { 
						//delete tx
         }
         pending--
      }
   }
}
```



## 检查 queue 交易数量

同样，交易池对于非可执行交易数量也存在上限控制。如果超过上限❶，同样需要删除超限部分。

```
//core/tx_pool.go:1096
queued := uint64(0)
for _, list := range pool.queue {
   queued += uint64(list.Len())
}
if queued > pool.config.GlobalQueue {//❶
	//...
}
```

删除交易的策略完成根据每个账户pending交易的时间处理，依次删除长时间存在于pending的账户交易。在交易进入pending 时会更新账户级的心跳时间，代表账户最后pending交易活动时间。时间越晚，说明交易越新。

当交易池的交易过多时，以太坊首先根据账户活动时间，从早到晚排列❷。 再按时间从晚到早❸依次交易。删除时，如果queue交易笔数不够待删除量时❹，直接清理该账户所有queue交易。否则逐个删除，直到到达删除任务❺。

```
addresses := make(addressesByHeartbeat, 0, len(pool.queue))
for addr := range pool.queue {
   if !pool.locals.contains(addr) { // don't drop locals
      addresses = append(addresses, addressByHeartbeat{addr, pool.beats[addr]})
   }
}
sort.Sort(addresses)//❷

for drop := queued - pool.config.GlobalQueue; drop > 0 && len(addresses) > 0; {
   addr := addresses[len(addresses)-1]//❸
   list := pool.queue[addr.address]

   addresses = addresses[:len(addresses)-1] 
   if size := uint64(list.Len()); size <= drop {//❹
      for _, tx := range list.Flatten() {
         pool.removeTx(tx.Hash(), true)
      }
      drop -= size
      queuedRateLimitCounter.Inc(int64(size))
      continue
   } 
   txs := list.Flatten()
   for i := len(txs) - 1; i >= 0 && drop > 0; i-- {//❺
      pool.removeTx(txs[i].Hash(), true)
      drop--
      queuedRateLimitCounter.Inc(1)
   }
}
```

也许，你所有疑惑。为何是删除最新活动账户的Queue交易呢？这是因为账户是最新活动，意味着该账户有刚交易进入 pending ，此账户的交易是更有机会被执行的。那么公平起见，哪些迟迟未能进入 pending 的账户的 queue 交易应该继续保留，以便账户交易有机会进入 pending 。这样对于每个账户来说，长时间等待过程中都是有机会进入 pending 被矿工处理的。