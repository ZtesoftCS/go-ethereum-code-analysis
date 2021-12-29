---
title: "以太坊创世区块"
menuTitle: "创世块"
weight: 100002
---

创世区块作为第零个区块，其他区块直接或间接引用到创世区块。
因此节点启动之初必须载入正确的创世区块信息，且不得任意修改。

以太坊允许通过创世配置文件来初始化创世区块，也可使用选择使用内置的多个网络环境的创世配置。
默认使用以太坊主网创世配置。

## 创世配置文件

如果你需要搭建以太坊私有链，那么了解创世配置是必须的，否则你大可不关心创世配置。
下面是一份 JSON 格式的创世配置示例：

```json
{
    "config": {
        "chainId": 1,
        "homesteadBlock": 1150000,
        "daoForkBlock": 1920000,
        "daoForkSupport": true,
        "eip150Block": 2463000,
        "eip150Hash": "0x2086799aeebeae135c246c65021c82b4e15a2c451340993aacfd2751886514f0",
        "eip155Block": 2675000,
        "eip158Block": 2675000,
        "byzantiumBlock": 4370000,
        "constantinopleBlock": 7280000,
        "petersburgBlock": 7280000,
        "ethash": {}
    },
    "nonce": "0x42",
    "timestamp": "0x0",
    "extraData": "0x11bbe8db4e347b4e8c937c1c8370e4b5ed33adb3db69cbdb7a38e1e50b1b82fa",
    "gasLimit": "0x1388",
    "difficulty": "0x400000000",
    "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "coinbase": "0x0000000000000000000000000000000000000000",
    "number": "0x0",
    "gasUsed": "0x0",
    "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "alloc": {
        "000d836201318ec6899a67540690382780743280": {
            "balance": "0xad78ebc5ac6200000"
        },
        "001762430ea9c3a26e5749afdb70da5f78ddbb8c": {
            "balance": "0xad78ebc5ac6200000"
        }
    }
}
```

根据配置用途可分为三大类：

1. 链配置
<br>`config`项是定义链配置，会影响共识协议，虽然链配置对创世影响不大，但新区块的出块规则均依赖链配置。
关于链配置更多细节，请查看文章《[链参数配置]({{< ref "./config.md" >}})》。
2. 创世区块头信息配置  
    + `nonce`：随机数，对应创世区块 `Nonce` 字段。
    + `timestamp`：UTC时间戳，对应创世区块 `Time`字段。
    + `extraData`：额外数据，对应创世区块 `Extra` 字段。
    + `gasLimit`：**必填**，燃料上限，对应创世区块 `GasLimit` 字段。
    + `difficulty`：**必填**，难度系数，对应创世区块 `Difficulty` 字段。搭建私有链时，需要根据情况选择合适的难度值，以便调整出块。
    + `mixHash`：一个哈希值，对应创世区块的`MixDigest`字段。和 nonce 值一起证明在区块上已经进行了足够的计算。
    + `coinbase`：一个地址，对应创世区块的`Coinbase`字段。
3. 初始账户资产配置
<br>`alloc` 项是创世中初始账户资产配置。在生成创世区块时，将此数据集中的账户资产写入区块中，相当于预挖矿。
这对开发测试和私有链非常好用，不需要挖矿就可以直接为任意多个账户分配资产。

### 自定义创世

如果你计划部署以太坊私有网络或者一个独立的测试环境，那么需要自定义创世，并初始化它。为了统一沟通，推荐先在用户根目录创建一个文件夹 `deepeth`，以做为《以太坊设计与实现》电子书学习工作目录。

```bash
mkdir $HOME/deepeth && cd $HOME/deepeth
```
再准备两个以太坊账户，以便在创世时存入资产。

```bash
dgeth --datadir $HOME/deepeth account new
```

>**注意**：命令中的 `dgeth` 是 `geth` 程序的重命名，下同。
>具体见文章《[开篇]({{< ref "first.md" >}})》。

因为是学习使用，推荐使用统一密码 `foobar`，
执行两次命令，创建好两个账户。
这里使用 `--datadir` 参数指定以太坊运行时数据存放目录，是让大家将数据统一存放在一个本课程学习文件夹中。

再将下面配置内容保存到 `$HOME/deepeth/genesis.json` 文件，其中 `alloc` 项替换成刚刚创建的两个以太坊账户地址。

```json
{
    "config": {
        "chainId": 8888,
        "homesteadBlock": 0,
        "daoForkBlock": 0,
        "daoForkSupport": true,
        "eip150Block": 0,
        "eip155Block": 0,
        "eip158Block": 0,
        "byzantiumBlock": 0,
        "constantinopleBlock": 0,
        "petersburgBlock": 0,
        "ethash": {}
    },
    "nonce": "0x42",
    "timestamp": "0x0",
    "extraData": "0x11bbe8db4e347b4e8c937c1c8370e4b5ed33adb3db69cbdb7a38e1e50b1b82fa",
    "gasLimit": "0x1388",
    "difficulty": "0x1",
    "alloc": {
        "093f59f1d91017d30d8c2caa78feb5beb0d2cfaf": {
            "balance": "0xffffffffffffffff"
        },
        "ddf7202cbe0aaed1c2d5c4ef05e386501a054406": {
            "balance": "0xffffffffffffffff"
        }
    }
}
```

