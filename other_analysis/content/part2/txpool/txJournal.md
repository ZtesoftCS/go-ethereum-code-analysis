---
title: "本地待处理交易存储"
menuTitle: "交易存储"
date: 2019-07-31T22:58:46+08:00
weight: 20202
---

上篇在介绍交易池时有讲到对于本地交易的特殊处理。为了不丢失未完成的本地交易，以太坊交易池通过 journal 文件存储和管理当前交易池中的本地交易，并定期更新存储。

下图是交易池对本地待处理交易的磁盘存储管理流程，涉及加载、实时写入和定期更新维护。
![以太坊交易池本地待处理交易存储管理](https://img.learnblockchain.cn/book_geth/image-20190622233938478.png!de)

## 加载已存储交易

在交易池首次启动 journal 时，将主动将该文件已存储的交易加载到交易池。

```go
//core/tx_journal.go:61
if _, err := os.Stat(journal.path); os.IsNotExist(err) { //❶
   return nil
}
// Open the journal for loading any past transactions
input, err := os.Open(journal.path) //❷
if err != nil {
   return err
}
defer input.Close()
```

处理时，如果文件不存在则退出 ❶，否则 Open 文件，获得 input 文件流 ❷。

```go
//core/tx_journal.go:76
stream := rlp.NewStream(input, 0)//❸
total, dropped := 0, 0
```

因为存储的内容格式是 rlp 编码内容，因此可以直接初始化 rlp 内容流 ❸，为连续解码做准备。

```go
var (
   failure error
   batch   types.Transactions
)
for {
   tx := new(types.Transaction)
   if err = stream.Decode(tx); err != nil { //❹
      if err != io.EOF {
         failure = err
      }
      if batch.Len() > 0 {//❼
         loadBatch(batch)
      }
      break
   }
   total++

   if batch = append(batch, tx); batch.Len() > 1024 {//❺
      loadBatch(batch)//❻
      batch = batch[:0]
   }
}
```

直接进入 for 循环遍历，不断从 stream 中一笔笔地解码出交易❹。但交易并非单笔直接载入交易池，而是采用批量提交模式，每 1024 笔交易提交一次 ❺。 批量写入，有利于降低交易池在每次写入交易后的更新。一个批次只需要更新（排序与超限处理等）一次。当然在遍历结束时（err==io.EOF）,也需要将当前批次中的交易载入❼。

```go
loadBatch := func(txs types.Transactions) {
   for _, err := range add(txs) {
      if err != nil {
         log.Debug("Failed to add journaled transaction", "err", err)
         dropped++ //❽
      }
   }
}
```

loadBatch 就是将交易一批次加入到交易池，并获得交易池的每笔交易的处理情况。如果交易加入失败，则进行计数 ❽。最终在 load 方法执行完毕时，显示交易载入情况。

```go
log.Info("Loaded local transaction journal", "transactions", total, "dropped", dropped)
```

##  存储交易

![以太坊存储本地交易](https://img.learnblockchain.cn/book_geth/image-20190622234643382.png!de)

当交易池新交易来自于本地账户时❶，如果已开启记录本地交易，则将此交易加入journal ❷。到交易池时，将实时存储到 journal 文件中。

```go
//core/tx_pool.go:757
func (pool *TxPool) journalTx(from common.Address, tx *types.Transaction) {
   // Only journal if it's enabled and the transaction is local
   if pool.journal == nil || !pool.locals.contains(from) {//❶
      return
   }
   if err := pool.journal.insert(tx); err != nil { //❷
      log.Warn("Failed to journal local transaction", "err", err)
   }
}
```

而 `journal.insert`则将交易实时写入文件流中❸，相当于实时存储到磁盘。而在写入时，是将交易进行RLP编码。

```go
//core/tx_journal.go:120
func (journal *txJournal) insert(tx *types.Transaction) error {
   if journal.writer == nil {
      return errNoActiveJournal
   }
   if err := rlp.Encode(journal.writer, tx); err != nil {//❸
      return err
   }
   return nil
}
```

这里引发了在上面载入已存储交易时将交易重复写入文件。因此在加载交易时，使用一个 空 writer 替代 ❹。

```
//core/tx_journal.go:72
journal.writer = new(devNull) //❹
defer func() { journal.writer = nil }() //❺
```

并且在加载结束时清理❺。

## 定期更新 journal

![image-20190622234757114](https://img.learnblockchain.cn/book_geth/image-20190622234757114.png!de)

journal 的目的是长期存储本地尚未完成的交易，以便交易不丢失。而文件内容属于交易的RLP编码内容，不便于实时清空已完成或已无效的交易。因此以太坊采取的是定期将交易池在途交易更新到 journal 文件中。

首先，在首次加载文件中的交易到交易池后，利用交易池的检查功能，将已完成或者已完成的交易拒绝在交易池外。在加载完成后，交易池中的交易仅仅是本地账户待处理的交易，因此在加载完成后❶，立即将交易池中的所有本地交易覆盖journal文件❷。

```go
//core/tx_pool.go:264
pool.journal = newTxJournal(config.Journal)

if err := pool.journal.load(pool.AddLocals); err != nil {//❶
   log.Warn("Failed to load transaction journal", "err", err)
}
if err := pool.journal.rotate(pool.local()); err != nil {//❷
   log.Warn("Failed to rotate transaction journal", "err", err)
}
```

在 rotate 中，并非直接覆盖。而是先创建另一个新文件❸，将所有交易RLP编码写入此文件❹ 。

```go
replacement, err := os.OpenFile(journal.path+".new",  //❸
                                os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0755)
if err != nil {
   return err
}
journaled := 0
for _, txs := range all {
   for _, tx := range txs {
      if err = rlp.Encode(replacement, tx); err != nil {//❹
         replacement.Close()
         return err
      }
}
   journaled += len(txs)
}
replacement.Close()
```

写入完毕，将此文件直接移动（重命名），已覆盖原 journal 文件。

```
if err = os.Rename(journal.path+".new", journal.path); err != nil {
   return err
}
```

其次，是交易池根据参数 `txpool.rejournal` 所设置的更新间隔定期更新❺。将交易池中的本地交易存储到磁盘❻。

```go
//core/tx_pool.go:298
journal := time.NewTicker(pool.config.Rejournal)//❺
//...
for {
  select {
    //...
    case <-journal.C:
			if pool.journal != nil {
				pool.mu.Lock()
				if err := pool.journal.rotate(pool.local()); err != nil { //❻
					log.Warn("Failed to rotate local tx journal", "err", err)
				}
				pool.mu.Unlock()
			}
		}
  }
}
```

上述，是以太坊交易池对于本地交易进行持久化存储管理细节。