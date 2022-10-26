# Tendermint ABCI

## ABCI 介绍

ABCI 是一个应用和 Tendermint 沟通的接口，接口中定义了一些方法，其中每个方法都有相应的请求和响应消息类型，Tendermint 通过发送请求消息和接收响应消息来调用 ABCI 应用程序中的 ABCI 方法。所有的消息类型都定义在一个 `protobuf`文件中，这样任何语言写的应用都能和 Tendermint 交互。

_可以理解为基于 GRPC 协议的严格约束接口，这样不仅比 http rest api 有更高的性能，而且安全性要好_

## [ABCI 调用机制](https://www.1111down.com/59524.html)

### ABCI 应用服务端

以 `abci-cli kvstore` 运行过程分析

1. 添加全局 cmd flag `addGlobalFlags` 方法
    1. ` address`: ABCI 服务端监听地址, 默认为 `tcp://0.0.0.0:26658`
    2. ` flagAbci` : `abci-cli`客户端与 ABCI 服务端通信协议，默认 `socket`
    3. `flagLogLevel`: 日志等级，默认为 `debug`
2. 使用 `AddCommand` 添加应用命令`kvstore`和`counter` 和 `batchCmd consoleCmd echoCmd` 等客户端命令
3. cmd flag `persist` 是否持久化应用实例
4. 应用`kvstore`命令分析

```plain
func cmdKVStore(cmd *cobra.Command, args []string) error {
            // 创建日志对象
            logger := log.NewTMLogger(log.NewSyncWriter(os.Stdout))
            // 创建应用实例，并根据flag参数判断是否持久化应用实例
            var app types.Application
            if flagPersist == "" {
                app = kvstore.NewApplication()
            } else {
                app = kvstore.NewPersistentKVStoreApplication(flagPersist)
                app.(*kvstore.PersistentKVStoreApplication).SetLogger(logger.With("module", "kvstore"))
            }
            // 开启服务 socket
            srv, err := server.NewServer(flagAddress, flagAbci, app)
            if err != nil {
                return err
            }
            srv.SetLogger(logger.With("module", "abci-server"))
            if err := srv.Start(); err != nil {
                return err
            }
            // Stop upon receiving SIGTERM or CTRL-C.
            tmos.TrapSignal(logger, func() {
                // Cleanup
                srv.Stop()
            })
            // Run forever.
            select {}
}
```

`server.NewServer(flagAddress, flagAbci, app)` 会调用 `NewSocketServer(protoAddr, app)` 创建 socket server.
`NewSocketServer` 中会实例化 `SocketServer`对象并 实例化 `*service.NewBaseService(nil, "ABCIServer", s)` 来设置对象属性 `BaseService`的值

```plain
> `BaseService` 是比较关键的一个结构体类型 ，其继承了 `Service`接口，Service 接口定义了一个具有启动，停止，重启接口的基础服务，Tendermint中其他所有具备此属性的接口均继承并实现Service 接口定义的方法。 可以参考 BaseService 的使用示例 libs/service/service.go:69-96  ，BaseService结构体中name参数根据impl 实例化的不同而设置不同的name
`srv.Start()` 调用了 BaseService 的 Start() 方法，这个方法里做了原子检查防止重复启动应用，并调用实例化的 impl Service 对应的 OnStart() 方法。在Kvstore 中，OnStart方法就是 `SocketServer`的 OnStart 方法。在此方法中 `ln, err := net.Listen(s.proto, s.addr)` 启动监听对应的地址和端口，
```

    s.listener = ln
    go s.acceptConnectionsRoutine()

```
并启动goroutinue 来接受客户端连接, 在 `acceptConnectionsRoutine`中
```

    func (s *SocketServer) acceptConnectionsRoutine() {
            for {
                // 接受连接
                s.Logger.Info("Waiting for new connection...")
                conn, err := s.listener.Accept()
                if err != nil {
                    if !s.IsRunning() {
                        return // 没有start 直接返回
                    }
                    s.Logger.Error("Failed to accept connection: " + err.Error())
                    continue
                }
                s.Logger.Info("Accepted a new connection")
                // 创建带锁的conn
                connID := s.addConn(conn)
                closeConn := make(chan error, 2)              //  推送连接信号关闭
                responses := make(chan *types.Response, 1000) // 缓冲响应的通道
                // Read requests from conn and deal with them 从连接中读取protobuf请求并处理protobuf类型
                go s.handleRequests(closeConn, conn, responses)
                // Pull responses from 'responses' and write them to conn.  推送响应并回写到连接中
                go s.handleResponses(closeConn, conn, responses)
                // Wait until signal to close connection  等待信号关闭连接
                go s.waitForClose(closeConn, connID)
            }
    }

```

```

```go
`handleRequest` 中会根据 handleRequests 中解析的protobuf消息类型来定向解析响应的结构体类型，并将结果写入chan response 中，这些规则都定义在 types.pb.go 文件中, 所以在 `acceptConnectionRoutine` 方法中是启动两个协程，一个处理请求，一个处理应答。
```

### abci-cli 客户端

在终端执行 `abci-cli echo zbc` 时，会与 ABCI 应用服务端建立 TCP 连接并将 zbc 发送到服务端处理，收到响应后断开连接。

