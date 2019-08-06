# go-ethereum-code-analysis
本文结合了一些网上资料，加上个人的原创结合而成。个人认为解释的比较清晰。若有疑问，还请及时批评指出。

## 目录

- [go-ethereum代码阅读环境搭建](/go-ethereum源码阅读环境搭建.md)
- [以太坊黄皮书 符号索引](a黄皮书里面出现的所有的符号索引.md)
- [account文件解析](/accounts源码分析.md)
- build文件解析： 此文件主要用于编译安装使用
- [cmd文件解析](/cmd.md)
- [consensus文件解析](/consensus.md)
- [rlp源码解析](/rlp源码解析.md)
- [trie源码分析](/trie源码分析.md)
- [ethdb源码分析](/ethdb源码分析.md)
- [rpc源码分析](/rpc源码分析.md)
- [p2p源码分析](/p2p源码分析.md)
- [eth协议源码分析](/eth源码分析.md)
- core文件源码分析
	- [types文件解析](/types.md)
	- [core/genesis.go](/core-genesis创世区块源码分析.md)
	- [core/blockchain.go](/core-blockchain源码分析.md)
	- [区块链索引 chain_indexer源码分析](/core-chain_indexer源码解析.md)
	- [布隆过滤器索引 bloombits源码分析](/core-bloombits源码分析.md)
	- [以太坊的trie树管理 回滚等操作 state源码分析](/core-state源码分析.md)
	- [交易执行和处理部分源码分析](/core-state-process源码分析.md)
	- vm 虚拟机源码分析
		- [虚拟机堆栈和内存数据结构分析](/core-vm-stack-memory源码分析.md)
		- [虚拟机指令,跳转表,解释器源码分析](/core-vm-jumptable-instruction.md)
		- [虚拟机源码分析](/core-vm源码分析.md)
	- 待确认交易池的管理txPool
		- [交易执行和处理部分源码分析](/core-txlist交易池的一些数据结构源码分析.md)
		- [交易执行和处理部分源码分析](/core-txpool交易池源码分析.md)
	- [创世区块的源码分析](/core-genesis创世区块源码分析.md)
- [miner挖矿部分源码分析CPU挖矿](/miner挖矿部分源码分析CPU挖矿.md)
- [pow一致性算法](/pow一致性算法.md)
- [以太坊测试网络Clique_PoA介绍](/以太坊测试网络Clique_PoA介绍.md)


