[https://docs.tendermint.com/master/](https://docs.tendermint.com/master/) 官方文档

# rpc list

gaia节点配置文件 config.toml中的 rpc.laddr 的默认配置为127.0.0.1:26657。如果本地需要启动两条链那么config.toml 中所有的端口配置都需要修改,以免端口占用冲突。

浏览器访问 [http://127.0.0.1:26657/](http://127.0.0.1:26657/) 地址会显示tendermint 提供的所有rpc 接口，这些接口显示了temdermint 网络层和共识层提供的服务。

Available endpoints:

Endpoints that require arguments:

[//127.0.0.1:26657/abci_info?](http://127.0.0.1:26657/abci_info?)

[//127.0.0.1:26657/abci_query?path=_&data=_&height=_&prove=_](http://127.0.0.1:26657/abci_query?path=_&data=_&height=_&prove=_)

[//127.0.0.1:26657/block?height=_](http://127.0.0.1:26657/block?height=_)

[//127.0.0.1:26657/block_results?height=_](http://127.0.0.1:26657/block_results?height=_)

[//127.0.0.1:26657/blockchain?minHeight=_&maxHeight=_](http://127.0.0.1:26657/blockchain?minHeight=_&maxHeight=_)

[//127.0.0.1:26657/broadcast_evidence?evidence=_](http://127.0.0.1:26657/broadcast_evidence?evidence=_)

[//127.0.0.1:26657/broadcast_tx_async?tx=_](http://127.0.0.1:26657/broadcast_tx_async?tx=_)

[//127.0.0.1:26657/broadcast_tx_commit?tx=_](http://127.0.0.1:26657/broadcast_tx_commit?tx=_)

[//127.0.0.1:26657/broadcast_tx_sync?tx=_](http://127.0.0.1:26657/broadcast_tx_sync?tx=_)

[//127.0.0.1:26657/commit?height=_](http://127.0.0.1:26657/commit?height=_)

[//127.0.0.1:26657/consensus_params?height=_](http://127.0.0.1:26657/consensus_params?height=_)

[//127.0.0.1:26657/consensus_state?](http://127.0.0.1:26657/consensus_state?)

[//127.0.0.1:26657/dump_consensus_state?](http://127.0.0.1:26657/dump_consensus_state?)

[//127.0.0.1:26657/genesis?](http://127.0.0.1:26657/genesis?)

[//127.0.0.1:26657/health?](http://127.0.0.1:26657/health?)

[//127.0.0.1:26657/net_info?](http://127.0.0.1:26657/net_info?)

[//127.0.0.1:26657/num_unconfirmed_txs?](http://127.0.0.1:26657/num_unconfirmed_txs?)

[//127.0.0.1:26657/status?](http://127.0.0.1:26657/status?)

[//127.0.0.1:26657/subscribe?query=_](http://127.0.0.1:26657/subscribe?query=_)

[//127.0.0.1:26657/tx?hash=_&prove=_](http://127.0.0.1:26657/tx?hash=_&prove=_)

[//127.0.0.1:26657/tx_search?query=_&prove=_&page=_&per_page=_](http://127.0.0.1:26657/tx_search?query=_&prove=_&page=_&per_page=_)

[//127.0.0.1:26657/unconfirmed_txs?limit=_](http://127.0.0.1:26657/unconfirmed_txs?limit=_)

[//127.0.0.1:26657/unsubscribe?query=_](http://127.0.0.1:26657/unsubscribe?query=_)

[//127.0.0.1:26657/unsubscribe_all?](http://127.0.0.1:26657/unsubscribe_all?)

[//127.0.0.1:26657/validators?height=_](http://127.0.0.1:26657/validators?height=_)

# rpc code locate

github.com/tendermint/tendermint/rpc/core/routes, 所有的rpc接口的定义都在这个文件中。

# rpc register

tendermint  是随着应用(gaia)的start 而以进程的形式启动的，其中tendermint的rpc也在这个创建和启动tendermint节点的过程中启动，首先是注册所有的rpc方法

```plain
rpcserver.RegisterRPCFuncs(mux, rpccore.Routes, coreCodec, rpcLogger)
```
然后是监听rpc端口, 端口可以监听多个，在应用配置中rpc.laddr 可以逗号分隔写多个。
# rpc call

在整个rpc call的流程最末端，tendermint有一一对应的方法来调用注册的rpc router

```plain
github.com/tendermint/tendermint/rpc/client/httpclient.go
```

