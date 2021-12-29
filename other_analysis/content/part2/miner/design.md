---
title: "以太坊挖矿架构设计"
menuTitle: "架构"
date: 2019-07-31T22:58:46+08:00
draft: false
weight: 20301
---

以太坊 geth 项目中，关于挖矿逻辑，全部在 miner 包中，仅用3个文件便清晰滴定义挖矿逻辑。上一篇文章中，可以看到挖矿的主要环节也就几个。但是如何协商每个环节的处理，却在于架构设计。本文我先同大家讲解以太坊关于挖矿的架构设计。

![以太坊Miner设计结构](https://img.learnblockchain.cn/book_geth/image-20190721223605124.png!de)

上图是以太坊 Miner 包中关于挖矿的核心结构。对外部仅仅开放了 Miner 对象，任何对挖矿的操作均通过 Miner 对象操作。而实际挖矿细节全部在 worker 实例中实现，同时将关键核心数据存储在 environment 中。

外部只需通过调用 Start、Stop 即可完成启动和停止挖矿。当然也可修改一些挖矿参数，如区块头中的可自定义数据 Extra，以及随时调用  SetEtherebase 修改矿工地址 coinbase。

这个的核心全部在 worker 中，worker 是一个工作管理器。订阅了 blockchain 的三个事件，分别监听新区块事件 chainHeadeCh，新分叉链事件 chainSideCh和新交易事件txCh。以及定义了内部一系列的信号，如 newWork 信号、task信号等。根据信号，执行不同的工作，在各种信号综合作用下协同作业。

在创建worker 时，将在 worker 内开启四个 goroutine 来分别监听不同信号。

 ![以太坊Miner下监听信号](https://img.learnblockchain.cn/book_geth/image-20190721235307204.png!de)

首先是 mainLoop ，将监听 newWork 、tx、chainSide 信号。newWork 表示将开始挖采下一个新区块。

这个信号在需要重新挖矿时发出，而此信号来自于 newWorkLoop 。当收到newWork信号，矿工将立刻将当前区块作为父区块，来挖下一个区块。

当收到来自交易池的tx信号时，如果已经是挖矿中，则可以忽略这些交易。因为交易一样会被矿工从交易池主动拿取。如果尚未开始挖矿，则有机会将交易暂时提交，并更新到state中。

同样，当 blockchain 发送变化（新区块）时，而自己当下的挖掘块中仅有极少的叔块，此时允许不再处理交易，而是直接将此叔块加入，立刻提交当前挖掘块。

newWorkLoop 负责根据不同情况来抉择是否需要终止当前工作，或者开始新一个区块挖掘。有以下几种情况将会终止当前工作，开始新区块挖掘。

1. 接收到 start 信号，表示需要开始挖矿。
2. 接收到 chainHeadCh 新区块信号，表示已经有新区块出现。你所处理的交易或者区块高度都极有可能重复，需要终止当下工作，立即开始新一轮挖矿。
3. timer计时器，默认每三秒检查一次是否有新交易需要处理。如果有则需要重新开始挖矿。以便将加高的交易优先打包到区块中。

在 newWorkLoop 中还有一个辅助信号，resubmitAdjustCh 和 resubmitIntervalCh。运行外部修改timer计时器的时钟。resubmitAdjustCh是根据历史情况重新计算一个合理的间隔时间。而resubmitIntervalCh则允许外部，实时通过 Miner 实例方法 SetRecommitInterval 修改间隔时间。

上面是在控制何时挖矿，而 taskLoop 和resultLoop则不同。 taskLoop 是在监听任务。任务是指包含了新区块内容的任务，表示可以将此新区块进行PoW计算。一旦接受到新任务，则立即将此任务进行PoW工作量计算，寻找符合要求的Nonce。一旦计算完成，把任务和计算结果作为一项结果数据告知 resultLoop 。由resultLoop 完成区块的最后工作，即将计算结构和区块基本数据组合成一个符合共识算法的区块。完成区块最后的数据存储和网络广播。

同时，在挖矿时将当下的挖矿工作的过程信息记录在 environment 中，打包区块时只需要从当前的environment中获取实时数据，或者快照数据。

采用goroutine下使用 channel 作为信号，以太坊 miner 完成一个激活挖矿到最终挖矿成功的整个逻辑。上面的讲解不涉及细节，只是让大家对挖矿有一个整体了解。为后续的各环节详解做准备。





