---
title: "账户"
weight: 100003
---
 

对比比特币的 “UTXO” 余额模型，以太坊使用“账户”余额模型。
以太坊丰富了账户内容，除余额外还能自定义存放任意多数据。
并利用账户数据的可维护性，构建智能合约账户。

实际上以太坊是为了实现智能合约而提炼的账户模型。
以账户为单位，安全隔离数据。
账户间信息相互独立，互不干扰。
再配合以太坊虚拟机，让智能合约沙盒运行。

以太坊作为智能合约操作平台，将账户划分为两类：外部账户（EOAs）和合约账户（contract account）。

## 账户基本概念

### 外部账户

EOAs-外部账户(external owned accouts)是由人们通过私钥创建的账户。
是真实世界的金融账户的映射，拥有该账户私钥的任何人都可以控制该账户。
如同银行卡，到ATM机取款时只需要密码输入正确即可交易。
这也是人类与以太坊账本沟通的唯一媒介，因为以太坊中的交易需要签名，
而只能使用拥有私有外部账户签名。

外部账户特点总结：

1. 拥有以太余额。
1. 能发送交易，包括转账和执行合约代码。
1. 被私钥控制。
1. 没有相关的可执行代码。

### 合约账户

含有合约代码的账户。
被外部账户或者合约创建，合约在创建时被自动分配到一个账户地址，
用于存储合约代码以及合约部署或执行过程中产生的存储数据。
合约账户地址是通过SHA3哈希算法产生，而非私钥。
因无私钥，因此无人可以拿合约账户当做外部账户使用。
只能通过外部账户来驱动合约执行合约代码。

下面是合约地址生成算法：`Keccak256(rlp([sender,nonce])[12:]`

```go
// crypto/crypto.go:74
func CreateAddress(b common.Address, nonce uint64) common.Address {
    data, _ := rlp.EncodeToBytes([]interface{}{b, nonce})
    return common.BytesToAddress(Keccak256(data)[12:])
}
```

因为合约由其他账户创建，因此将创建者地址和该交易的随机数进行哈希后截取部分生成。

