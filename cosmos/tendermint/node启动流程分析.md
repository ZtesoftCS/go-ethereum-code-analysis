再说启动流程之前我们看看一个github的项目。  [cobra](https://github.com/spf13/cobra) 它是一个是用于创建强大的现代CLI应用程序的库，也是用于生成应用程序和命令文件的程序。 简单点来说就是方便使用者更易创建命令行工具。 

举个静态博客生成器hugo的例子:
```shell
hugo help
hugo is the main command, used to build your Hugo site.

Hugo is a Fast and Flexible Static Site Generator
built with love by spf13 and friends in Go.

Complete documentation is available at http://gohugo.io/.

Usage:
  hugo [flags]
  hugo [command]

Available Commands:
  benchmark   Benchmark Hugo by building a site a number of times.
  check       Contains some verification checks
  config      Print the site configuration
  convert     Convert your content to different formats
  env         Print Hugo version and environment info
  gen         A collection of several useful generators.
  help        Help about any command
  import      Import your site from others.
  list        Listing out various types of content
  new         Create new content for your site
  server      A high performance webserver
  version     Print the version number of Hugo

```
使用这个包可以方便管理这些子命令。  和这个包类似功能的还有一个叫做[cli](https://github.com/urfave/cli)。 之前我都是用的这个包。 大致流程都是一样的。 我们看一下官方的readme给的一个例子。

```shell
package main

import (
  "fmt"
  "strings"

  "github.com/spf13/cobra"
)

func main() {
  var echoTimes int

  var cmdPrint = &cobra.Command{
    Use:   "print [string to print]",
    Short: "Print anything to the screen",
    Long: `print is for printing anything back to the screen.
For many years people have printed back to the screen.`,
    Args: cobra.MinimumNArgs(1),
    Run: func(cmd *cobra.Command, args []string) {
      fmt.Println("Print: " + strings.Join(args, " "))
    },
  }

  var cmdEcho = &cobra.Command{
    Use:   "echo [string to echo]",
    Short: "Echo anything to the screen",
    Long: `echo is for echoing anything back.
Echo works a lot like print, except it has a child command.`,
    Args: cobra.MinimumNArgs(1),
    Run: func(cmd *cobra.Command, args []string) {
      fmt.Println("Print: " + strings.Join(args, " "))
    },
  }

  var cmdTimes = &cobra.Command{
    Use:   "times [# times] [string to echo]",
    Short: "Echo anything to the screen more times",
    Long: `echo things multiple times back to the user by providing
a count and a string.`,
    Args: cobra.MinimumNArgs(1),
    Run: func(cmd *cobra.Command, args []string) {
      for i := 0; i < echoTimes; i++ {
        fmt.Println("Echo: " + strings.Join(args, " "))
      }
    },
  }

  cmdTimes.Flags().IntVarP(&echoTimes, "times", "t", 1, "times to echo the input")

  var rootCmd = &cobra.Command{Use: "app"}
  rootCmd.AddCommand(cmdPrint, cmdEcho)
  cmdEcho.AddCommand(cmdTimes)
  rootCmd.Execute()
}

/*
这样 我们就实现go run main.go print | echo | times 三个子命令了  
*/
```
关于这个包我们就只说这么多，开始进行Tendermint的流程分析。
进入cmd/tendermint/main.go 文件中。
```go
func main() {
  // 创建根命令
	rootCmd := cmd.RootCmd
	
	// 创建了一些子命令 这些命令在这里不再细说了  大家只要tendermint help一下就能命名其含义 如果想最终具体某个子命令的实现只需要到
	// cmd/tendermint/commands找到对应的实现就好了 在此处我们只关注node子命令的实现。
	rootCmd.AddCommand(
		cmd.GenValidatorCmd,
		cmd.InitFilesCmd,
		cmd.ProbeUpnpCmd,
		cmd.LiteCmd,
		cmd.ReplayCmd,
		cmd.ReplayConsoleCmd,
		cmd.ResetAllCmd,
		cmd.ResetPrivValidatorCmd,
		cmd.ShowValidatorCmd,
		cmd.TestnetFilesCmd,
		cmd.ShowNodeIDCmd,
		cmd.GenNodeKeyCmd,
		cmd.VersionCmd)

  // 这个是我们重点关注的子命令 用于创建node。
	nodeFunc := nm.DefaultNewNode

	// 添加node子命令 
	rootCmd.AddCommand(cmd.NewRunNodeCmd(nodeFunc))

	cmd := cli.PrepareBaseCmd(rootCmd, "TM", os.ExpandEnv(filepath.Join("$HOME", cfg.DefaultTendermintDir)))
	if err := cmd.Execute(); err != nil {
		panic(err)
	}
}

func NewRunNodeCmd(nodeProvider nm.NodeProvider) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "node",
		Short: "Run the tendermint node",
		
		RunE: func(cmd *cobra.Command, args []string) error {
			// 当调用tendermint node .... 就会进入到这个函数  
			
			// 这里就是先创建一个node对象  nodeProvider就是上面的nm.DefaultNewNode  
			// 这个函数流程就是创建node对象 然后启动node 调用n.RunForever()进行守护
			// RunForever 其实就是监听系统的os.Interrupt, syscall.SIGTERM信号 当收到这两个信号时
			// 调用node.Stop 进行退出处理。否则一直在运行。
			n, err := nodeProvider(config, logger)
			if err != nil {
				return fmt.Errorf("Failed to create node: %v", err)
			}

			if err := n.Start(); err != nil {
				return fmt.Errorf("Failed to start node: %v", err)
			}
			logger.Info("Started node", "nodeInfo", n.Switch().NodeInfo())

			// Trap signal, run forever.
			n.RunForever()

			return nil
		},
	}

	AddNodeFlags(cmd)
	return cmd
}
```
分析完main函数 我们就要集中到node的创建和启动了， 那里就是整个Tendermint的启动核心。代码在node/node.go的文件中。
先看创建node的过程
```go
func DefaultNewNode(config *cfg.Config, logger log.Logger) (*Node, error) {
	return NewNode(config,
		privval.LoadOrGenFilePV(config.PrivValidatorFile()),
		proxy.DefaultClientCreator(config.ProxyApp, config.ABCI, config.DBDir()),
		DefaultGenesisDocProviderFunc(config),
		DefaultDBProvider,
		DefaultMetricsProvider(config.Instrumentation),
		logger,
	)
}
// 为了分析方便 会忽略一些细节
func NewNode(config *cfg.Config,
	privValidator types.PrivValidator,
	clientCreator proxy.ClientCreator,
	genesisDocProvider GenesisDocProvider,
	dbProvider DBProvider,
	metricsProvider MetricsProvider,
	logger log.Logger) (*Node, error) {

	// 根据配置信息 创建数据库的使用 tendermint已经封装了leveldb(c/go 一个是原生go写的客户端 一个是cgo写的客户端) fsdb remotedb memdb的实现。 
	// 如果不出意外我们使用的是leveldb。 当然也是可以扩展自己的后端存储 只要实现db定义的那几个接口就行。 
	// 下面我们直接以leveldb作为数据存储来分析
	// 此处打开或者创建名称blockstore.db的数据库
	blockStoreDB, err := dbProvider(&DBContext{"blockstore", config})
	if err != nil {
		return nil, err
	}
	// 创建区块存储对象  这个函数不知道大家还有没有印象 在Blockchain模块处有分析过。 回想一下Blockchain模块， store.go的文件中包含了对区块数据的读取和写入操作等功能
	blockStore := bc.NewBlockStore(blockStoreDB)

	// 同理 打开或者创建名称state.db的数据库 保存状态相关的内容 
	stateDB, err := dbProvider(&DBContext{"state", config})
	if err != nil {
		return nil, err
	}
  
  // 在加载状态数据之前， 我们先加载一下创世区块文件 也就是genesis.json文件 这个文件中保存了
  // 最初的状态信息 当然如果没有加载到 Tendermint会默认创建一个创世区块状态。 
	genDoc, err := loadGenesisDoc(stateDB)
	if err != nil {
		genDoc, err = genesisDocProvider()
		if err != nil {
			return nil, err
		}
		saveGenesisDoc(stateDB, genDoc)
	}

  // 根据stateDB和之前加载的创世区块文件来加载出最新状态。
 //  如果数据库中没有读取到最新的状态 则从创世区块来生成状态。
	state, err := sm.LoadStateFromDBOrGenesisDoc(stateDB, genDoc)
	if err != nil {
		return nil, err
	}


  // 下面这几行就是创建和我们自己的应用层交互的地方  这里我们准备先不分析 
  // 留到下一节分析abci接口的时候在追踪这个地方 但是有个地方我们我先说一下就是这个
  // NewHandshaker 这个函数创建handshaker之后 最后会在proxyApp.Start中调用了
  // handshaker.Handshake这个函数  这个函数会重放已经保存的区块内容将Tendermint保存的区块一一调用
  // 我们的APP层 然后进行APPHASH相关的校验 在共识算法中会有描述。
  // proxyApp.Start()执行之后 已存区块已经重放完成。 同时创建了内存池, 共识, 查询的应用客户端
	consensusLogger := logger.With("module", "consensus")
	handshaker := cs.NewHandshaker(stateDB, state, blockStore, genDoc)
	handshaker.SetLogger(consensusLogger)
	proxyApp := proxy.NewAppConns(clientCreator, handshaker)
	proxyApp.SetLogger(logger.With("module", "proxy"))
	if err := proxyApp.Start(); err != nil {
		return nil, fmt.Errorf("Error starting proxy app connections: %v", err)
	}

	//此处再次重新加载一下状态。 因为在重放的时候状态可能会改变 比如应用层在上次停掉时比Tendermint保存的区块高度少一个 重放的时候就会追上来 这就会导致状态发生了变化。
	state = sm.LoadState(stateDB)

	// Tendermint对验证角色进行了封装 默认是从配置文件中加载自己的验证器信息 
	// 同时提供了通过socket来获取是有验证器信息的功能 
	// 当然前提你要是一个验证者角色才行
	if config.PrivValidatorListenAddr != "" {
		var (
			// TODO: persist this key so external signer
			// can actually authenticate us
			privKey = ed25519.GenPrivKey()
			pvsc    = privval.NewSocketPV(
				logger.With("module", "privval"),
				config.PrivValidatorListenAddr,
				privKey,
			)
		)

		if err := pvsc.Start(); err != nil {
			return nil, fmt.Errorf("Error starting private validator client: %v", err)
		}

		privValidator = pvsc
	}

	// 开始创建内存池Reactor 关于内存池内容可以看看内存池的模块分析
	mempoolLogger := logger.With("module", "mempool")
	mempool := mempl.NewMempool(
		config.Mempool,
		proxyApp.Mempool(),
		state.LastBlockHeight,
		mempl.WithMetrics(memplMetrics),
	)
	mempool.SetLogger(mempoolLogger)
	mempool.InitWAL() // no need to have the mempool wal during tests
	mempoolReactor := mempl.NewMempoolReactor(config.Mempool, mempool)
	mempoolReactor.SetLogger(mempoolLogger)
	if config.Consensus.WaitForTxs() {
		mempool.EnableTxsAvailable()
	}

	//打开evidence.db 创建EvidenceReactor 
	evidenceDB, err := dbProvider(&DBContext{"evidence", config})
	if err != nil {
		return nil, err
	}
	evidenceLogger := logger.With("module", "evidence")
	evidenceStore := evidence.NewEvidenceStore(evidenceDB)
	evidencePool := evidence.NewEvidencePool(stateDB, evidenceStore)
	evidencePool.SetLogger(evidenceLogger)
	evidenceReactor := evidence.NewEvidenceReactor(evidencePool)
	evidenceReactor.SetLogger(evidenceLogger)

  // 下面几句是 先创建一个blockExec  这个对象最重要的就是之前我们在state中说的ApplyBlock 
  // 把Tendermint打包的区块提交到我们的应用层 然后更新Tendermint的状态，Mempool等。 具体查看state模块分析
  // 然后创建了Blockchain的Reactor
	blockExecLogger := logger.With("module", "state")
	// make block executor for consensus and blockchain reactors to execute blocks
	blockExec := sm.NewBlockExecutor(stateDB, blockExecLogger, proxyApp.Consensus(), mempool, evidencePool)
	// Make BlockchainReactor
	bcReactor := bc.NewBlockchainReactor(state.Copy(), blockExec, blockStore, fastSync)
	bcReactor.SetLogger(logger.With("module", "blockchain"))

	// 接下来是创建共识Reactor
	consensusState := cs.NewConsensusState(
		config.Consensus,
		state.Copy(),
		blockExec,
		blockStore,
		mempool,
		evidencePool,
		cs.WithMetrics(csMetrics),
	)
	consensusState.SetLogger(consensusLogger)
	if privValidator != nil {
		consensusState.SetPrivValidator(privValidator)
	}
	consensusReactor := cs.NewConsensusReactor(consensusState, fastSync)
	consensusReactor.SetLogger(consensusLogger)

	p2pLogger := logger.With("module", "p2p")

  // 创建P2P的switch 将上面的Reactor加入进来 其实我们可以看到 之前分析的那么多的模块 很多实例的创建其实都是在这个函数中完成的。
	sw := p2p.NewSwitch(config.P2P, p2p.WithMetrics(p2pMetrics))
	sw.SetLogger(p2pLogger)
	sw.AddReactor("MEMPOOL", mempoolReactor)
	sw.AddReactor("BLOCKCHAIN", bcReactor)
	sw.AddReactor("CONSENSUS", consensusReactor)
	sw.AddReactor("EVIDENCE", evidenceReactor)

  // 开始PEX的Reactor创建  
  // 创建地址簿 这个地址簿是维护所有peer的地址信息 是对peer进行crud的关键。
  // 这个在p2p模块中， 好像我没有把这块的代码进行文档化(todo)
	addrBook := pex.NewAddrBook(config.P2P.AddrBookFile(), config.P2P.AddrBookStrict)
	addrBook.SetLogger(p2pLogger.With("book", config.P2P.AddrBookFile()))
	if config.P2P.PexReactor {
		// TODO persistent peers ? so we can have their DNS addrs saved
		pexReactor := pex.NewPEXReactor(addrBook,
			&pex.PEXReactorConfig{
				Seeds:    cmn.SplitAndTrim(config.P2P.Seeds, ",", " "),
				SeedMode: config.P2P.SeedMode,
			})
		pexReactor.SetLogger(p2pLogger)
		sw.AddReactor("PEX", pexReactor)
	}

	sw.SetAddrBook(addrBook)

	// 下面是一个索引服务功能  这个是Tendermint提供的一个功能 就是可以对交易进行索引查找 这个功能我没有仔细分析
	// 个人认为这个功能意义不大 如果我实现了自己的APP 那么我可以在自己的APP层进行定制化的索引。 效果比这个好很多
    // 而且还不受这个限制。
    // 如果以后有时间 我会分析一下交易索引服务的原理 
	var txIndexer txindex.TxIndexer
	switch config.TxIndex.Indexer {
	case "kv":
		store, err := dbProvider(&DBContext{"tx_index", config})
		if err != nil {
			return nil, err
		}
		if config.TxIndex.IndexTags != "" {
			txIndexer = kv.NewTxIndex(store, kv.IndexTags(cmn.SplitAndTrim(config.TxIndex.IndexTags, ",", " ")))
		} else if config.TxIndex.IndexAllTags {
			txIndexer = kv.NewTxIndex(store, kv.IndexAllTags())
		} else {
			txIndexer = kv.NewTxIndex(store)
		}
	default:
		txIndexer = &null.TxIndex{}
	}

	indexerService := txindex.NewIndexerService(txIndexer, eventBus)
	indexerService.SetLogger(logger.With("module", "txindex"))

	node := &Node{
		config:        config,
		genesisDoc:    genDoc,
		privValidator: privValidator,

		sw:       sw,
		addrBook: addrBook,

		stateDB:          stateDB,
		blockStore:       blockStore,
		bcReactor:        bcReactor,
		mempoolReactor:   mempoolReactor,
		consensusState:   consensusState,
		consensusReactor: consensusReactor,
		evidencePool:     evidencePool,
		proxyApp:         proxyApp,
		txIndexer:        txIndexer,
		indexerService:   indexerService,
		eventBus:         eventBus,
	}
	node.BaseService = *cmn.NewBaseService(logger, "Node", node)
	return node, nil
}
```
到了这里我们差不多就看完了node的创建。 总结一下床架node的过程：

*  创建或者打开blockstore.db 最终创建bc实例和bcReactor
*  创建或者打开state.db 最终更新state对象
*  创建mempool实例 加载本地持久化的交易池 并创建mempoolReactor
*  创建与APP之间的客户端 并重返所有保存的区块
*  创建证据内存池和证据Reactor
*  根据上面已经创建的对象开始创建consensus对象和Reactor
*  开始创建p2p的Switch 将所有reactor加入。 
*  开启tx_index服务
*  返回node实例


创建完实例就需要启动了 来看看启动流程
```go
func (n *Node) OnStart() error {

	// 创建p2p的监听  有了监听才能接受别人的请求 这一步个人觉得在上面的函数里比较合适 这里应该启动SW 而不是还要进行一些初始化的工作
	l := p2p.NewDefaultListener(
		n.config.P2P.ListenAddress,
		n.config.P2P.ExternalAddress,
		n.config.P2P.UPNP,
		n.Logger.With("module", "p2p"))
	n.sw.AddListener(l)

  // 从我们的配置文件中加载一个node的配置  
  // 结构类似这个 {"priv_key":{"type":"tendermint/PrivKeyEd25519","value":"I5Dn6uZXbNO+VgvXNgehFduA2HsdMs+XubFCWzOM0AYZ66I3Bjwakez1B+klii6Am6WAdP95AWIo8wMkkafUeg=="}}
  // 如果config 文件夹下没有node_key.json 则会自动创建一个
	nodeKey, err := p2p.LoadOrGenNodeKey(n.config.NodeKeyFile())
	if err != nil {
		return err
	}
	n.Logger.Info("P2P Node ID", "ID", nodeKey.ID(), "file", n.config.NodeKeyFile())

	nodeInfo := n.makeNodeInfo(nodeKey.ID())
	n.sw.SetNodeInfo(nodeInfo)
	n.sw.SetNodeKey(nodeKey)

	//configure文件夹下的 addrbook.json 会加入我们自己的节点
	n.addrBook.AddOurAddress(nodeInfo.NetAddress())

	// 把配置文件中配置的私有节点也加入addrBook
	n.addrBook.AddPrivateIDs(cmn.SplitAndTrim(n.config.P2P.PrivatePeerIDs, ",", " "))

  // 开启rpc服务 找个时间专门分析一下rpc服务 Tendermint的rpc流程还是比较清晰的 
  // 不像ethereum中使用了大量的反射包 查询一个具体的rpc方法实现非常麻烦
	if n.config.RPC.ListenAddress != "" {
		listeners, err := n.startRPC()
		if err != nil {
			return err
		}
		n.rpcListeners = listeners
	}

  // 性能监控相关的地方 我都忽略掉了  目前我都不会考虑这个地方的分析
	if n.config.Instrumentation.Prometheus &&
		n.config.Instrumentation.PrometheusListenAddr != "" {
		n.prometheusSrv = n.startPrometheusServer(n.config.Instrumentation.PrometheusListenAddr)
	}

	// 终于可以启动SW了  启动Switch的过程也就意味着所有Reactor的启动 每个Reactor的启动就会启动相对应的各个模块的服务 具体的启动可以看各个模块的分析
	err = n.sw.Start()
	if err != nil {
		return err
	}

	// 先对配置中的持久地址进行一次拨号  后面在PEX中会每隔一段时间都会进行检查
	if n.config.P2P.PersistentPeers != "" {
		err = n.sw.DialPeersAsync(n.addrBook, cmn.SplitAndTrim(n.config.P2P.PersistentPeers, ",", " "), true)
		if err != nil {
			return err
		}
	}

	// 开启交易索引服务 
	return n.indexerService.Start()
}

```

启动流程就是这么多 主要就是启动sw 然后启动rpc服务 最后再启动索引服务。


再看一下退出的流程:

```go
func (n *Node) OnStop() {
  // 几乎所有的模块都实现了cmd.Server接口 n.BaseService.OnStop()是一个cmd的简单实现Server接口的实例 其实啥也没做
	n.BaseService.OnStop()
	// 索引服务关闭
	n.indexerService.Stop()

  // 这个比较重要 关闭所有的Reactor服务 区块链的各个模块服务在此处会被关闭掉
	n.sw.Stop()

	// 关闭rpc服务
	for _, l := range n.rpcListeners {
		n.Logger.Info("Closing rpc listener", "listener", l)
		if err := l.Close(); err != nil {
			n.Logger.Error("Error closing listener", "listener", l, "err", err)
		}
	}

  // privValidator 如果是通过socket进行验证器的获取 那么此处需要关闭socket
	if pvsc, ok := n.privValidator.(*privval.SocketPV); ok {
		if err := pvsc.Stop(); err != nil {
			n.Logger.Error("Error stopping priv validator socket client", "err", err)
		}
	}

}
```

整个Tendermint节点启动的流程大致就是这么多， 主要代码就在tendermint/node目录下。 在Tendermint中， 如果了解各个模块的工作内容， 差不多对整个流程的理解就没有什么太大的问题。
Tendermint的各个模块启动最后均是由Switch的启动引发的， 每个Reactor启动时同时也会自己模块的各个功能启动。 同样在退出时也是由Switch关闭，调用各个Reactor的Stop功能， 最后使Reactor对应的各个模块的功能关闭掉。











