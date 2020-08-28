##  区块存储
区块的存储是由leveldb完成的，leveldb的数据是以键值对存储的。在这里保存区块信息时，key一般是与hash相关的，value所保存的数据结构是经过RLP编码的。<br>
在代码中，core/database_util.go中封装了区块存储和读取相关的代码。<br>
在存储区块信息时，会将区块头和区块体分开进行存储。因此在区块的结构体中，能够看到Header和Body两个结构体。<br>
区块头（Header）的存储格式为：
```
    headerPrefix + num (uint64 big endian) + hash -> rlpEncode(header)
```
key是由区块头的前缀，区块号和区块hash构成。value是区块头的RLP编码。<br>
区块体（Body）的存储格式为：
```
    bodyPrefix + num (uint64 big endian) + hash -> rlpEncode(block body)
```
key是由区块体前缀，区块号和区块hash构成。value是区块体的RLP编码。<br>
在database_util.go中，key的前缀可以区分leveldb中存储的是什么类型的数据。
```
    var (
        headHeaderKey = []byte("LastHeader")
        headBlockKey  = []byte("LastBlock")
        headFastKey   = []byte("LastFast")
    
        // Data item prefixes (use single byte to avoid mixing data types, avoid `i`).
        headerPrefix        = []byte("h") // headerPrefix + num (uint64 big endian) + hash -> header
        tdSuffix            = []byte("t") // headerPrefix + num (uint64 big endian) + hash + tdSuffix -> td
        numSuffix           = []byte("n") // headerPrefix + num (uint64 big endian) + numSuffix -> hash
        blockHashPrefix     = []byte("H") // blockHashPrefix + hash -> num (uint64 big endian)
        bodyPrefix          = []byte("b") // bodyPrefix + num (uint64 big endian) + hash -> block body
        blockReceiptsPrefix = []byte("r") // blockReceiptsPrefix + num (uint64 big endian) + hash -> block receipts
        lookupPrefix        = []byte("l") // lookupPrefix + hash -> transaction/receipt lookup metadata
        bloomBitsPrefix     = []byte("B") // bloomBitsPrefix + bit (uint16 big endian) + section (uint64 big endian) + hash -> bloom bits
    
        preimagePrefix = "secure-key-"              // preimagePrefix + hash -> preimage
        configPrefix   = []byte("ethereum-config-") // config prefix for the db
    
        // Chain index prefixes (use `i` + single byte to avoid mixing data types).
        BloomBitsIndexPrefix = []byte("iB") // BloomBitsIndexPrefix is the data table of a chain indexer to track its progress
    
        // used by old db, now only used for conversion
        oldReceiptsPrefix = []byte("receipts-")
        oldTxMetaSuffix   = []byte{0x01}
    
        ErrChainConfigNotFound = errors.New("ChainConfig not found") // general config not found error
    
        preimageCounter    = metrics.NewCounter("db/preimage/total")
        preimageHitCounter = metrics.NewCounter("db/preimage/hits")
    )
```
database_util.go最开始就定义了所有的前缀。这里的注释详细说明了每一个前缀存储了什么数据类型。<br>
database_util.go中的其他方法则是对leveldb的操作。其中get方法是读取数据库中的内容，write则是向leveldb中写入数据。<br>
要讲一个区块的信息写入数据库，则需要调用其中的WriteBlock方法。
```
// WriteBlock serializes a block into the database, header and body separately.
    func WriteBlock(db ethdb.Putter, block *types.Block) error {
        // Store the body first to retain database consistency
        if err := WriteBody(db, block.Hash(), block.NumberU64(), block.Body()); err != nil {
            return err
        }
        // Store the header too, signaling full block ownership
        if err := WriteHeader(db, block.Header()); err != nil {
            return err
        }
        return nil
    }
```
这里我们看到，将一个区块信息写入数据库其实是分别将区块头和区块体写入数据库。<br>
首先来看区块头的存储。区块头的存储是由WriteHeader方法完成的。
```
    // WriteHeader serializes a block header into the database.
    func WriteHeader(db ethdb.Putter, header *types.Header) error {
        data, err := rlp.EncodeToBytes(header)
        if err != nil {
            return err
        }
        hash := header.Hash().Bytes()
        num := header.Number.Uint64()
        encNum := encodeBlockNumber(num)
        key := append(blockHashPrefix, hash...)
        if err := db.Put(key, encNum); err != nil {
            log.Crit("Failed to store hash to number mapping", "err", err)
        }
        key = append(append(headerPrefix, encNum...), hash...)
        if err := db.Put(key, data); err != nil {
            log.Crit("Failed to store header", "err", err)
        }
        return nil
    }
```
这里首先对区块头进行了RLP编码，然后将区块号转换成为byte格式，开始组装key。<br>
这里首先向数据库中存储了一条区块hash->区块号的键值对，然后才将区块头的信息写入数据库。<br>
接下来是区块体的存储。区块体存储是由WriteBody方法实现。
```
// WriteBody serializes the body of a block into the database.
    func WriteBody(db ethdb.Putter, hash common.Hash, number uint64, body *types.Body) error {
        data, err := rlp.EncodeToBytes(body)
        if err != nil {
            return err
        }
        return WriteBodyRLP(db, hash, number, data)
    }

// WriteBodyRLP writes a serialized body of a block into the database.
    func WriteBodyRLP(db ethdb.Putter, hash common.Hash, number uint64, rlp rlp.RawValue) error {
        key := append(append(bodyPrefix, encodeBlockNumber(number)...), hash.Bytes()...)
        if err := db.Put(key, rlp); err != nil {
            log.Crit("Failed to store block body", "err", err)
        }
        return nil
    }
```
WriteBody首先将区块体的信息进行RLP编码，然后调用WriteBodyRLP方法将区块体的信息写入数据库。key的组装方法如之前所述。<br>
## 交易存储
交易主要在数据库中仅存储交易的Meta信息。
```
    txHash + txMetaSuffix -> rlpEncode(txMeta)
```
交易的Meta信息结构体如下：
```
// TxLookupEntry is a positional metadata to help looking up the data content of
// a transaction or receipt given only its hash.
    type TxLookupEntry struct {
        BlockHash  common.Hash
        BlockIndex uint64
        Index      uint64
    }
```
这里，meta信息会存储块的hash，块号和块上第几笔交易这些信息。<br>
交易Meta存储是以交易hash加交易的Meta前缀为key，Meta的RLP编码为value。<br>
交易写入数据库是通过WriteTxLookupEntries方法实现的。
```
// WriteTxLookupEntries stores a positional metadata for every transaction from
// a block, enabling hash based transaction and receipt lookups.
    func WriteTxLookupEntries(db ethdb.Putter, block *types.Block) error {
        // Iterate over each transaction and encode its metadata
        for i, tx := range block.Transactions() {
            entry := TxLookupEntry{
                BlockHash:  block.Hash(),
                BlockIndex: block.NumberU64(),
                Index:      uint64(i),
            }
            data, err := rlp.EncodeToBytes(entry)
            if err != nil {
                return err
            }
            if err := db.Put(append(lookupPrefix, tx.Hash().Bytes()...), data); err != nil {
                return err
            }
        }
        return nil
    }
```
这里，在将交易meta入库时，会遍历块上的所有交易，并构造交易的meta信息，进行RLP编码。然后以交易hash为key，meta为value进行存储。<br>
这样就将一笔交易写入数据库中。<br>
从数据库中读取交易信息时通过GetTransaction方法获得的。
```
// GetTransaction retrieves a specific transaction from the database, along with
// its added positional metadata.
    func GetTransaction(db DatabaseReader, hash common.Hash) (*types.Transaction, common.Hash, uint64, uint64) {
        // Retrieve the lookup metadata and resolve the transaction from the body
        blockHash, blockNumber, txIndex := GetTxLookupEntry(db, hash)
    
        if blockHash != (common.Hash{}) {
            body := GetBody(db, blockHash, blockNumber)
            if body == nil || len(body.Transactions) <= int(txIndex) {
                log.Error("Transaction referenced missing", "number", blockNumber, "hash", blockHash, "index", txIndex)
                return nil, common.Hash{}, 0, 0
            }
            return body.Transactions[txIndex], blockHash, blockNumber, txIndex
        }
        // Old transaction representation, load the transaction and it's metadata separately
        data, _ := db.Get(hash.Bytes())
        if len(data) == 0 {
            return nil, common.Hash{}, 0, 0
        }
        var tx types.Transaction
        if err := rlp.DecodeBytes(data, &tx); err != nil {
            return nil, common.Hash{}, 0, 0
        }
        // Retrieve the blockchain positional metadata
        data, _ = db.Get(append(hash.Bytes(), oldTxMetaSuffix...))
        if len(data) == 0 {
            return nil, common.Hash{}, 0, 0
        }
        var entry TxLookupEntry
        if err := rlp.DecodeBytes(data, &entry); err != nil {
            return nil, common.Hash{}, 0, 0
        }
        return &tx, entry.BlockHash, entry.BlockIndex, entry.Index
    }
```
这个方法会首先通过交易hash从数据库中获取交易的meta信息，包括交易所在块的hash，块号和第几笔交易。<br>
接下来使用块号和块hash获取从数据库中读取块的信息。<br>
然后根据第几笔交易从块上获取交易的具体信息。<br>
这里以太坊将交易的存储换成了新的存储方式，即交易的具体信息存储在块上，交易hash只对应交易的meta信息，并不包含交易的具体信息。<br>
而以前的交易存储则是需要存储交易的具体信息和meta信息。<br>
因此GetTransaction方法会支持原有的数据存储方式。