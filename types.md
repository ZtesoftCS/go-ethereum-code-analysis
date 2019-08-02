# core/types
### core/types/block.go
block data stucture:
<pre><code>type Block struct {
	header       *Header
	uncles       []*Header
	transactions Transactions
	hash atomic.Value
	size atomic.Value
	td *big.Int
	ReceivedAt   time.Time
	ReceivedFrom interface{}
}</code></pre>
|字段	|描述|
|--------|------------------------------|
|header	 |指向 Header 结构（之后会详细说明），header 存储一个区块的基本信息。|
|uncles	 |指向 Header 结构|
|transactions|	一组 transaction 结构|
|hash	|当前区块的哈希值|
|size	|当前区块的大小|
|td	|当前区块高度|
|ReceivedAt|	接收时间|
|ReceivedFrom|	来源|
交易组成区块，一个一个区块以单向链表的形式连在一起组成区块链
</br>Ｈｅａｄｅｒ data structure:
<pre><code>type Header struct {
	ParentHash  common.Hash    `json:"parentHash"       gencodec:"required"`
	UncleHash   common.Hash    `json:"sha3Uncles"       gencodec:"required"`
	Coinbase    common.Address `json:"miner"            gencodec:"required"`
	Root        common.Hash    `json:"stateRoot"        gencodec:"required"`
	TxHash      common.Hash    `json:"transactionsRoot" gencodec:"required"`
	ReceiptHash common.Hash    `json:"receiptsRoot"     gencodec:"required"`
	Bloom       Bloom          `json:"logsBloom"        gencodec:"required"`
	Difficulty  *big.Int       `json:"difficulty"       gencodec:"required"`
	Number      *big.Int       `json:"number"           gencodec:"required"`
	GasLimit    uint64         `json:"gasLimit"         gencodec:"required"`
	GasUsed     uint64         `json:"gasUsed"          gencodec:"required"`
	Time        *big.Int       `json:"timestamp"        gencodec:"required"`
	Extra       []byte         `json:"extraData"        gencodec:"required"`
	MixDigest   common.Hash    `json:"mixHash"          gencodec:"required"`
	Nonce       BlockNonce     `json:"nonce"            gencodec:"required"`
}</code></pre>
|字段|	描述|
|--------|-------|
|ParentHash|	父区块的哈希值|
|UncleHash	|叔区块的哈希值|
|Coinbase	|矿工得到奖励的账户，一般是矿工本地第一个账户|
|Root	|表示当前所有用户状态|
|TxHash	|本区块所有交易 Hash，即摘要|
|ReceiptHash	|本区块所有收据 Hash，即摘要|
|Bloom	|布隆过滤器，用来搜索收据|
|Difficulty	|该区块难度，动态调整，与父区块和本区块挖矿时间有关。
|Number	|该区块高度|
|GasLimit	gas |用量上限，该数值根据父区块 gas 用量调节，如果 parentGasUsed > parentGasLimit * (2/3) ，则增大该数值，反之则减小该数值。|
|GasUsed	|实际花费的 gas|
|Time	|新区块的出块时间，严格来说是开始挖矿的时间|
|Extra	|额外数据|
|MixDigest|	混合哈希，与nonce 结合使用|
|Nonce	|加密学中的概念|
ParentHash 表示该区块的父区块哈希，我们通过 ParentHash 这个字段将一个一个区块连接起来组成区块链，但实际上我们并不会直接将链整个的存起来，它是以一定的数据结构一块一块存放的，geth 的底层数据库用的是 LevelDB，这是一个 key-value 数据库，要得到父区块时，我们通过 ParentHash 以及其他字符串组成 key，在 LevelDB 中查询该 key 对应的值，就能拿到父区块。
