---
title: "以太坊交易池架构设计"
menuTitle: "架构设计"
date: 2019-07-31T22:58:46+08:00
weight: 20201
---

当前以太坊公链的平均每秒能处理30到40笔交易，因此以太坊一旦出现火热的DAPP时，极易出现交易拥堵。

偏低的交易处理速度永远无法同现有的中心化服务相比。当网络中出现大量交易排队时，矿工是如何选择并管理这些交易的呢？答案在本篇所介绍的以太坊交易池中，如果你对交易还不特别熟悉，则请先阅读 [以太坊交易]({{< ref "part1/transaction.md" >}})。

## 交易处理流程

当你通过以太坊钱包，发送一笔转账交易给张三时。这笔交易是如何进入网络，最终被矿工打包到区块中呢？

下图是一笔交易从出生到交易进入区块的关键流程。

![transaction-life](https://img.learnblockchain.cn/book_geth/transaction-life.png)

首先，用户可通过以太坊钱包或者其他调用以太坊节点API (eth_sendRawTransaction等)发送交易到一个运行中的以太坊 geth 节点。

此时，因为交易是通过节点的API接收，因此此交易被视为一笔来自本地(local)（图中用红球表示），在经过一系列校验和处理后。交易成功进入交易池，随后向已连接的邻近节点发送此交易。

当邻近节点，如矿工节点从邻近节点接收到此交易时，在进入交易池之前。会将交易标记为来自远方（remote）的交易（图中用绿球表示）。也需要经过校验和处理后，进入矿工节点的交易池，等待矿工打包到区块中。

如果邻近节点，不是矿工，也无妨。因为任何节点会默认将接收到的合法交易及时发送给邻近节点。得益于P2P网络，一笔交易平均在6s内扩散到整个以太坊公链网络的各个节点中。

![A-Distributed-P2P-Network-with-Elements-of-Blockchain-and-Cryptocurrency](https://img.learnblockchain.cn/book_geth/A-Distributed-P2P-Network.jpg)

进入以太坊交易池的交易被区分本地还是远方的目的是因为，节点对待local的交易和remote的交易有所差异。简单地说是 local 交易优先级高于 remote 交易。

## 以太坊交易池设计

前面并未交易池处理细节，这里将详细讲解以太坊交易池处理一笔交易时的完整过程。在讲解前，你还应该先了解以太坊交易池的设计模型。 从2014年到现在，以太坊的交易池一直在不断优化中，从未停止。从这里也说明，交易池不仅仅重要，还需要高性能。

下图是以太坊交易池的主要设计模块，分别是交易池配置、实时的区块链状态、交易管理容器、本地交易存储和新交易信号。

![ethereum-tx-pool-desgin](https://img.learnblockchain.cn/book_geth/image-20190616220718529.png)

各个模块相互影响，其中最重要的的交易管理。这也是需要我们重点介绍的部分。

### 交易池配置

交易池配置不多，但每项配置均直接影响交易池对交易的处理行为。配置信息由 TxPoolConfig 所定义，各项信息如下：

```go
// core/tx_pool.go:125
type TxPoolConfig struct {
   Locals    []common.Address
   NoLocals  bool
   Journal   string
   Rejournal time.Duration
   PriceLimit uint64
   PriceBump  uint64
   AccountSlots uint64
   GlobalSlots  uint64
   AccountQueue uint64
   GlobalQueue  uint64
   Lifetime time.Duration
}
```

+ Locals: 定义了一组视为local交易的账户地址。任何来自此清单的交易均被视为 local 交易。
+ NoLocals: 是否禁止local交易处理。默认为 fasle,允许 local 交易。如果禁止，则来自 local 的交易均视为 remote 交易处理。
+ Journal： 存储local交易记录的文件名，默认是 `./transactions.rlp`。
+ Rejournal：定期将local交易存储文件中的时间间隔。默认为每小时一次。
+ PriceLimit： remote交易进入交易池的最低 Price 要求。此设置对 local 交易无效。默认值1。
+ PriceBump：替换交易时所要求的价格上调涨幅比例最低要求。任何低于要求的替换交易均被拒绝。
+ AccountSlots： 当交易池中可执行交易（是已在等待矿工打包的交易）量超标时，允许每个账户可以保留在交易池最低交易数。默认值是 16 笔。
+ GlobalSlots： 交易池中所允许的可执行交易量上限，高于上限时将释放部分交易。默认是 4096 笔交易。
+ AccountQueue：交易池中单个账户非可执行交易上限，默认是64笔。
+ GlobalQueue： 交易池中所有非可执行交易上限，默认1024 笔。
+ Lifetime： 允许 remote 的非可执行交易可在交易池存活的最长时间。交易池每分钟检查一次，一旦发现有超期的remote 账户，则移除该账户下的所有非可执行交易。默认为3小时。

上面配置中，包含两个重要概念**可执行交易**和**非可执行交易**。可执行交易是指从交易池中择优选出的一部分交易可以被执行，打包到区块中。非可执行交易则相反，任何刚进入交易池的交易均属于非可执行状态，在某一个时刻才会提升为可执行状态。

一个节点如何自定义上述交易配置呢？以太坊 geth 节点允许在启动节点时，通过参数修改配置。可修改的交易池配置参数如下（通过 `geth -h` 查看）:

```html
TRANSACTION POOL OPTIONS:
  --txpool.locals value        Comma separated accounts to treat as locals (no flush, priority inclusion)
  --txpool.nolocals            Disables price exemptions for locally submitted transactions
  --txpool.journal value       Disk journal for local transaction to survive node restarts (default: "transactions.rlp")
  --txpool.rejournal value     Time interval to regenerate the local transaction journal (default: 1h0m0s)
  --txpool.pricelimit value    Minimum gas price limit to enforce for acceptance into the pool (default: 1)
  --txpool.pricebump value     Price bump percentage to replace an already existing transaction (default: 10)
  --txpool.accountslots value  Minimum number of executable transaction slots guaranteed per account (default: 16)
  --txpool.globalslots value   Maximum number of executable transaction slots for all accounts (default: 4096)
  --txpool.accountqueue value  Maximum number of non-executable transaction slots permitted per account (default: 64)
  --txpool.globalqueue value   Maximum number of non-executable transaction slots for all accounts (default: 1024)
  --txpool.lifetime value      Maximum amount of time non-executable transaction are queued (default: 3h0m0s)
```

### 链状态

所有进入交易池的交易均需要被校验，最基本的是校验账户余额是否足够支付交易执行。或者交易 nonce 是否合法。在交易池中维护的最新的区块StateDB。当交易池接收到新区块信号时，将立即重置 statedb。

在交易池启动后，将订阅链的区块头事件：

```go
//core/tx_pool.go:274
pool.chainHeadSub = pool.chain.SubscribeChainHeadEvent(pool.chainHeadCh)
```

并开始监听新事件：

```go
//core/tx_pool.go:305
for {
   select {
   // Handle ChainHeadEvent
   case ev := <-pool.chainHeadCh:
      if ev.Block != nil {
         pool.mu.Lock()
         if pool.chainconfig.IsHomestead(ev.Block.Number()) {
            pool.homestead = true
         }
         pool.reset(head.Header(), ev.Block.Header())
         head = ev.Block

         pool.mu.Unlock()
      }
  //...
  }
}
```

接收到事件后，将执行 `func (pool *TxPool) reset(oldHead, newHead *types.Header)`方法更新 state和处理交易。核心是将交易池中已经不符合要求的交易删除并更新整理交易，这里不展开描述，有兴趣的话，可以到微信群中交流。

### 本地交易

在交易池中将交易标记为 local 的有多种用途：

1. 在本地磁盘存储已发送的交易。这样，本地交易不会丢失，重启节点时可以重新加载到交易池，实时广播出去。
2. 可以作为外部程序和以太坊沟通的一个渠道。外部程序只需要监听文件内容变化，则可以获得交易清单。
3. local交易可优先于 remote 交易。对交易量的限制等操作，不影响 local 下的账户和交易。

对应本地交易存储，在启动交易池时根据配置开启本地交易存储能力：

```go
//core/tx_pool.go:264
if !config.NoLocals && config.Journal != "" {
		pool.journal = newTxJournal(config.Journal)
		if err := pool.journal.load(pool.AddLocals); err != nil {
			log.Warn("Failed to load transaction journal", "err", err)
		}
    //...
}
```

并从磁盘中加载已有交易到交易池。在新的local 交易进入交易池时，将被实时写入 journal 文件。

```go
// core/tx_pool.go:757
func (pool *TxPool) journalTx(from common.Address, tx *types.Transaction) {
   if pool.journal == nil || !pool.locals.contains(from) {
      return
   }
   if err := pool.journal.insert(tx); err != nil {
      log.Warn("Failed to journal local transaction", "err", err)
   }
}
```

从上可看到，只有属于 local 账户的交易才会被记录。你又没有注意到，如果仅仅是这样的话，journal 文件是否会跟随本地交易而无限增长？答案是否定的，虽然无法实时从journal中移除交易。但是支持定期更新journal文件。

journal 并不是保存所有的本地交易以及历史，他仅仅是存储当前交易池中存在的本地交易。因此交易池会定期对 journal 文件执行 `rotate`，将交易池中的本地交易写入journal文件，并丢弃旧数据。

```go
journal := time.NewTicker(pool.config.Rejournal)
//...
//core/tx_pool.go:353
case <-journal.C:
			if pool.journal != nil {
				pool.mu.Lock()
				if err := pool.journal.rotate(pool.local()); err != nil {
					log.Warn("Failed to rotate local tx journal", "err", err)
				}
				pool.mu.Unlock()
			}
}
```

### 新交易信号

文章开头，有提到进入交易池的交易将被广播到网络中。这是依赖于交易池支持外部订阅新交易事件信号。任何订阅此事件的子模块，在交易池出现新的可执行交易时，均可实时接受到此事件通知，并获得新交易信息。

需要注意的是并非所有进入交易池的交易均被通知外部，而是只有交易从非可执行状态变成可执行状态后才会发送信号。

```go
//core/tx_pool.go:705
go pool.txFeed.Send(NewTxsEvent{types.Transactions{tx}})
//core/tx_pool.go:1022
go pool.txFeed.Send(NewTxsEvent{promoted})
```

在交易池中，有两处地方才会执行发送信号。一是交易时用于替换已经存在的可执行交易时。二是有新的一批交易从非可执行状态提升到可执行状态后。

外部只需要订阅`SubscribeNewTxsEvent(ch chan<- NewTxsEvent)`新可执行交易事件，则可实时接受交易。在 geth 中网络层将订阅交易事件，以便实时广播。

```go
//eth/handler.go:213
pm.txsCh = make(chan core.NewTxsEvent, txChanSize)
pm.txsSub = pm.txpool.SubscribeNewTxsEvent(pm.txsCh)
//eth/handler.go:781
func (pm *ProtocolManager) txBroadcastLoop() {
   for {
      select {
      case event := <-pm.txsCh:
         pm.BroadcastTxs(event.Txs)
      //...
   }
}
```

另外是矿工实时订阅交易，以便将交易打包到区块中。

```go
//miner/worker.go:207
worker.txsSub = eth.TxPool().SubscribeNewTxsEvent(worker.txsCh)
//miner/worker.go:462
txs := make(map[common.Address]types.Transactions)
for _, tx := range ev.Txs {
		acc, _ := types.Sender(w.current.signer, tx)
   	txs[acc] = append(txs[acc], tx)
}
txset := types.NewTransactionsByPriceAndNonce(w.current.signer, txs)
w.commitTransactions(txset, coinbase, nil)
```

### 交易管理

最核心的部分则是交易池对交易的管理机制。以太坊将交易按状态分为两部分：可执行交易和非可执行交易。分别记录在pending容器中和 queue 容器中。

![ethereum-tx-pool-txManager](https://img.learnblockchain.cn/book_geth/image-20190617002144274.png)

如上图所示，交易池先采用一个 txLookup (内部为map）跟踪所有交易。同时将交易根据本地优先，价格优先原则将交易划分为两部分 queue 和 pending。而这两部交易则按账户分别跟踪。

那么在交易在进入交易池进行管理的细节有是如何的呢？等我下一篇文章详细介绍以太坊交易池交易管理。

