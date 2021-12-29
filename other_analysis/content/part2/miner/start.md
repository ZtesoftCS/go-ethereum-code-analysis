---
title: "启动挖矿"
menuTitle: "启动挖矿"
date: 2019-07-31T22:58:46+08:00
draft: false
weight: 20301
---

挖矿模块只通过 Miner 实例对外提供数据访问。可以通过多种途径开启挖矿服务。程序运行时已经将 Miner 实例化，并进入等待挖矿状态，随时可以启动挖矿。

## 挖矿参数

矿工可以根据矿机的服务器性能，来定制化挖矿参数。下面是一份 geth 关于挖矿的运行时参数清单，全部定义在 `cmd/utils/flags.go` 文件中。

| 参数              | 默认值         | 用途  |
| ----------------- | -------------- | -------------------- |
| --mine            | false          | 是否自动开启挖矿        |
| --miner.threads   | 0              | 挖矿时可用并行PoW计算的协程（轻量级线程）数。<br>兼容过时参数 —minerthreads。 |
| --miner.notify    | 空             | 挖出新块时用于通知远程服务的任意数量的远程服务地址。<br>是用 `,`分割的多个远程服务器地址。<br>如：”http://api.miner.com,http://api2.miner.com“ |
| --miner.noverify  | false          | 是否禁用区块的PoW工作量校验。   |
| --miner.gasprice  | 1000000000 wei | 矿工可接受的交易Gas价格，<br>低于此GasPrice的交易将被拒绝写入交易池和不会被矿工打包到区块。 |
| --miner.gastarget | 8000000 gas    | 动态计算新区块燃料上限（gaslimit）的下限值。<br>兼容过时参数 —targetgaslimit。 |
| --miner.gaslimit  | 8000000 gas    | 动态技术新区块燃料上限的上限值。    |
| --miner.etherbase | 第一个账户     | 用于接收挖矿奖励的账户地址，<br>默认是本地钱包中的第一个账户地址。 |
| --miner.extradata | geth版本号     | 允许矿工自定义写入区块头的额外数据。  |
| --miner.recommit  | 3s             | 重新开始挖掘新区块的时间间隔。<br>将自动放弃进行中的挖矿后，重新开始一次新区块挖矿。 |
| --minerthreads    |                | *已过时*   |
| —targetgaslimit   |                | *已过时*    |
| --gasprice        |                | *已过时*    |

你可以通过执行程序 dgeth[^1] 来查看参数。

```
dgeth -h |grep "mine"
```

## 实例化Miner

geth 程序运行时已经将 Miner 实例化，只需等待命令开启挖矿。

```go
//eth/backend.go:197
eth.miner = miner.New(eth, chainConfig, eth.EventMux(),
                      eth.engine, config.MinerRecommit,
                      config.MinerGasFloor, config.MinerGasCeil, eth.isLocalBlock)
eth.miner.SetExtra(makeExtraData(config.MinerExtraData))
```

从上可看出，在实例化 miner 时所用到的配置项只有4项。实例化后，便可通过 API 操作 Miner。

