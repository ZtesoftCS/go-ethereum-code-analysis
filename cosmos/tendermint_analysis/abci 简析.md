# cosmos sdk 中query abci消息类型

```plain
func (app *BaseApp) Query(req abci.RequestQuery) abci.ResponseQuery {
   path := splitPath(req.Path)
   if len(path) == 0 {
      sdkerrors.QueryResult(sdkerrors.Wrap(sdkerrors.ErrUnknownRequest, "no query path provided"))
   }
   switch path[0] {
   // "/app" prefix for special application queries
   case "app":
      return handleQueryApp(app, path, req)
   case "store":
      return handleQueryStore(app, path, req)
   case "p2p":
      return handleQueryP2P(app, path)
   case "custom":
      return handleQueryCustom(app, path, req)
   }
   return sdkerrors.QueryResult(sdkerrors.Wrap(sdkerrors.ErrUnknownRequest, "unknown query path"))
}
```
其中custom 用于 Querier ，
nscli query nameservice resolve jack.id

上面命令经过Query处理后 path 为数组 [custom nameservice resolve jack.id]

# 

# abci cli kvstore 例子

调用 broadcast_tx_commit 的时候, 会先调用 CheckTx, 验证通过后会把 TX 加入到 mempool 里. 在 kvstore 示例中没有对 transaction 做检查, 直接通过:

```plain
func (app *Application) CheckTx(req types.RequestCheckTx) types.ResponseCheckTx {
   return types.ResponseCheckTx{Code: code.CodeTypeOK, GasWanted: 1}
}
```
放到 mempool 里的 TX 会被定期广播到所有节点. 当 Tendermint 选出了 Proposal 节点后, 它便会从 mempool 里选出一系列的 TXs , 将它们组成一个 Block, 广播给所有的节点. 节点在收到 Block 后, 会对 Block 里的所有 TX 执行 DeliverTX 操作, 同时对 Block 执行 Commit 操作.

调用 broadcast_tx_commit 返回的结果其实就是 DeliverTX 返回的结果:

```plain
// tx is either "key=value" or just arbitrary bytes
func (app *Application) DeliverTx(req types.RequestDeliverTx) types.ResponseDeliverTx {
   var key, value []byte
   parts := bytes.Split(req.Tx, []byte("="))
   if len(parts) == 2 {
      key, value = parts[0], parts[1]
   } else {
      key, value = req.Tx, req.Tx
   }
   app.state.db.Set(prefixKey(key), value)
   app.state.Size++
   events := []types.Event{
      {
         Type: "app",
         Attributes: []kv.Pair{
            {Key: []byte("creator"), Value: []byte("Cosmoshi Netowoko")},
            {Key: []byte("key"), Value: key},
         },
      },
   }
   return types.ResponseDeliverTx{Code: code.CodeTypeOK, Events: events}
}
```
可以看出它会从输入参数中解析出 key 和 value, 最后保存在应用的 State 中.

当所有的 TX 被处理完之后需要调用 Commit 来更新整个区块的状态, 包括高度加 1 等:

```plain
func (app *Application) Commit() types.ResponseCommit {
   // Using a memdb - just return the big endian size of the db
   appHash := make([]byte, 8)
   binary.PutVarint(appHash, app.state.Size)
   app.state.AppHash = appHash
   app.state.Height++
   saveState(app.state)
   resp := types.ResponseCommit{Data: appHash}
   if app.RetainBlocks > 0 && app.state.Height >= app.RetainBlocks {
      resp.RetainHeight = app.state.Height - app.RetainBlocks + 1
   }
   return resp
}
```

