## ethapi/api包分析
ethapi/api包主要是进入js的命令行界面后，输入的命令实现部分。<br>
js的命令实现在ethapi/api和node/api中。目前一共有三种api的命令。<br>
(1)第一种是admin相关的命令，这个是通过安全的RPC通道实现的。其结构体为PrivateAdminAPI<br>
```
// PrivateAdminAPI is the collection of administrative API methods exposed only
// over a secure RPC channel.
type PrivateAdminAPI struct {
	node *Node // Node interfaced by this API
}
```
(2)第二种是personal相关的命令，主要是负责账户管理相关命令，可以lock和unlock账户。其结构体为PrivateAccountAPI<br>
```
// PrivateAccountAPI provides an API to access accounts managed by this node.
// It offers methods to create, (un)lock en list accounts. Some methods accept
// passwords and are therefore considered private by default.
type PrivateAccountAPI struct {
	am        *accounts.Manager
	nonceLock *AddrLocker
	b         Backend
}
```
(3)第三种是eth相关的命令，主要是可以操作区块上的相关命令。其结构体为PublicBlockChainAPI<br>
```
// PublicBlockChainAPI provides an API to access the Ethereum blockchain.
// It offers only methods that operate on public data that is freely available to anyone.
type PublicBlockChainAPI struct {
	b Backend
}
```