![image-20190722225217754](https://img.learnblockchain.cn/book_geth/image-20190722225217754.png!de)

[Miner API](https://github.com/ethereum/go-ethereum/wiki/Management-APIs#miner) 分 public 和 private。挖矿属于隐私，不得让其他人任意修改。因此挖矿API全部定义在 Private 中，公共部分只有 `Mining()`。

## 启动挖矿

geth 运行时默认不开启挖矿。如果用户需要启动挖矿，则可以通过以下几种方式启动挖矿。

### 参数方式自动开启挖矿

使用参数 `—mine `，可以在启动程序时默认开启挖矿。下面我们用 dgeth[^1] 在开发者模式启动挖矿为例：

```sh
dgeth --dev --mine
```

启动后，可以看到默认情况下已开启挖矿。开发者模式下已经挖出了一个高度为1的空块。

![image-20190722215758989(https://img.learnblockchain.cn/book_geth/image-20190722215758989.png!de)

当参数加入了`--mine`参数表示启用挖矿，此时将根据输入个各项挖矿相关的参数启动挖矿服务。

```go
// cmd/geth/main.go:369
if ctx.GlobalBool(utils.MiningEnabledFlag.Name) || ctx.GlobalBool(utils.DeveloperFlag.Name) { //❶
   // Mining only makes sense if a full Ethereum node is running
   if ctx.GlobalString(utils.SyncModeFlag.Name) == "light" {
      utils.Fatalf("Light clients do not support mining")
   }
   var ethereum *eth.Ethereum
   if err := stack.Service(&ethereum); err != nil {
      utils.Fatalf("Ethereum service not running: %v", err)
   }
   // Set the gas price to the limits from the CLI and start mining
   gasprice := utils.GlobalBig(ctx, utils.MinerLegacyGasPriceFlag.Name)//❷
   if ctx.IsSet(utils.MinerGasPriceFlag.Name) {
      gasprice = utils.GlobalBig(ctx, utils.MinerGasPriceFlag.Name)
   }
   ethereum.TxPool().SetGasPrice(gasprice)

   threads := ctx.GlobalInt(utils.MinerLegacyThreadsFlag.Name)//❸
   if ctx.GlobalIsSet(utils.MinerThreadsFlag.Name) {
      threads = ctx.GlobalInt(utils.MinerThreadsFlag.Name)
   }
   if err := ethereum.StartMining(threads); err != nil {//❹
      utils.Fatalf("Failed to start mining: %v", err)
   }
}
```

启动 geth 过程是，如果启用挖矿`--mine`或者属于开发者模式`—dev`，则将启动挖矿❶。

在启动挖矿之前，还需要获取 `—miner.gasprice` 实时应用到交易池中❷。同时也需要指定将允许使用多少协程来并行参与PoW计算❸。然后开启挖矿，如果开启挖矿失败则终止程序运行并打印错误信息❹。

### 控制台命令启动挖矿

在实例化Miner后，已经将 miner 的操作API化。因此我们可以在 geth 的控制台中输入Start命令启动挖矿。

调用API `miner_start` 将使用给定的挖矿计算线程数来开启挖矿。下面表格是调用 API 的几种方式。

| 客户端  | 调用方式                                            |
| ------- | --------------------------------------------------- |
| Go      | `miner.Start(threads *rpc.HexNumber) (bool, error)` |
| Console | `miner.start(number)`                               |
| RPC     | `{"method": "miner_start", "params": [number]}`     |

首先，我们进入 geth 的 JavaScript 控制台，后输入命令`miner.start(1)`来启动挖矿。

```sh
dgeth --maxpeers=0 console
```

![启动命令](https://img.learnblockchain.cn/book_geth/image-20190722231355886.png!de)

启动挖矿后，将开始出新区块。

###  RPC API 启动挖矿

因为 API 已支持开启挖矿，如上文所述，可以直接调用 RPC  `{"method": "miner_start", "params": [number]}` 来启动挖矿。实际上在控制台所执行的 `miner.start(1)`，则相对于 `{"method": "miner_start", "params": [1]}`。

如，启动 geth 时开启RPC。

```sh
dgeth --maxpeer 0 --rpc --rpcapi --rpcport 8080 "miner,admin,eth" console
```

开启后，则可以直接调用API，开启挖矿服务。

```sh
curl -d '{"id":1,"method": "miner_start", "params": [1]}' http://127.0.0.1:8080
```

## 挖矿启动细节

不管何种方式启动挖矿，最终通过调用 miner 对象的 Start 方法来启动挖矿。不过在开启挖矿前，geth 还处理了额外内容。

当你通过控制台或者 RPC API 调用启动挖矿命令后，在程序都将引导到方法`func (s *Ethereum) StartMining(threads int) error `。

```go
// eth/backend.go:414
type threaded interface {
   SetThreads(threads int)
}
if th, ok := s.engine.(threaded); ok {//❶
   log.Info("Updated mining threads", "threads", threads)
   if threads == 0 {
      threads = -1 // Disable the miner from within
   }
   th.SetThreads(threads)//❷
}
if !s.IsMining() { //❸
    //...
		price := s.gasPrice
		s.txPool.SetGasPrice(price) //❹

		eb, err := s.Etherbase() //❺
		if err != nil {
			log.Error("Cannot start mining without etherbase", "err", err)
			return fmt.Errorf("etherbase missing: %v", err)
		}
		if clique, ok := s.engine.(*clique.Clique); ok {
			wallet, err := s.accountManager.Find(accounts.Account{Address: eb})//❻
			if wallet == nil || err != nil {
				log.Error("Etherbase account unavailable locally", "err", err)
				return fmt.Errorf("signer missing: %v", err)
			}
			clique.Authorize(eb, wallet.SignData)//❼
		}
		atomic.StoreUint32(&s.protocolManager.acceptTxs, 1)//❽

		go s.miner.Start(eb)//❾
	}
	return nil
```

在此方法中，首先看挖矿的共识引擎是否支持设置协程数❶，如果支持，将更新此共识引擎参数 ❷。接着，如果已经是在挖矿中，则忽略启动，否则将开启挖矿 ❸。在启动前，需要确定两项配置：交易GasPrice下限❹，和挖矿奖励接收账户（矿工账户地址）❺。

这里对于 clique.Clique 共识引擎（PoA 权限共识），进行了特殊处理，需要从钱包中查找对于挖矿账户❻。在进行挖矿时不再是进行PoW计算，而是使用认可的账户进行区块签名❼即可。

可能由于一些原因，不允许接收网络交易。因此，在挖矿前将允许接收网络交易❽。随即，开始在挖矿账户下开启挖矿❾。此时，已经进入了miner实例的 Start 方法。

```go
// miner/miner.go:108
func (self *Miner) Start(coinbase common.Address) {
   atomic.StoreInt32(&self.shouldStart, 1)
   self.SetEtherbase(coinbase) //⑩

   if atomic.LoadInt32(&self.canStart) == 0 { //⑪
      log.Info("Network syncing, will start miner afterwards")
      return
   }
   self.worker.start()
}
// miner/worker.go:268
func (w *worker) start() { //⑬
	atomic.StoreInt32(&w.running, 1)
	w.startCh <- struct{}{}
}
```

存储coinbase 账户后⑩，有可能因为正在同步数据，此时将不允许启动挖矿⑪。如果能够启动挖矿，则立即开启worker 让其开始干活。只需要发送一个开启挖矿信号，worker 将会被自动触发挖矿工作。



## Worker Start 信号

对 worker 发送 start 信号后，该信号将进入 startCh chain中。一旦获得信号，则立即重新开始commit新区块，重新开始干活。

```go
//miner/worker.go:342
for {
   select {
   case <-w.startCh:
      clearPending(w.chain.CurrentBlock().NumberU64())
      timestamp = time.Now().Unix()
      commit(false, commitInterruptNewHead)
   //...
   }
}
```

[^1]: dgeth 是本电子书书写期初指导大家所编译的一个 geth 程序。具体见[《开始》]({{< ref "first.md#编译geth" >}})

