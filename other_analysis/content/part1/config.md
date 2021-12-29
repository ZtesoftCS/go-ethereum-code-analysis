---
title: "以太坊基础配置"
menuTitle: "配置"
weight: 100001
---

以太坊的基础配置用于服务于链，启动以太坊节点，则需要将链配置载入。
因此，在以太坊中内置了主网(mainnet)、测试网(testnet)、Rinkeby、Goerli网络中链配置。

初始启动节点时，将根据不同的参数（--dev、--testnet）来默认加载不同链配置。

## 链配置

不同于传统软件，因为区块链的不可篡改性，要求对同一个区块，不管出块时的软件版本，还是10年后的软件版本。都需要保证软件对已出块区块做出相同操作。因此区块链的链配置，不得随意更改，还需要维护重要历史变更内容。


下面是链的核心配置信息，定义在 params/config.go 中：

```go
type ChainConfig struct {
	ChainID *big.Int  
	HomesteadBlock *big.Int 
	DAOForkBlock   *big.Int  
	DAOForkSupport bool   

	// EIP150 implements the Gas price changes (https://github.com/ethereum/EIPs/issues/150)
	EIP150Block *big.Int     
	EIP150Hash  common.Hash 

	EIP155Block *big.Int  
	EIP158Block *big.Int  

	ByzantiumBlock      *big.Int  
	ConstantinopleBlock *big.Int  
	PetersburgBlock     *big.Int  
	EWASMBlock          *big.Int  

	// Various consensus engines
	Ethash *EthashConfig  
	Clique *CliqueConfig
}
```

区块链的不可篡改性，非中心化程序使得区块链网络程序升级复杂化。从链核心配置，可折射一个区块链网络所经历的关键时刻。 

如上的以太坊链配置，并非程序期初编写，而是随以太坊发展，在共识协议重大变更时积累而成。 下面是各项配置的作用说明：

### ChainID

