eth的源码又下面几个包

- downloader 		主要用于和网络同步，包含了传统同步方式和快速同步方式
- fetcher			主要用于基于块通知的同步，接收到当我们接收到NewBlockHashesMsg消息得时候，我们只收到了很多Block的hash值。 需要通过hash值来同步区块。
- filter			提供基于RPC的过滤功能，包括实时数据的同步(PendingTx)，和历史的日志查询(Log filter)
- gasprice			提供gas的价格建议， 根据过去几个区块的gasprice，来得到当前的gasprice的建议价格


eth 协议部分源码分析

- [以太坊的网络协议大概流程](eth以太坊协议分析.md)

fetcher部分的源码分析

- [fetch部分源码分析](eth-fetcher源码分析.md)

downloader 部分源码分析
	
- [节点快速同步算法](以太坊fast%20sync算法.md)
- [用来提供下载任务的调度和结果组装 queue.go](eth-downloader-queue.go源码分析.md)
- [用来代表对端，提供QoS等功能 peer.go](eth-downloader-peer源码分析.md)
- [快速同步算法 用来提供Pivot point的 state-root的同步 statesync.go](eth-downloader-statesync.md)
- [同步的大致流程的分析 ](eth-downloader源码分析.md)

filter 部分源码分析

- [提供布隆过滤器的查询和RPC过滤功能](eth-bloombits和filter源码分析.md)
