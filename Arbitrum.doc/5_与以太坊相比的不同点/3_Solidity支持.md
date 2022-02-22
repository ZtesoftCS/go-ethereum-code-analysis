# 3_Solidity支持


Arbitrum Rollup支持EVM交易，你可以免信任地在Arbitrum上部署Solidty合约（以及其他会编译为EVM的语言如Vyper）。Arbitrum还支持几乎所有的Solidty代码，除了下面所说的几点小不同。

## 与以太坊上solidty的不同
虽然Arbitrum支持Solidty代码，但一些操作仍有不同，其中包括一些在L2上没太大意义的操作。

* `tx.gasprice`返回用户的ArbGas出价价格
* `blockhash(x)`返回Arbitrum的区块哈希，该值由收件箱确定性地生成。注意，Arbitrum的区块哈希并不取决于L1区块哈希，因此不应认为有任何经济安全性（例如，一个随机数种子）
* `block.coinbase`返回0
* `block.difficulty`返回常量2500000000000000
* `block.gaslimit`返回区块的ArbGas limit
* `gasleft`返回剩余的ArbGas
* `block.number`在非序列器的Arbitrum链上，返回提交至收件箱时的L1区块编号；在序列器Arbitrum链上，返回该序列器接收到该交易时估算的L1区块编号（见[Arbitrum中的时间](4_区块编号和时间.md)）。
## 时间
Arbitrum支持`block.number`和`block.timestamp`。对于这些术语在Arbitrum语境下的意义，见[Arbitrum中的时间](4_区块编号和时间.md)。

← [2_特殊特性](2_特殊特性.md)
→ [4_区块编号和时间](4_区块编号和时间.md)