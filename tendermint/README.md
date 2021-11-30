## Tendermint源码分析

## 缘由
最近工作时间稍微空闲一些, 本来是想写一些关于以太坊的源码分析，一来ethereum的实现过于复杂, 二来网上的资源也是比较丰富的。 有段时间在研究数据如何上链的问题是接触到了一个叫做[bigchaindb][1]的项目。 发现此项目是基于tendermint引擎的。 逐渐接触到了[tendermint][2]。 我想每一个区块链行业的从业者应该都有实现一条公链的想法。 tendermint正好满足了所有的功能。 不用去自己写P2P网络， 不用去实现复杂的共识算法， 不用研究如何对区块打包和存储。 只需要实现几个特定的接口就可以实现一个全新的链。

在基于tendermint实现了一个简(无)单(用)的公链之后， 愈发想研究一下tendermint的技术细节。 所以就有了现在这个源码分析的文章。目前已经通读和理解了大部分的代码， 我是按着模块来阅读的。目前已经看完了P2P, Mempool, Blockchain, State, Consensue。 很多模块的代码注释和文档都比较全面对于阅读源码非常有帮助。当然也有些模块注释很不明确需要自己琢磨许久才能明确其功能。我会逐渐将其落实为文档, 期望能给看到这篇文章的同学提供一些帮助。

## 分析计划

- [x] [P2P模块源码分析][3]
- [x] [Mempool模块源码分析][5]
- [x] [BlockCain模块源码分析][6]
- [x] [State模块源码分析][9]
- [ ] Consensus模块源码分析
    - [x] [pbft论文简述][121]
    - [x] [tendermint共识流程][122]
- [ ] Evidence模块源码分析
- [x] [Crypto加密包功能分析][7]
- [x] [Tendermint的启动流程分析][8]
- [x] [分析Tendermint的ABCI接口实现自己的区块链][11]
- [x] [移植以太坊虚拟机到Tendermint][10]
    - [x] [移植evm虚拟机之智能合约详解][101]
    - [x] [移植evm虚拟机之分析操作码][102]
    - [x] [移植evm虚拟机之源码分析][103]
    - [x] [移植evm虚拟机之实战][104]
    - [x] [移植evm虚拟机总结][105]

  [1]: https://github.com/bigchaindb/bigchaindb
  [2]: https://github.com/tendermint/tendermint
  [3]: p2p源码分析.md
  [4]: https://github.com/blockchainworkers/conch
  [5]: Mempool源码分析.md
  [6]: Blockchain源码分析.md
  [7]: crypto模块源码分析.md
  [8]: node启动流程分析.md
  [9]: state源码分析.md
  [10]: ./evm移植/index.md
  [11]: ./abci接口调用.md
  [12]: https://github.com/wupeaking/vechain_helper

  [101]: ./evm移植/evm之智能合约详解.md
  [102]: ./evm移植/evm之操作码分析.md
  [103]: ./evm移植/evm之源码分析.md
  [104]: ./evm移植/evm之实战.md
  [105]: ./evm移植/evm之总结.md

  [121]: ./epbft/pbft论文.md
  [122]: ./epbft/tendermint拜占庭共识算法.md