`RootCmd`中的方法 `PersistentPreRunE` 会在子命令运行之前调用，方法中会创建新的 socket 客户端对象

` client, err = abcicli.NewClient(flagAddress, flagAbci``,`` false) ` client 为全局变量。

在 `echo` 子命令中调用 `res, err := client.EchoSync(msg) ` 是调用 socketClient 中的 EchoSync() 方法来实现 echo 的逻辑, 其中的数据处理也是依据 types.pb.go 中关于 Request 和 Respose 的定义。

## in process 启动 tendermint 时 ABCI 调用机制

### ABCI 应用服务器和客户端

​ 以 `gaiad start` 为例，执行命令之后首先是配置的预加载

1.  在 server/util.go 的 `PersistentPreRunEFn` 方法中, 加载的配置文件目标默认为 ~/.gaiad/config/config.toml 和 app.toml

2.  AddCommands 的添加其中第 4 个参数 newApp 是函数类型参数将 newApp 方法(**返回值类型为 abci.Application**所以**GaiaApp 继承 BaseApp 这个 ABCI application**)传递到 sdk 的 AddCommands 方法中，newApp 方法返回的是实例化的 gaia app，其接收的参数也是 sdk 中的 `app := appCreator(ctx.Logger, db, traceWriter)`

3.  sdk 中的 AddCommands 方法会继续添加 sdk 中的 tendermint 子命令和 start 命令等。

4.  在 start 命令中会默认以 in process 的方式启动 ABCIserver 和 tendermint 服务。

5.  startInProcess 方法中有两个重要的逻辑一是根据前面传递过来的创建 app 实例的 newApp 方法实例化 app，二是调用 node.NewNode()方法创建一个 tendermint 节点。

6.  在 NewNode 方法中

    ```go
    tmNode, err := node.NewNode(
    		cfg,// 配置参数结构体
    		pvm.LoadOrGenFilePV(cfg.PrivValidatorKeyFile(), cfg.PrivValidatorStateFile()),// 见证者相关
    		nodeKey, // 节点key
    		proxy.NewLocalClientCreator(app), // ABCI client
    		node.DefaultGenesisDocProviderFunc(cfg),
    		node.DefaultDBProvider,
    		node.DefaultMetricsProvider(cfg.Instrumentation),
    		ctx.Logger.With("module", "node"),
    	)

    ```

    7.  NewNode 中会创建 tendermint 节点运行需要的所有信息包括数据库初始化，创世节点信息，abci client，eventBus, 交易索引等，这里只跟踪 abci 相关的代码。

    8.  `proxyApp, err := createAndStartProxyAppConns(clientCreator, logger)` 最终调用 `NewMultiAppConn` 创建 abci clients, 同时管理 mempool, consensus, query3 种 client。其中 `multiAppConn` 有 **`BaseService` **作为自定义结构的匿名字段，实例了 name 为 `multiAppConn`的 baseservice。

    在 `proxyApp.Start()`中最终会调用 `multiAppConn`的 `OnStart`方法这里面会继续实例化 multiAppConn 的参数比如 `queryConn`的赋值 会先实例化真正的 ABCI CLIENT **`querycli, err := app.clientCreator.NewABCIClient()`** , 所以最终使用的是 **abci/client/local_client.go** 创建的 name 为`localClient`的基于 BaseService 的 ABCI Client

    ```go
    func (l *localClientCreator) NewABCIClient() (abcicli.Client, error) {
    	return abcicli.NewLocalClient(l.mtx, l.app), nil
    }
    ```

    然后赋值 queryConn`app.queryConn = NewAppConnQuery(querycli)`

    9.  doHandshake

    ```go
    if err := doHandshake(stateDB, state, blockStore, genDoc, eventBus, proxyApp, consensusLogger); err != nil {
       return nil, err
    }
    ```

    doHandshake 方法会代理所有应用与 tendermint 需要交互的业务 。

    10. NewHandshaker 方法

    ```go
    func NewHandshaker(stateDB dbm.DB, state sm.State,
       store sm.BlockStore, genDoc *types.GenesisDoc) *Handshaker {

       return &Handshaker{
          stateDB:      stateDB, // 状态存储db实例
          initialState: state, // tendermint区块状态结构体实例
          store:        store, // 区块存储实例
          eventBus:     types.NopEventBus{},
          genDoc:       genDoc,
          logger:       log.NewNopLogger(),
          nBlocks:      0,
       }
    }
    ```

    11. `handshaker.Handshake(proxyApp)` 中的 `res, err := proxyApp.Query().InfoSync(proxy.RequestInfo) ` 方法调用 ABCI 的 Query 方法来获得 ABCI client Info

    ```
    func (app *localClient) InfoSync(req types.RequestInfo) (*types.ResponseInfo, error) {
    	app.mtx.Lock()
    	defer app.mtx.Unlock()

    	res := app.Application.Info(req)
    	return &res, nil
    }
    ```

    从代码可以看出最终就是调用了应用的 Info 方法也就是 sdk 的 BaseApp 的 Info 方法

    **_总结_**：in process 启动时不同于单独启动，前者不需要启动一个 server 对 proxy_app 地址的监听，只需要调用代码即可，因为应用 app 继承了 BaseApp，而 BaseApp 实现了 ABCI 接口