然后，执行 geth 子命令 init 初始化创世区块。

```bash
dgeth  --datadir $HOME/deepeth init genesis.json
```

执行成功后，便可启动该私有链：

```bash
dgeth --maxpeers 0 --datadir $HOME/deepeth  console
```

执行如下命令，可以查看到前面创建的两个账户，均已有资产：

```js
eth.getBalance(eth.accounts[0])
// 18446744073709551615
eth.getBalance(eth.accounts[1])
// 18446744073709551615
```

至此，我们已完成创世定制版。


### 内置的创世配置

上面我已完成自定义创世，但以太坊作为去中心平台，需要许多节点一起参与。
仅仅为了测试，多个节点来搭建私有链比较麻烦。
如果希望和别人一起联调，或者需要在测试网络中测试DAPP时，该怎么办呢？
那么，可使用以太坊测试网络。以太坊公开的测试网络有 5 个，目前仍在运行的有 4 个，具体见下表格。

|测试网|共识机制|出块间隔|提供方|上线时间|备注|状态|
|---|---|---|---|---|---|---|
| Morden | PoW || 以太坊官方 |2015.7|因难度炸弹被迫退役 |stopped|
|[Ropsten](https://ropsten.etherscan.io) |PoW |30秒|以太坊官方|2016.11|接替Morden| running|
|[Kovan](https://kovan.etherscan.io/) | PoA | 4秒|以太坊钱包<br>Parity开发团队| 2017.3 |不支持geth| running |
|[Rinkeby](https://rinkeby.etherscan.io/) | PoA |15秒| 以太坊官方| 2017.4|最常用，只支持geth | running|
|[Sokol](https://sokol-explorer.poa.network/) | PoA |5秒| 以太坊官方POA.network团队| 2017.12|不支持geth | running|
|[Görli](https://goerli.net/) | PoA | 15秒| 以太坊柏林社区 | 2018.9| 首个以太坊2.0实验场| running|

支持 geth 的3个测试网络的创世配置已内置在以太坊代码中，具体见 `core/genesis.go` 文件：

```go
// DefaultTestnetGenesisBlock returns the Ropsten network genesis block.
func DefaultTestnetGenesisBlock() *Genesis{}
// DefaultRinkebyGenesisBlock returns the Rinkeby network genesis block.
func DefaultRinkebyGenesisBlock() *Genesis
// DefaultGoerliGenesisBlock returns the Görli network genesis block.
func DefaultGoerliGenesisBlock() *Genesis{}
```

当然不会缺以太坊主网创世配置，也是 geth 运行的默认配置。

```go
// DefaultGenesisBlock returns the Ethereum main net genesis block.
func DefaultGenesisBlock() *Genesis{}
```

如果你不想自定义创世配置文件用于开发测试，那么以太坊也提供一份专用于本地开发的配置。

```go

// DeveloperGenesisBlock returns the 'geth --dev' genesis block. Note, this must
// be seeded with the
func DeveloperGenesisBlock(period uint64, faucet common.Address) *Genesis
```

运行 `dgeth --dev console` 可临时运行使用。但如果需要长期使用此模式，则需要指定 `datadir`。

```bash
dgeth --dev --datadir $HOME/deepeth/dev console
```

首次运行 dev 模式会自动创建一个空密码的账户，并开启挖矿。
当有新交易时，将立刻打包出块。




## geth 创世区块加载流程

在运行 geth 时需根据配置文件加载创世配置以及创世区块，并校验其合法性。
如果配置信息随意变更，易引起共识校验不通过等问题。
只有在加载并检查通过时，才能继续运行程序。

![创世加载流程](https://img.learnblockchain.cn/2019/04/07_20190407101509.png!de?width=400px)

上图是一个简要流程，下面分别讲解“加载创世配置”和“安装创世区块”两个子流程。

### 加载创世配置

应使用哪种创世配置，由用户在启动 geth 时决定。下图是创世配置选择流程图：
![以太坊创世配置选择流程图](https://img.learnblockchain.cn/2019/04/07_WX20190407-103229@2x.png!de)
通过 geth 命令参数可选择不同网络配置，可以通过 `networkid` 选择，也可使用网络名称启用。

1. 使用 networkid:

    不同网络使用不同ID标识。
    + 1=Frontier，主网环境，是默认选项。
    + 2=Morden 测试网络，但已禁用。
    + 3=Ropsten 测试网络。
    + 4=Rinkeby 测试网络。

2. 直接使用网络名称：
    + testnet: Ropsten 测试网络。
    + rinkeby: Rinkeby 测试网络。
    + goerli: Görli 测试网络。
    + dev: 本地开发环境。

geth 启动时根据不同参数选择加载不同网络配置，并对应不同网络环境。
如果不做任何选择，虽然在此不会做出选择，但在后面流程中会默认使用主网配置。

### 安装创世区块

上面已初步选择创世配置，而这一步则根据配置加载或者初始化创世单元。
下图是处理流程：

![安装创世区块](https://img.learnblockchain.cn/2019/04/07_安装创世区块.png!de)

首先，需要从数据库中根据区块高度 0 读取创世区块哈希。
如果不存在则说明本地属于第一次启动，直接使用运行时创世配置来构建创世区块。
属于首次，还需要存储创世区块和链配置。

如果存在，则需要使用运行时创世配置构建创世区块并和本次已存储的创世区块哈希进行对比。
一旦不一致，则返回错误，不得继续。

随后，还需要检查链配置。先从数据库获取链配置，如果不存在，则无需校验直接使用运行时链配置。
否则，需要检查运行时链配置是否正确，只有正确时才能替换更新。
但有一个例外：主网配置不得随意更改，由代码控制而非人为指定。

总的来说，以太坊默认使用主网配置，只有在首次运行时才创建和存储创世区块，其他时候仅仅用于校验。
而链配置除主网外则在规则下可随时变更。

## 构建创建区块

上面我们已知晓总体流程，这里再细说下以太坊是如何根据创世配置生成创世区块。
核心代码位于 `core/genesis.go:229`。

```go
func (g *Genesis) ToBlock(db ethdb.Database) *types.Block{
    if db == nil {
        db = rawdb.NewMemoryDatabase()
    }
    statedb, _ := state.New(common.Hash{}, state.NewDatabase(db))//❶
    for addr, account := range g.Alloc { //❷
        statedb.AddBalance(addr, account.Balance)
        statedb.SetCode(addr, account.Code)
        statedb.SetNonce(addr, account.Nonce)
        for key, value := range account.Storage {
            statedb.SetState(addr, key, value)
        }
    }
    root := statedb.IntermediateRoot(false)//❸
    head := &types.Header{//❹
        Number:     new(big.Int).SetUint64(g.Number),
        Nonce:      types.EncodeNonce(g.Nonce),
        Time:       g.Timestamp,
        ParentHash: g.ParentHash,
        Extra:      g.ExtraData,
        GasLimit:   g.GasLimit,
        GasUsed:    g.GasUsed,
        Difficulty: g.Difficulty,
        MixDigest:  g.Mixhash,
        Coinbase:   g.Coinbase,
        Root:       root,
    }
    //❺
    if g.GasLimit == 0 {
        head.GasLimit = params.GenesisGasLimit
    }
    if g.Difficulty == nil {
        head.Difficulty = params.GenesisDifficulty
    }

    statedb.Commit(false)//❻
    statedb.Database().TrieDB().Commit(root, true)//❼

    return types.NewBlock(head, nil, nil, nil)//❽
}
```

上面代码是根据创世配置生成创世区块的代码逻辑，细节如下：

+ ❶ 创世区块无父块，从零初始化全新的 `state`（后续文章会详细讲解 `state`对象）。
+ ❷ 遍历配置中 `Alloc` 项账户集合数据，直接写入 state 中。
    这里不单可以设置 `balance`，还可以设置 `code`、`nonce` 以及任意多个 `storage` 数据。
    意味着创世时便可以直接部署智能合约。例如下面配置则在创世时部署了一个名为`093f59f1d91017d30d8c2caa78feb5beb0d2cfaf` 的智能合约。

    ```json
    "alloc": {
            "093f59f1d91017d30d8c2caa78feb5beb0d2cfaf": {
                "balance": "0xffffffffffffffff",
                "nonce": "0x3",
                "code":"0x606060",
                "storage":{
                "11bbe8db4e347b4e8c937c1c8370e4b5ed33adb3db69cbdb7a38e1e50b1b82fa":"1234ff"
                }
            }
    }
    ```

+ ❸ 将账户数据写入 state 后，便可以计算出 state 数据的默克尔树的根值，称之为 `StateRoot`。
    此值记录在区块头 `Root` 字段中。
+ ❹ 创世配置的一部分配置，则直接映射到区块头中，完成创世区块头的构建。
+ ❺ 因为 `GasLimit` 和 `Difficulty` 直接影响到下一个区块出块处理。
    因此未设置时使用默认配置(Difficulty=131072，GasLimit=4712388)。
+ ❻ 提交 state，将 state 数据提交到底层的内存 trie 数据中。
+ ❼ 将内存 trie 数据更新到 db 中。
这是多余的一步，因为提交到数据库是由外部进行，这里只需要负责生成区块。
+ ❽ 利用区块头创建区块，且区块中无交易记录。
