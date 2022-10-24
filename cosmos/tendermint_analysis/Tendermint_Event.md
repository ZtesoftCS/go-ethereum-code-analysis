# Tendermint Event

## Event 概述

>EventBus是系统中所有事件的公共总线。所有调用都代理到底层pubsub服务器。所有事件都必须使用
>EventBus来发布，来确保正确的数据类型
```plain
type EventBus struct {
   service.BaseService
   pubsub *tmpubsub.Server // Server 允许 client 订阅/取消订阅消息，带或不带 tag 发布消息，并管理内部状态
}
eventBus, err := createAndStartEventBus(logger)
```

## EventBus 创建订阅

EventBus结构体同样存在匿名字段BaseService，那么也实现了BaseService的所有接口。pubsub来自 libs/pubsub/pubsub.go文件。pubsub的`Server`结构体同样实现了BaseService的所有接口。 NewNode方法中创建代码。

```go
eventBus := types.NewEventBus()
eventBus.SetLogger(logger.With("module", "events"))

// 交易索引 使用levelDB存储索引和搜索交易的内容, 配置默认索引所有标签（预定义标签："tx.hash", "tx.height" 以及DeliverTx响应中的所有键
indexerService, txIndexer, err := createAndStartIndexerService(config, dbProvider, eventBus, logger)
// 索引器服务将事件总线和事务索引器连接在一起，以便对来自事件总线的事务进行索引
indexerService := txindex.NewIndexerService(txIndexer, eventBus)
type IndexerService struct {
	service.BaseService

	idr      TxIndexer			// tx事务索引
	eventBus *types.EventBus // 事件总线
}
TxIndexer接口定义了一组索引和查找的接口。
IndexerService 会把 TxIndexer 和 EventBus 连接在一起，以对来自 EventBus 的交易进行索引。

```

之后会调用 `IndexerService` 的 `OnStart` 方法。

>使用SubscribeUnbuffered以确保两个订阅都不能由于提取消息的速度不够快而取消。因为这可能有时在没有其他订阅者的情况下发生

```go
// 区块头订阅
blockHeadersSub, err := is.eventBus.SubscribeUnbuffered(
   context.Background(),
   subscriber,
   types.EventQueryNewBlockHeader)

// 交易tx订阅
txsSub, err := is.eventBus.SubscribeUnbuffered(context.Background(), subscriber, types.EventQueryTx)
```

订阅了之后会启动一个goroutinue循环读取从两种订阅通道获取数据。

所有支持的事件类型

```go
var (
	EventQueryCompleteProposal    = QueryForEvent(EventCompleteProposal)
	EventQueryLock                = QueryForEvent(EventLock)
	EventQueryNewBlock            = QueryForEvent(EventNewBlock)
	EventQueryNewBlockHeader      = QueryForEvent(EventNewBlockHeader)
	EventQueryNewRound            = QueryForEvent(EventNewRound)
	EventQueryNewRoundStep        = QueryForEvent(EventNewRoundStep)
	EventQueryPolka               = QueryForEvent(EventPolka)
	EventQueryRelock              = QueryForEvent(EventRelock)
	EventQueryTimeoutPropose      = QueryForEvent(EventTimeoutPropose)
	EventQueryTimeoutWait         = QueryForEvent(EventTimeoutWait)
	EventQueryTx                  = QueryForEvent(EventTx)
	EventQueryUnlock              = QueryForEvent(EventUnlock)
	EventQueryValidatorSetUpdates = QueryForEvent(EventValidatorSetUpdates)
	EventQueryValidBlock          = QueryForEvent(EventValidBlock)
	EventQueryVote                = QueryForEvent(EventVote)
)
```

