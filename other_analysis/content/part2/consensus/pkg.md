---
title: "共识代码结构介绍"
menuTitle: "代码结构"
date: 2019-08-18T10:11:47+08:00
weight: 20301
description: "详解以太坊共识包源代码组织结构"
---

在以太坊 geth 项目中共识类代码均组织在`github.com/ethereum/go-ethereum/consensus`包中。
这篇小文，给你介绍下代码结构，为后续讲解共识算法实现做准备。

下面是整个包内子包组织和文件定义。

```js
consensus -> 共识算法包
├── clique -> PoA 算法
│   ├── api.go
│   ├── clique.go  -> 共识算法实现
│   ├── snapshot.go
│   └── snapshot_test.go
├── consensus.go -> 算法接口
├── errors.go -> 全局错误信息定义
├── ethash  ->  PoW 算法
│   ├── algorithm.go ->  ethash算法核心
│   ├── algorithm_test.go
│   ├── api.go
│   ├── consensus.go -> 共识算法实现
│   ├── consensus_test.go
│   ├── ethash.go  ->  ethash 算法入口
│   ├── ethash_test.go
│   ├── sealer.go  ->  挖矿入口
│   └── sealer_test.go
└── misc  -> 公共算法
    ├── dao.go ->  The dao 攻击，硬分叉处理
    └── forks.go
```

consensus 包下有两个共识算法包 ethash 和 clique，分别实现了定义在 consensus.go 文件中共识算法接口 Engin。

![以太坊共识算法接口](https://img.learnblockchain.cn/book_geth/2019-8-18-10-55-32.png!de)

接口方法分为两类：

1. 区块校验：
    + VerifyHeader： 校验单个区块头
    + VerifyHeaders：批量校验多个区块头
    + VerifyUncles： 批量校验多个叔块
    + VerifySeal：   校验区块头是否符合共识算法要求
2. 挖矿挖矿所用：
    + Prepare:     挖矿前准备信号，如设置区块难度。
    + Finalize:    新区块打包完成信号，如添加区块奖励。
    + Seal:  开始挖矿
    + SealHash： 用于挖矿计算时的数据哈希
    + CalcDifficulty： 计算挖矿难度
    + APIs： 共识算法可提供的对外API
    + Close： 通知共识关闭挖矿

根据接口定义，在共识算法包内部进行实现，当前以太坊中有两个算法：PoW版的Ethash和PoA版的clique。PoA相对简单些，而PoW则主要涉及难度调整，抗ASIC等。

区块校验和挖矿算法相对应，了解挖矿细节，则自然可以了解是如何进行区块校验的。
所以本章重点介绍共识算法细节，将忽略区块校验。
