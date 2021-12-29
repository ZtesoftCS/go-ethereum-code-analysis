---
title: "以太坊交易回执-Receipt"
menuTitle: "交易回执"
weight: 100007
---

不同于比特币，以太坊作为智能合约平台。每一笔交易作为消息在以太坊虚拟机中执行时，均会获得一个交易回执信息(Receipt)。形同在银行转账后，可以获得关于这笔转账的交易电子回单。

![招商银行电子回单](https://img.learnblockchain.cn/2019/05/21_Transaction-receipt.png!de)

同样，在以太坊中一份交易回执记录了关于此笔交易的处理结果信息：

![以太坊交易回执数据结构](https://img.learnblockchain.cn/2019/05/21_ethereum-tx-receipt-struct.png!de)

回执信息分为三部分：共识信息、交易信息、区块信息。下面分别介绍各类信息。

![以太坊交易回执内容分类](https://img.learnblockchain.cn/2019/05/21_ethereum-tx-receipt-struct-category.png!de)

## 交易回执内容介绍

### 交易回执共识信息

共识信息意味着在校验区块合法性时，这部分信息也参与校验。这些信息参与校验的原因是确保交易必须在区块中的固定顺序中执行，且记录了交易执行后的状态信息。这样可强化交易顺序。

+ Status： 成功与否，1表示成功，0表示失败。注意在高度1035301前，并非1或0，而是 StateRoot，表示此交易执行完毕后的以太坊状态。
  ```go
  //core/state_processor.go:104
  var root []byte
  if config.IsByzantium(header.Number) {
     statedb.Finalise(true)
  } else {
     root = statedb.IntermediateRoot(config.IsEIP158(header.Number)).Bytes()
  }
  //...
  receipt := types.NewReceipt(root, failed, *usedGas)
  ```
+ CumulativeGasUsed： 区块中已执行的交易累计消耗的Gas，包含当前交易。
+ Logs:  当前交易执行所产生的智能合约事件列表。
+ Bloom：是从 Logs 中提取的事件布隆过滤器，用于快速检测某主题的事件是否存在于Logs中。

这些信息是如何参与共识校验的呢？实际上参与校验的仅仅是回执哈希，而回执哈希计算只包含这些信息。
首先，在校验时获取整个区块回执信息的默克尔树的根哈希值。再判断此哈希值是否同区块头定义内容相同。

```go
//core/block_validator.go:92
receiptSha := types.DeriveSha(receipts)
if receiptSha != header.ReceiptHash {
   return fmt.Errorf("invalid receipt root hash (remote: %x local: %x)",
   header.ReceiptHash, receiptSha)
}
```

而函数`types.DeriveSha`中生成根哈希值，是将列表元素（这里是交易回执）的RLP编码信息构成默克树，最终获得列表的哈希值。

```go
//core/types/derive_sha.go:32
func DeriveSha(list DerivableList) common.Hash {
   keybuf := new(bytes.Buffer)
   trie := new(trie.Trie)
   for i := 0; i < list.Len(); i++ {
      keybuf.Reset()
      rlp.Encode(keybuf, uint(i))
      trie.Update(keybuf.Bytes(), list.GetRlp(i))
   }
   return trie.Hash()
}
// core/types/receipt.go:237
func (r Receipts) GetRlp(i int) []byte {
   bytes, err := rlp.EncodeToBytes(r[i])
   if err != nil {
      panic(err)
   }
   return bytes
}
```

继续往下看，交易回执实现了 RLP 编码接口。在方法`EncodeRLP`中是构建了一个私有的`receiptRLP`。
```go
//core/types/receipt.go:119
func (r *Receipt) EncodeRLP(w io.Writer) error {
	return rlp.Encode(w, 
	&receiptRLP{r.statusEncoding(), r.CumulativeGasUsed, r.Bloom, r.Logs})
}
```

从代码中可以看出 `receiptRLP` 仅仅包含上面提到的参与共识校验的内容。

```go
//core/types/receipt.go:78
type receiptRLP struct {
   PostStateOrStatus []byte
   CumulativeGasUsed uint64
   Bloom             Bloom
   Logs              []*Log
}
```

### 交易回执交易信息

这部分信息记录的是关于回执所对应的交易信息，有：

+ TxHash ： 交易回执所对应的交易哈希。
+ ContractAddress： 当这笔交易是部署新合约时，记录新合约的地址。

  ```go
  //core/state_processor.go:118
  if msg.To() == nil {
     receipt.ContractAddress = crypto.CreateAddress(vmenv.Context.Origin, tx.Nonce())
  }
  ```
  
+ GasUsed: 这笔交易执行所消耗的[Gas燃料]({{< ref "./gas.md" >}})。

这些信息不参与共识的原因是这三项信息已经在其他地方校验。

+ TxHash: 区块有校验交易集的正确性。
+ ContractAddress： 如果是新合约，实际上已经提交到以太坊状态 State 中。
+ GasUsed： 已属于CumulativeGasUsed的一部分。

### 交易回执区块信息

这部分信息完全是为了方便外部读取交易回执，不但知道交易执行情况，还能方便的指定该交易属于哪个区块中第几笔交易。

+ BlockHash: 交易所在区块哈希。
+ BlockNumber: 交易所在区块高度。
+ TransactionIndex： 交易在区块中的序号。

这三项信息，主要是在数据库 Leveldb 中读取交易回执时，实时指定。

```go
//core/rawdb/accessors_chain.go:315
receipts := make(types.Receipts, len(storageReceipts))
logIndex := uint(0)
for i, receipt := range storageReceipts {
   //...
   receipts[i] = (*types.Receipt)(receipt)
   receipts[i].BlockHash = hash
   receipts[i].BlockNumber = big.NewInt(0).SetUint64(number)
   receipts[i].TransactionIndex = uint(i)
}
```

## 交易回执构造

交易回执是在以太坊虚拟机处理完交易后，根据结果整理出的交易执行结果信息。反映了交易执行前后以太坊变化以及交易执行状态。

构造细节，已经在前面提及，不再细说。这里给出的完整的交易回执构造代码。

```go
// core/state_processor.go:94
context := NewEVMContext(msg, header, bc, author) 
vmenv := vm.NewEVM(context, statedb, config, cfg) 
_, gas, failed, err := ApplyMessage(vmenv, msg, gp)
if err != nil {
   return nil, 0, err
} 
var root []byte
if config.IsByzantium(header.Number) {
   statedb.Finalise(true)
} else {
   root = statedb.IntermediateRoot(config.IsEIP158(header.Number)).Bytes()
}
*usedGas += gas
 
receipt := types.NewReceipt(root, failed, *usedGas)
receipt.TxHash = tx.Hash()
receipt.GasUsed = gas 
if msg.To() == nil {
   receipt.ContractAddress = crypto.CreateAddress(vmenv.Context.Origin, tx.Nonce())
} 
receipt.Logs = statedb.GetLogs(tx.Hash())
receipt.Bloom = types.CreateBloom(types.Receipts{receipt})
receipt.BlockHash = statedb.BlockHash()
receipt.BlockNumber = header.Number
receipt.TransactionIndex = uint(statedb.TxIndex())

return receipt, gas, err
```

## 交易回执存储

交易回执作为交易执行中间产物，为了方便快速获取某笔交易的执行明细。以太坊中有跟随区块存储时实时存储交易回执。但为了降低存储量，只存储了必要内容。

首先，在存储时，将交易回执对象转换为精简内容。

```go
//core/rawdb/accessors_chain.go:338
storageReceipts := make([]*types.ReceiptForStorage, len(receipts))
for i, receipt := range receipts {
   storageReceipts[i] = (*types.ReceiptForStorage)(receipt)
}
```

精简内容是专门为存储定义的一个结构`ReceiptForStorage`。存储时将交易回执集进行RLP编码存储。

```go
//core/rawdb/accessors_chain.go:342
bytes, err := rlp.EncodeToBytes(storageReceipts)
if err != nil {
   log.Crit("Failed to encode block receipts", "err", err)
} 
if err := db.Put(blockReceiptsKey(number, hash), bytes); err != nil {
   log.Crit("Failed to store block receipts", "err", err)
}
```

所以看存储了哪些内容，只需要看 `ReceiptForStorage`的 `EncodeRLP`方法：

```go
//core/types/receipt.go:179
func (r *ReceiptForStorage) EncodeRLP(w io.Writer) error {
   enc := &receiptStorageRLP{
      PostStateOrStatus: (*Receipt)(r).statusEncoding(),
      CumulativeGasUsed: r.CumulativeGasUsed,
      TxHash:            r.TxHash,
      ContractAddress:   r.ContractAddress,
      Logs:              make([]*LogForStorage, len(r.Logs)),
      GasUsed:           r.GasUsed,
   }
   for i, log := range r.Logs {
      enc.Logs[i] = (*LogForStorage)(log)
   }
   return rlp.Encode(w, enc)
}
```

根据`EncodeRLP`方法实现，可以得出在存储时仅仅存储了部分内容，且 Logs 内容同样进行了特殊处理`LogForStorage`。 

![交易回执存储部分](https://img.learnblockchain.cn/2019/05/22_ethereum-tx-receipt-storage.png)

## 交易回执示例

上面讲完交易回执内容与构造和存储，下面我从etherscan上查找三中不同类型的交易回执数据，供大家找找感觉。

### 一笔包含日志的交易回执

交易 [0x01e180......0a4021](https://etherscan.io/tx/0x01e1808b12e0392a2f13e6e480a22cd48abe21a62a12b4763b7573682a0a4021) 执行成功，且包含了两个事件日志。
![](https://img.learnblockchain.cn/2019/05/21_ethereum-tx-recipe.png!wl)

### 一笔成功部署合约的交易回执

如果是部署合约的交易，可以看到 contractAddress 有值。
![](https://img.learnblockchain.cn/2019/05/22_ethereum-tx-receipt-data-demo2.png!de)

### 一笔含 StateRoot的交易回执

和其他交易回执内容不同，在高度1035301 前的交易并无 status 字段，而是 root 字段。是在后续改进中去除 root 采用 status 的。
![](https://img.learnblockchain.cn/2019/05/22_ethereum-tx-receipt-data-demo3-root.png!de)

### 一笔交易失败的交易回执

如果是失败的交易，则 `status`为0。
 ![](https://img.learnblockchain.cn/2019/05/22_ethereum-tx-receipt-data-demo3-failed.png!de)
