# 官方脚手架scaffold

[https://github.com/cosmos/scaffold](https://github.com/cosmos/scaffold) 官方提供了快速开发应用和module的脚手架scaffold，根据文档安装后可以使用命令 scaffold 来按需生成标准的应用或者module的开发目录。

# module 常规目录结构

.

├── README.md

├── abci.go

├── alias.go

├── client

│   ├── cli

│   │   ├── query.go

│   │   └── tx.go

│   └── rest

│       ├── query.go

│       ├── rest.go

│       └── tx.go

├── genesis.go

├── go.mod

├── go.sum

├── handler.go

├── keeper

│   ├── keeper.go

│   ├── params.go

│   └── querier.go

├── module.go

├── spec

│   └── README.md

└── types

    ├── codec.go

    ├── errors.go

    ├── events.go

    ├── expected_keepers.go

    ├── genesis.go

    ├── key.go

    ├── msg.go

    ├── params.go

    └── querier.go

# module manager

1. module 需要实现AppModule 接口，应用启动的时候可以使用Module Manager来统一加载管理module.
1. 自定义module结构体要定义AppModuleBasic对象，是所有module都要实现的接口，包含的方法不依赖任何其他module。
2. AppModule 中定义了module内部和其他module交互的方法，主要是keeper中与存储交互的方法。
# keeper 结构解析

type Keeper struct {// 一个keeper的结构体定义例子

	CoinKeeper types.BankKeeper

	storeKey sdk.StoreKey // Unexposed key to access store from sdk.Context

	cdc *codec.Codec // The wire codec for binary encoding/decoding.

}

1. CoinKeeper 定义了使用到的其他module 的keeper类型，并且为了安全性 在types中仅仅定义了本module中需要的接口方法
1. storeKey可以理解为mysql的数据库名称，keeper中可以使用sdk.Context的KVStore 方法来通过storeKey获取本module的数据实例。
2. cdc 是与tendermint通信时的数据encodeing类型，在keeper中获取或者存储数据时需要使用cdc的对应方法进行转换
# module 数据CURD

1. module中最重要的目录是keeper 功能是数据的流转, 可以理解为数据库的CURD，通常keeper.go中包含大量的数据读取和存储
1. client 目录是客户端，其中涉及到了命令行和rest两种客户端与节点交互的方式，分别在对应的子目录cli和rest中
1. 其中查询数据对应各目录中的query.go文件，其中涉及查询msg的接收和输出，与节点node存储交互的逻辑在 keeper目录的querier.go 中，querier.go 文件可以理解为与数据库交互的dao层，NewQuerier 包含了能提供的所有查询服务
1. 数据插入和修改对应目录中的tx.go文件，其中的handler涉及查询msg的接收和输出，与节点node存储交互的逻辑在keeper目录的keeper.go中。
1. keeper目录的功能是与存储和其他模块交互，
# types 目录

1. 整体上定义了module相关的数据类型
2. expected_keepers.go 文件中定义了本module中调用其他module时被允许的接口，比如如果用到了转账操作那么就只需要在定义接口中添加 bank模块sendcoin 方法.
3. key.go 文件定义了一组module的常量如模块名称，store key , route key, querier router 等
4. errors.go 文件定义了keeper中使用到的错误状态的变量
5. queriers.go 文件定义了cli 和 reset查询中返回数据的类型结构
6. types.go 中定义了 本module中最核心的数据类型结构，就是module业务最重要的数据结构
7. codec.go 文件注册了本module handler中处理的msg 结构类型对应的codec name比如

**func **RegisterCodec(cdc *codec.Codec) {

   cdc.RegisterConcrete(MsgSend{}, **"cosmos-sdk/MsgSend"**, nil)

   cdc.RegisterConcrete(MsgMultiSend{}, **"cosmos-sdk/MsgMultiSend"**, nil)

}

a. 其中的 cosmos-sdk/MsgSend就是注册的codec的name，这个name在其他语言的cosmos交易签名库中会用到比如官方的js库 Sig, codec 编码是应用与tendermint沟通的编码方式，在其他模块中也存在。

b. 通常情况下如果module需要触发某些events 那么就要注册codec

     c. 模块定义的codec 会在应用new app的第一步  cdc := MakeCodec() 进行注册



# BeginBlocker 和 EndBlocker

1. 根据module需要来判断是否需要实现的方法
1. 用来处理节点在block开始和结束时候的发来的消息
1. 可以理解为路由中间件中的begin route 和 end route，根据本module需要自动做一些操作，其中实际处理逻辑在 abci.go文件对应的方法中， 并且可以在app.go中初始化app市使用SetOrderBeginBlocker/SetOrderEndBlocker 来设置各个module的beginblocker和endblocker的执行顺序。
2. 可以根据module需要来判断是否需要触发events , events相关的常量定义在 types/events.go文件中。
# Events

1. 主要在beginblocker和endblocker中触发
2. events管理结构体定义如下

type EventManager struct {

	events Events

}

3. 如果需要在Handler中触发events，那么需要在NewHandler的ctx中添加eventmanager

ctx = ctx.WithEventManager(sdk.NewEventManager())

1. events 可以通过tendermint的websocket接口订阅 [https://docs.tendermint.com/master/rpc/#/Websocket/subscribe](https://docs.tendermint.com/master/rpc/#/Websocket/subscribe)

