## 交易的数据结构
交易的数据结构定义在core.types.transaction.go中，结构如下：
```
    type Transaction struct {
        data txdata
        // caches
        hash atomic.Value
        size atomic.Value
        from atomic.Value
    }
```
交易的结构体中只有一个data字段，是txdata类型的。其他的hash，size，from都是缓存。
txdata结构体定义如下：
```
    type txdata struct {
        AccountNonce uint64          `json:"nonce"    gencodec:"required"`
        Price        *big.Int        `json:"gasPrice" gencodec:"required"`
        GasLimit     uint64          `json:"gas"      gencodec:"required"`
        Recipient    *common.Address `json:"to"       rlp:"nil"` // nil means contract creation
        Amount       *big.Int        `json:"value"    gencodec:"required"`
        Payload      []byte          `json:"input"    gencodec:"required"`
    
        // Signature values
        V *big.Int `json:"v" gencodec:"required"`
        R *big.Int `json:"r" gencodec:"required"`
        S *big.Int `json:"s" gencodec:"required"`
    
        // This is only used when marshaling to JSON.
        Hash *common.Hash `json:"hash" rlp:"-"`
    }
```
AccountNonce是交易发送者已经发送交易的次数
Price是此交易的gas费用
GasLimit是本次交易允许消耗gas的最大数量
Recipient是交易的接收者
Amount是交易的以太坊数量
Payload是交易携带的数据
V，R，S是交易的签名数据
这里没有交易的发起者，因为发起者可以通过签名的数据获得。
## 交易的hash
交易的hash会首先从Transaction的缓存中读取hash，如果缓存中没有，则通过rlpHash来计算hash，并将hash放入到缓存中。
交易的hash是通过Hash()方法获得的。
```
// Hash hashes the RLP encoding of tx.
// It uniquely identifies the transaction.
    func (tx *Transaction) Hash() common.Hash {
        if hash := tx.hash.Load(); hash != nil {
            return hash.(common.Hash)
        }
        v := rlpHash(tx)
        tx.hash.Store(v)
        return v
    }
```
这里交易的hash实际上是对Transaction结构体重的data字段进行hash得到的结果。
##交易类型
目前交易有两种类型
第一种是以太坊转账，这里在创建交易时需要在sendTransaction写入to字段，即写转到的地址。
第二种是合约交易，以太坊代码中定义在发送合约交易时，sendTransaction中的to字段置空，这样就能够知道是合约交易。
在执行交易时，在命令行中调用eth.sendTransaction即可执行交易。
sendTransaction具体的实现在account下的eth account analysis.md文件中。