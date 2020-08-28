node包建立多重协议以太坊节点

一个node是一组服务，通过共享资源提供RPC API。
Services提供devp2p协议，当node实例开始运行，服务被wire到devp2p网络

Node管理资源

Node实例使用到的所有文件系统资源被放到data目录中。
每个资源的路径可以通过额外的node配置改写。
data目录是可选的。==如果没有设置或资源路径没有指定，node包会在内存中创建资源。==

配置Node并开启p2p服务，来访问devp2p网络。
每个devp2p网络上的host有一个唯一标识符，node key.
在重启过程中，Node实例维持这个key。
Node加载static的和trusted可信的节点列表，保证关于其他hosts的知识持久化。

JSON-RPC服务器可以在Node上启动，上面运行着HTTP，WebSocket，IPC。
已注册服务提供的RPC模块，将通过通过这些endpoints提供。
用户可以限制任何endpoint为RPC模块的子集。
Node自身提供debug,admin,web3模块。

通过service context,服务实现可以打开LevelDB数据库。
node包选择每个数据库的文件系统位置。
如果node配置为没有data目录运行，databases替换为内存打开。

Node创建共享的加密的以太坊账户keys的store，Services能够通过service context
访问account manager

在实例之间共享数据目录

如果Multiple node有区别的实例名称，他们能够共享一个数据目录。
共享行为依赖于资源的类型。

devp2p相关资源（node key，static/trusted node列表，known hosts database）存储到与实例名相同的目录中。

LevelDB数据库也存储到实例子目录中。
如果多节点实例使用同一data目录，使用唯一名称打开数据库将为每一个实例创建一个数据库。

账户key store在所有node之间共享，使用一个data目录。
其location可以通过KeyStoreDir配置项修改。

Data Directory Sharing Example见doc.go

本包主要class结构

配置类代表配置项集合，用于微调P2P协议栈的网络层。这些值能被所有注册服务进一步扩展
Config
|-DataDir 文件系统目录，node可将其用于任何数据存储需求。
|-P2P P2P网络的配置
|-KeyStoreDir 不指定，New会创建临时目录，node停止时销毁
|-IPCPath IPC存放IPC endpoint的请求路径。空路径disable IPC
|-HTTPHost Host interface，在其上开启HTTP RPC服务。
|-HTTPPort HTTP RPC服务使用的TCP端口号
|-HTTPModules 通过HTTP RCP接口暴露的API模块列表
|-StaticNodes() 解析static-nodes.json文件，返回配置的静态节点enode URLs列表
|-TrustedNodes() 解析trusted-nodes.json文件，返回配置的静态节点enode URLs列表
|-NodeDB() returns the path to the discovery node database
|-NodeKey() 检索当前节点配置的私钥，先检查手动设置key，失败再查配置data目录，都没有，新生成。

Node
|-eventmux Event multiplexer used between the services of a stack
|-config
|-accman  Manager is an overarching account manager that can communicate with various backends for signing transactions
|-instanceDirLock  prevents concurrent use of instance directory
|-serverConfig p2p配置
|-server Server manages all peer connections
|-serviceFuncs ServiceConstructor is the function signature of the constructors
|-services Currently running services
|-rpcAPIs List of APIs currently provided by the node
|-inprocHandler In-process RPC request handler to process the API requests
|-ipc\http\ws属性

备注：
1、Server represents a RPC server
2、// API describes the set of methods offered over the RPC interface
type API struct {
	Namespace string      // namespace under which the rpc methods of Service are exposed
	Version   string      // api version for DApp's
	Service   interface{} // receiver instance which holds the methods
	Public    bool        // indication if the methods must be considered safe for public use
}

Service
|-Protocols() Protocols retrieves the P2P protocols the service wishes to start.
|-APIs()  APIs retrieves the list of RPC descriptors the service provides
|-Start(server *p2p.Server) 
|-Stop()

ServiceContext
|-config
|-services Index of the already constructed services
|-EventMux Event multiplexer used for decoupled notifications
|-AccountManager  Account manager created by the node.
|-OpenDatabase() 打开指定数据库，通过node data目录。如果是临时节点，返回内存数据库
|-Service() 检索指定类型的运行服务

PrivateAdminAPI
|-AddPeer() 
	// Try to add the url as a static peer and return
	node, err := discover.ParseNode(url)
|-RemovePeer()  RemovePeer disconnects from a a remote node if the connection exists
|-PeerEvents() 


PublicAdminAPI