特别需要注意的是，在[EIP1014](http://eips.ethereum.org/EIPS/eip-1014)中提出的另一种生成合约地址的算法。
其目的是为状态通道提供便利，通过确定内容输出稳定的合约地址。
在部署合约前就可以知道确切的合约地址。下面是算法方法:`keccak256( 0xff ++ address ++ salt ++ keccak256(init_code))[12:]`。

```go
// crypto/crypto.go:81
func CreateAddress2(b common.Address, salt [32]byte, inithash []byte) common.Address {
    return common.BytesToAddress(Keccak256([]byte{0xff}, b.Bytes(), salt[:], inithash)[12:])
}
```

合约账户特点总结：

1. 拥有以太余额。
2. 有相关的可执行代码（合约代码）。
3. 合约代码能够被交易或者其他合约消息调用。
4. 合约代码被执行时可再调用其他合约代码。
5. 合约代码被执行时可执行复杂运算，可永久地改变合约内部的数据存储。


### 差异对比

综上，下面表格列出两类账户差异，合约账户更优于外部账户。
但外部账户是人们和以太坊沟通的唯一媒介，和合约账户相辅相成。

|项|外部账户|合约账户|
|----|----|----|
|私钥 private Key| ✔️ | ✖️|
|余额 balance| ✔️ |✔️|
|代码 code|  ✖️|✔️|
|多重签名| ✖️|✔️|
|控制方式| 私钥控制 | 通过外部账户执行合约 |

上面有列出多重签名，是因为以太坊外部账户只由一个独立私钥创建，无法进行多签。
但合约具有可编程性，可编写符合多重签名的逻辑，实现一个支持多签的账户。

## 账户数据结构

以太坊数据以账户为单位组织，账户数据的变更引起账户状态变化。
从而引起以太坊状态变化（关于以太坊状态，后续另写文章介绍）。

在程序逻辑上两类账户的数据结构一致：

![以太坊账户数据结构](https://img.learnblockchain.cn/2019/04/14_以太坊账户数据结构1.png!de)

对应代码如下：

```go
// core/state/state_object.go:100
type Account struct {
    Nonce    uint64
    Balance  *big.Int
    Root     common.Hash
    CodeHash []byte
}
```

但在数据存储上稍有不同，
因为外部账户无内部存储数据和合约代码，因此外部账户数据中 `StateRootHash` 和 `CodeHash` 是一个空默认值。
一旦属于空默认值，则不会存储对应物理数据库中。
在程序逻辑上，存在`code`则为合约账户。
即 `CodeHash` 为空值时，账户是一个外部账户，否则是合约账户。

![以太坊账户数据存储结构](https://img.learnblockchain.cn/2019/04/14_以太坊账户数据存储结构.png!de)

上图是以太坊账户数据存储结构，账户内部实际只存储关键数据，而合约代码以及合约自身数据则通过对应的哈希值关联。
因为每个账户对象，将作为一个以太坊账户树的一个叶子数据存储，
不能太大。

从以太坊作为一个世界态(World State)状态机视角看数据关系如下：

![以太坊世界态](https://img.learnblockchain.cn/2019/05/19_ethereum-global-state.png!de)

在密码学领域，Nonce 代表一个只使用一次的数字。它往往是一个随机或伪随机数，以避免重复。
以太坊账户中加入 Nonce，可避免重放攻击（具体细节，在讲解以太坊交易流程时介绍），但不是随机产生。
账户 Nonce 起始值是 0，后续每触发一次账户执行则 Nonce 值计加一次。
其中一处的计数逻辑如下：

```go
// core/state_transition.go:212
st.state.SetNonce(msg.From(), st.state.GetNonce(sender.Address())+1)
```

这样的附加好处是，一般可将 Nonce 当做账户的交易次数计数器使用，特别是对于合约账户可以准确的记录合约被调用次数。

而`Balance`则记录该账户所拥有的以太（ETH）数量，称为账户余额
(注意，这里的余额的单位是 Wei )。
转移资产(Transfer)是在一个账户的`Balance`上计加，在另外一个账户计减。

```go
// core/evm.go:94
func Transfer(db vm.StateDB, sender, recipient common.Address, amount *big.Int) {
    db.SubBalance(sender, amount)
    db.AddBalance(recipient, amount)
}
// core/vm/evm.go:191
if !evm.Context.CanTransfer(evm.StateDB, caller.Address(), value) {
    return nil, gas, ErrInsufficientBalance
}
// core/vm/evm.go:214
evm.Transfer(evm.StateDB, caller.Address(), to.Address(), value)
```

当然必须保证转账方余额充足，在转移前需要`CanTransfer`检查，
如果余额充足，则执行`Transfer`转移`Value`数量的以太。

账户状态哈希值 `StateRoot`，是合约所拥有的方法、字段信息构成的一颗默克尔压缩前缀树（Merkle Patricia Tree 后续独立文章讲解）的根值，简单地讲是一颗二叉树的根节点值。
合约状态中的任意一项细微变动都最终引起 `StateRoot` 变化，因此合约状态变化会反映在账户的`StateRoot`上。

同时，你可以直接利用 `StateRoot` 从 Leveldb 中快速读取具体的某个状态数据，如合约的创建者。
通过以太坊API [web3.eth.getStorageAt](https://github.com/ethereum/wiki/wiki/JavaScript-API#web3ethgetstorageat) 可读取合约中任意位置的数据。

下面，我们通过一段示例代码，感受下以太坊账户数据存储。

```go
import(...)
var toAddr =common.HexToAddress
var toHash =common.BytesToHash

func main()  {
    statadb, _ := state.New(common.Hash{},
        state.NewDatabase(rawdb.NewMemoryDatabase()))// ❶

    acct1:=toAddr("0x0bB141C2F7d4d12B1D27E62F86254e6ccEd5FF9a")// ❷
    acct2:=toAddr("0x77de172A492C40217e48Ebb7EEFf9b2d7dF8151B")

    statadb.AddBalance(acct1,big.NewInt(100))
    statadb.AddBalance(acct2,big.NewInt(888))

    contract:=crypto.CreateAddress(acct1,statadb.GetNonce(acct1))//❸
    statadb.CreateAccount(contract)
    statadb.SetCode(contract,[]byte("contract code bytes"))//❹

    statadb.SetNonce(contract,1)
    statadb.SetState(contract,toHash([]byte("owner")),toHash(acct1.Bytes()))//❺
    statadb.SetState(contract,toHash([]byte("name")),toHash([]byte("ysqi")))

    statadb.SetState(contract,toHash([]byte("online")),toHash([]byte{1})
    statadb.SetState(contract,toHash([]byte("online")),toHash([]byte{}))//❻

    statadb.Commit(true)//❼
    fmt.Println(string(statadb.Dump()))//❽
}

```

上面代码中，我们创建了三个账户，并且提交到数据库中。最终打印出当前数据中所有账户的数据信息：

+ ❶ 一行代码涉及多个操作。首先是创建一个内存KV数据库，再包装为 stata 数据库实例，
最后利用一个空的DB级的`StateRoot`，初始化一个以太坊 statadb。
+ ❷ 定义两个账户 acct1和acct2，并分别添加100和888到账户余额。
+ ❸ 模拟合约账户的创建过程，由外部账户 acct1 创建合约账户地址，并将此地址载入 statadb。
+ ❹ 在将合约代码加入刚刚创建的合约账户中，在写入合约代码的同时，
会利用`crypto.Keccak256Hash(code)`计算合约代码哈希，保留在账户数据中。
+ ❺ 模拟合约执行过程，涉及修改合约状态，新增三项状态数据`owner`,`name`和`online`，分别对应不同值。
+ ❻ 这里和前面不同的是，是给状态`online`赋值为空`[]byte{}`，因为所有状态的默认值均是`[]byte{}`，
在提交到数据库时，如Leveldb 认为这些状态无有效值，会从数据库文件中删除此记录。
因此，此操作实际是一个删除状态`online`操作。
+ ❼ 上面所有操作，还都只是发生在 statdb 内存中，并未真正的写入数据库文件。
执行`Commit`，才会将关于 statadb 的所有变更更新到数据库文件中。
+ ❽ 一旦提交数据，则可以使用 `Dump` 命令从数据库中查找此 stata 相关的所有数据，包括所有账户。
并以 JSON 格式返还。这里，我们将返还结果直接打印输出。

代码执行输出结果如下：

```json
{
    "root": "3a25b0816cf007c0b878ca7a62ba35ee0337fa53703f281c41a791a137519f00",
    "accounts": {
        "0bb141c2f7d4d12b1d27e62f86254e6cced5ff9a": {
            "balance": "100",
            "nonce": 0,
            "root": "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
            "codeHash": "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
            "code": "",
            "storage": {}
        },
        "77de172a492c40217e48ebb7eeff9b2d7df8151b": {
            "balance": "888",
            "nonce": 0,
            "root": "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
            "codeHash": "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
            "code": "",
            "storage": {}
        },
        "80580f576731dc1e1dcc53d80b261e228c447cdd": {
            "balance": "0",
            "nonce": 1,
            "root": "1f6d937817f2ac217d8b123c4983c45141e50bd0c358c07f3c19c7b526dd4267",
            "codeHash": "c668dac8131a99c411450ba912234439ace20d1cc1084f8e198fee0a334bc592",
            "code": "636f6e747261637420636f6465206279746573",
            "storage": {
                "000000000000000000000000000000000000000000000000000000006e616d65": "8479737169",
                "0000000000000000000000000000000000000000000000000000006f776e6572": "940bb141c2f7d4d12b1d27e62f86254e6cced5ff9a"
            }
        }
    }
}
```

我们看到这些显示数据，直接对应我们刚刚的所有操作。
也只有合约账户才有 `storage` 和 `code`。而外部账户的`codeHash`和`root`值相同，是一个默认值。