链标识符，是在[EIP155](http://eips.ethereum.org/EIPS/eip-155)改进方案中实现，用于防止重放攻击。

重放攻击是在以太坊第一次硬分叉（以太经典）时，引入的Bug。
导致一笔交易，在两条链上同样有效，造成双花。

当前以太坊生态中不同网络环境下的链网络信息[^1]:

|Chain ID|Name|Short Name|Chain|Network|Network ID|
|--- |--- |--- |--- |--- |--- |
|1|Ethereum Mainnet|eth|ETH|mainnet|1|
|2|Expanse Network|exp|EXP|mainnet|1|
|3|Ethereum Testnet Ropsten|rop|ETH|ropsten|3|
|4|Ethereum Testnet Rinkeby|rin|ETH|rinkeby|4|
|5|Ethereum Testnet Görli|gor|ETH|goerli|5|
|6|Ethereum Classic Testnet Kotti|kot|ETC|kotti|6|
|8|Ubiq Network Mainnet|ubq|UBQ|mainnet|1|
|9|Ubiq Network Testnet|tubq|UBQ|mainnet|2|
|28|Ethereum Social|etsc|ETSC|mainnet|1|
|30|RSK Mainnet|rsk|RSK|mainnet|775|
|31|RSK Testnet|trsk|RSK|testnet|8052|
|42|Ethereum Testnet Kovan|kov|ETH|kovan|42|
|60|GoChain|go|GO|mainnet|60|
|61|Ethereum Classic Mainnet|etc|ETC|mainnet|1|
|62|Ethereum Classic Testnet|tetc|ETC|testnet|2|
|64|Ellaism|ella|ELLA|mainnet|1|
|76|Mix|mix|MIX|mainnet|1|
|77|POA Network Sokol|poa|POA|sokol|1|
|88|TomoChain|tomo|TOMO|mainnet|88|
|99|POA Network Core|skl|POA|core|2|
|100|xDAI Chain|xdai|XDAI|mainnet|1|
|101|Webchain|web|WEB|mainnet|37129|
|101|EtherInc|eti|ETI|mainnet|1|
|820|Callisto Mainnet|clo|CLO|mainnet|1|
|821|Callisto Testnet|tclo|CLO|testnet|2|
|1620|Atheios|ath|ATH|mainnet|11235813|
|1856|Teslafunds|tsf|TSF|mainnet|1|
|1987|EtherGem|egem|EGEM|mainnet|1987|
|2018|EOS Classic|eosc|EOSC|mainnet|1|
|24484|Webchain (after block xxxxxxx)|web|WEB|mainnet|37129|
|31102|Ethersocial Network|esn|ESN|mainnet|1|
|200625|Akaroma|aka|AKA|mainnet|200625|
|246529|ARTIS sigma1|ats|ARTIS|sigma1|246529|
|246785|ARTIS tau1|ats|ARTIS|tau1|246785|
|1313114|Ether-1|etho|ETHO|mainnet|1313114|
|7762959|Musicoin|music|MUSIC|mainnet|7762959|
|18289463|IOLite|ilt|ILT|mainnet|18289463|
|3125659152|Pirl|pirl|PIRL|mainnet|3125659152|
|385|Lisinski|lisinski|CRO|mainnet|385|
|108|ThunderCore Mainnet|TT|TT|mainnet|108|
|18|ThunderCore Testnet|TST|TST|testnet|18|
|11|Metadium Mainnet|meta|META|mainnet|11|
|12|Metadium Testnet|kal|META|testnet|12|
|13371337|PepChain Churchill|tpep|PEP|testnet|13371337|



### HomesteadBlock

以太坊 homestead 版本硬分叉高度。
意味着从此高度开始，新区块受 homested 版本共识规则约束。
因涉及共识变更，如果希望继续接受新区块则必须升级以太坊程序，属于区块链硬分叉。
如果不愿意接受共识变更，则可以独立使用新的 ChainID 继续原共识，且必须独立维护版本。

### DAOForkBlock和DAOForkSupport

以太坊应对[The DAO 攻击]({{< ref "dao.md" >}})所实施的软件软分叉。
在程序代码中嵌入关于 The DAO 账户控制代码，来锁定资产转移。

这是以太坊首个ICO筹集资金达 1.5 亿美元的众筹项目，占有近以太坊总币 15%。
攻击的影响关乎以太坊生死，以太坊基金会介入并组织社区投票决定，是否愿意通过修改程序来干预这个 ICO 智能合约，以避免资金流向黑客。

最终因为社区的不同意见，利益与信念的交融，在 1920000 高度进行硬分叉。
分叉出以太坊和以太经典。  

### EIP150Block与EIP150Hash

[EIP150](http://eips.ethereum.org/EIPS/eip-150) 提案生效高度。
该提案是为解决拒绝服务攻击，而通过提高 IO 操作相关的 Gas 来预防攻击。

主要注意的是Go语言版并非以太坊的第一个实现版本，属于新语言重写。
此部分代码是在2016年11月21日提交的[#a8ca75](https://github.com/ethereum/go-ethereum/commit/a8ca75738a45a137ff7b2dfa276398fad26439da)中实现。
而EIP150激活的区块高度是 [2463000](https://etherscan.io/block/2463000)，在2016年10月18日出块。

因此，在配置中特别写入了 EIP150 激活区块 2463000 的哈希值。

###  ByzantiumBlock

2017年10月16日，以太坊从第4370000号区块起顺利完成了代号为Byzantium的硬分叉。
Byzantium是Metropolis升级计划中的第一步，为之后的Constantinople硬分叉做好了铺垫。
 

### ConstantinopleBlock

以太坊君士坦丁堡版本启用区块高度，主网在2019年3月1日成功出块。
Constantinople (君士坦丁堡) 包含一大波以太坊改进提案（EIP），
涉及核心协议规范、客户端 API以及合约标准。下列 EIP 为君士坦丁堡升级中包含的更新：

+ [EIP 145 -EVM 中的按位移动（bitwise shifting）指令](https://eips.ethereum.org/EIPS/eip-145)：
提供与其它算术运算代价相当的原生按位移动指令。
EVM 现在是没有按位移动指令的，但支持其他逻辑和算术运算。
按位移动可以通过算术操作来实现，但这样会有更高的 Gas 消耗，也需要更多时间来处理。
使用算术操作，实现 SHL 和 SHR 需要耗费 35 Gas，但这一提案提供的原生指令只需消耗 3 Gas。
一句话总结：该 EIP 为协议加入了一个原生的功能，使得 EVM 中的按位移动操作更便宜也更简单。

+ [EIP 1014-Skinny CREATE2](https://eips.ethereum.org/EIPS/eip-1014)：
加入新的操作码 0xf5 ，需要 4 个堆栈参数（stack argument）： endowment 、 memory_start 、 memory_length 、 salt 。具体表现与 CREATE 相同，但使用 keccak256( 0xff ++ sender_address ++ salt ++ keccak256(init_code)))[12:] ，而不是 keccak256(RLP(sender_address, nonce))[12:] ，作为合约初始化的地址。
拓宽我们的交互范围：有些合约在链上还不存在，但可以确定只可能包含由 init_code 特定部分创建出来的代码，有了该 EIP 之后我们就可以和这样的合约交互。
对包含与合约的 conterfactual 交互的状态通道来说非常重要。
一句话总结：这一 EIP 让你可以与还没有被创建出来的合约交互。

+ [EIP 1052 EXTCODEHASH 操作码](https://eips.ethereum.org/EIPS/eip-1052)：
指定了一个新的操作码，可以返回某合约代码的 keccak256 哈希值。
许多合约都需要检查某一合约的字节码，但并不需要那些字节码本身。比如，某个合约可能想检查另一合约的字节码是不是一组可行的实现之一；又或者它想分析另一合约的代码，把所有能通过分析的合约（即字节码匹配的合约）添加进白名单。
合约现在可以使用 EXTCODECOPY 操作码，但在那些只需要哈希值的情境下，这一操作码相对来说是比较贵的，尤其是对那些大型合约而言。新的操作码EXTCODEHASH 部署之后，就可以只返回某一合约字节码的 keccak256 哈希值。
一句话总结：该 EIP 会让相关操作变得更便宜（消耗更少的 Gas）。

+ [EIP 1283 改变 SSTORE 操作码所用 Gas 的计算方式](https://eips.ethereum.org/EIPS/eip-1283)：
改变 SSTORE 操作码的净 Gas 计量方式，以启用合约存储的新用法，并在计算方式与当前大多数实现不匹配的情形下减少无谓的 Gas 消耗。
一句话总结：该 EIP 会让某些操作变得更便宜（只需更少的 Gas 即可完成操作），减少那些当前“多余”而昂贵的 Gas 消耗。

+ [EIP 1234-推迟难度炸弹爆炸的时间并调整区块奖励](https://eips.ethereum.org/EIPS/eip-1234):
平均出块时间会因为逐渐加速的难度炸弹（也叫做“冰河时期”）而不断上升。该 EIP 提议推迟难度炸弹约 12 个月，并且（为适应冰河期推迟）而减少区块奖励。
一句话总结：该 EIP 保证了我们不会在 PoS 准备好并实现之前使以太坊停止出块。

### PetersburgBlock

以太坊彼得斯堡版本启用区块高度。
因为以太坊改进提案 [EIP1283](https://eips.ethereum.org/EIPS/eip-1283) 可能会为攻击者提供窃取用户资金的代码漏洞。
为避免这种情况发生，团队决定在同一区块进行两个硬分叉（君士坦丁堡和彼得斯堡）。

该分叉将禁用已发现的缺陷协议。

### EWASMBlock

尚未实现的功能，以太坊将支持 wasm 指令，意味着可以使用 WebAssembly 编写智能合约。
