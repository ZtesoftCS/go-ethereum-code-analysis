# gaia 中默认启动方式

1. 独立进程:
```go
svr, err := server.NewServer(addr, "socket", app)
s = NewSocketServer(protoAddr, app)
s.BaseService = *service.NewBaseService(nil, "ABCIServer", s)
```
github.com/tendermint/tendermint@v0.33.5/abci/server/socket_server.go:45
s 参数为实例化的 SocketServer 结构体

err = svr.Start()     libs/server/start.go:129

这里的Start()调用的BaseService的 Start()方法，在此方法内再调用SocketServer的 OnStart()方法 ，socket监听 proxy_app参数对应的地址或者默认的tcp://127.0.0.1:26658

err := bs.impl.OnStart()  libs/service/service.go:140

独立进程已经启动


1. 跟随cosmos sdk进程

       以启动tm全节点Node的方式启动, $tendermint node 也是这种启动方式

```plain
tmNode, err := node.NewNode(...)
node.BaseService = *service.NewBaseService(logger, "Node", node)
NewBaseService 第三个参数为Node本身所以在tmNode.Start()中的OnStart()方法为
```
/node/node.go:738的OnStart()方法，rpc端口为 rpc.laddr配置对应的地址 tcp://127.0.0.1:26657
# 实现启动多个tendermint

1. 第一个tendermint使用默认的 in process 方式启动
2. 第二个使用 tendermint node 的方式启动

在cosmos sdk 中 server/util.go:120 添加类似 tendermint2 的子命令, 并在此子命令下添加

【tendermint node】的 node 子命令具体方法名可以为RunNode。这种方式启动的   tendermint 并没有应用支持。所以启动时连接 26658端口会报错。

RunNode 方法中需要指定此tendermint的 root 目录。

```go
func RunNode(ctx *Context) *cobra.Command {
   return &cobra.Command{
      Use:   "node",
      Short: "Run Node",
      RunE: func(cmd *cobra.Command, args []string) error {
         cnnf := ctx.Config
         nodeProvider := node.DefaultNewNode
         //cnnf := config.DefaultConfig()
         cnnf.BaseConfig.RootDir = "/Users/haierding/.tendermint"
         n, err := nodeProvider(cnnf, ctx.Logger)
         if err != nil {
            return fmt.Errorf("failed to create node: %w", err)
         }
         
         if err := n.Start(); err != nil {
            return fmt.Errorf("failed to start node: %w", err)
         }
         ctx.Logger.Info("Started node", "nodeInfo", n.Switch().NodeInfo())
         // Stop upon receiving SIGTERM or CTRL-C.
         tmos.TrapSignal(ctx.Logger, func() {
            if n.IsRunning() {
               n.Stop()
            }
         })
         return nil
      },
   }
}
```

