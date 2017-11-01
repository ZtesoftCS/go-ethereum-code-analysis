geth是我们的go-ethereum最主要的一个命令行工具。 也是我们的各种网络的接入点(主网络main-net 测试网络test-net 和私有网络)。支持运行在全节点模式或者轻量级节点模式。 其他程序可以通过它暴露的JSON RPC调用来访问以太坊网络的功能。

如果什么命令都不输入直接运行geth。 就会默认启动一个全节点模式的节点。 连接到主网络。 我们看看启动的主要流程是什么，涉及到了那些组件。


## 启动的main函数  cmd/geth/main.go
看到main函数一上来就直接运行了。 最开始看的时候是有点懵逼的。 后面发现go语言里面有两个默认的函数，一个是main()函数。一个是init()函数。 go语言会自动按照一定的顺序先调用所有包的init()函数。然后才会调用main()函数。 

	func main() {
		if err := app.Run(os.Args); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}
	

main.go的init函数
app是一个三方包gopkg.in/urfave/cli.v1的实例。 这个三方包的用法大致就是首先构造这个app对象。 通过代码配置app对象的行为，提供一些回调函数。然后运行的时候直接在main函数里面运行 app.Run(os.Args)就行了。

	import (
		...
		"gopkg.in/urfave/cli.v1"
	)

	var (

		app = utils.NewApp(gitCommit, "the go-ethereum command line interface")
		// flags that configure the node
		nodeFlags = []cli.Flag{
			utils.IdentityFlag,
			utils.UnlockedAccountFlag,
			utils.PasswordFileFlag,
			utils.BootnodesFlag,
			...
		}
	
		rpcFlags = []cli.Flag{
			utils.RPCEnabledFlag,
			utils.RPCListenAddrFlag,
			...
		}
	
		whisperFlags = []cli.Flag{
			utils.WhisperEnabledFlag,
			...
		}
	)
	func init() {
		// Initialize the CLI app and start Geth
		// Action字段表示如果用户没有输入其他的子命令的情况下，会调用这个字段指向的函数。
		app.Action = geth
		app.HideVersion = true // we have a command to print the version
		app.Copyright = "Copyright 2013-2017 The go-ethereum Authors"
		// Commands 是所有支持的子命令
		app.Commands = []cli.Command{
			// See chaincmd.go:
			initCommand,
			importCommand,
			exportCommand,
			removedbCommand,
			dumpCommand,
			// See monitorcmd.go:
			monitorCommand,
			// See accountcmd.go:
			accountCommand,
			walletCommand,
			// See consolecmd.go:
			consoleCommand,
			attachCommand,
			javascriptCommand,
			// See misccmd.go:
			makecacheCommand,
			makedagCommand,
			versionCommand,
			bugCommand,
			licenseCommand,
			// See config.go
			dumpConfigCommand,
		}
		sort.Sort(cli.CommandsByName(app.Commands))
		// 所有能够解析的Options
		app.Flags = append(app.Flags, nodeFlags...)
		app.Flags = append(app.Flags, rpcFlags...)
		app.Flags = append(app.Flags, consoleFlags...)
		app.Flags = append(app.Flags, debug.Flags...)
		app.Flags = append(app.Flags, whisperFlags...)
	
		app.Before = func(ctx *cli.Context) error {
			runtime.GOMAXPROCS(runtime.NumCPU())
			if err := debug.Setup(ctx); err != nil {
				return err
			}
			// Start system runtime metrics collection
			go metrics.CollectProcessMetrics(3 * time.Second)
	
			utils.SetupNetwork(ctx)
			return nil
		}
	
		app.After = func(ctx *cli.Context) error {
			debug.Exit()
			console.Stdin.Close() // Resets terminal mode.
			return nil
		}
	}

如果我们没有输入任何的参数，那么会自动调用geth方法。

	// geth is the main entry point into the system if no special subcommand is ran.
	// It creates a default node based on the command line arguments and runs it in
	// blocking mode, waiting for it to be shut down.
	// 如果没有指定特殊的子命令，那么geth是系统主要的入口。
	// 它会根据提供的参数创建一个默认的节点。并且以阻塞的模式运行这个节点，等待着节点被终止。
	func geth(ctx *cli.Context) error {
		node := makeFullNode(ctx)
		startNode(ctx, node)
		node.Wait()
		return nil
	}

makeFullNode函数，
	
	func makeFullNode(ctx *cli.Context) *node.Node {
		// 根据命令行参数和一些特殊的配置来创建一个node
		stack, cfg := makeConfigNode(ctx)
		// 把eth的服务注册到这个节点上面。 eth服务是以太坊的主要的服务。 是以太坊功能的提供者。
		utils.RegisterEthService(stack, &cfg.Eth)
	
		// Whisper must be explicitly enabled by specifying at least 1 whisper flag or in dev mode
		// Whisper是一个新的模块，用来进行加密通讯的功能。 需要显式的提供参数来启用，或者是处于开发模式。
		shhEnabled := enableWhisper(ctx)
		shhAutoEnabled := !ctx.GlobalIsSet(utils.WhisperEnabledFlag.Name) && ctx.GlobalIsSet(utils.DevModeFlag.Name)
		if shhEnabled || shhAutoEnabled {
			if ctx.GlobalIsSet(utils.WhisperMaxMessageSizeFlag.Name) {
				cfg.Shh.MaxMessageSize = uint32(ctx.Int(utils.WhisperMaxMessageSizeFlag.Name))
			}
			if ctx.GlobalIsSet(utils.WhisperMinPOWFlag.Name) {
				cfg.Shh.MinimumAcceptedPOW = ctx.Float64(utils.WhisperMinPOWFlag.Name)
			}
			// 注册Shh服务
			utils.RegisterShhService(stack, &cfg.Shh)
		}
	
		// Add the Ethereum Stats daemon if requested.
		if cfg.Ethstats.URL != "" {
			// 注册 以太坊的状态服务。 默认情况下是没有启动的。
			utils.RegisterEthStatsService(stack, cfg.Ethstats.URL)
		}
	
		// Add the release oracle service so it boots along with node.
		// release oracle服务是用来查看客户端版本是否是最新版本的服务。
		// 如果需要更新。 那么会通过打印日志来提示版本更新。
		// release 是通过智能合约的形式来运行的。 后续会详细讨论这个服务。
		if err := stack.Register(func(ctx *node.ServiceContext) (node.Service, error) {
			config := release.Config{
				Oracle: relOracle,
				Major:  uint32(params.VersionMajor),
				Minor:  uint32(params.VersionMinor),
				Patch:  uint32(params.VersionPatch),
			}
			commit, _ := hex.DecodeString(gitCommit)
			copy(config.Commit[:], commit)
			return release.NewReleaseService(ctx, config)
		}); err != nil {
			utils.Fatalf("Failed to register the Geth release oracle service: %v", err)
		}
		return stack
	}

makeConfigNode。 这个函数主要是通过配置文件和flag来生成整个系统的运行配置。
	
	func makeConfigNode(ctx *cli.Context) (*node.Node, gethConfig) {
		// Load defaults.
		cfg := gethConfig{
			Eth:  eth.DefaultConfig,
			Shh:  whisper.DefaultConfig,
			Node: defaultNodeConfig(),
		}
	
		// Load config file.
		if file := ctx.GlobalString(configFileFlag.Name); file != "" {
			if err := loadConfig(file, &cfg); err != nil {
				utils.Fatalf("%v", err)
			}
		}
	
		// Apply flags.
		utils.SetNodeConfig(ctx, &cfg.Node)
		stack, err := node.New(&cfg.Node)
		if err != nil {
			utils.Fatalf("Failed to create the protocol stack: %v", err)
		}
		utils.SetEthConfig(ctx, stack, &cfg.Eth)
		if ctx.GlobalIsSet(utils.EthStatsURLFlag.Name) {
			cfg.Ethstats.URL = ctx.GlobalString(utils.EthStatsURLFlag.Name)
		}
	
		utils.SetShhConfig(ctx, stack, &cfg.Shh)
	
		return stack, cfg
	}

RegisterEthService

	// RegisterEthService adds an Ethereum client to the stack.
	func RegisterEthService(stack *node.Node, cfg *eth.Config) {
		var err error
		// 如果同步模式是轻量级的同步模式。 那么启动轻量级的客户端。
		if cfg.SyncMode == downloader.LightSync {
			err = stack.Register(func(ctx *node.ServiceContext) (node.Service, error) {
				return les.New(ctx, cfg)
			})
		} else {
			// 否则会启动全节点
			err = stack.Register(func(ctx *node.ServiceContext) (node.Service, error) {
				fullNode, err := eth.New(ctx, cfg)
				if fullNode != nil && cfg.LightServ > 0 {
					// 默认LightServ的大小是0 也就是不会启动LesServer
					// LesServer是给轻量级节点提供服务的。
					ls, _ := les.NewLesServer(fullNode, cfg)
					fullNode.AddLesServer(ls)
				}
				return fullNode, err
			})
		}
		if err != nil {
			Fatalf("Failed to register the Ethereum service: %v", err)
		}
	}


startNode

	// startNode boots up the system node and all registered protocols, after which
	// it unlocks any requested accounts, and starts the RPC/IPC interfaces and the
	// miner.
	func startNode(ctx *cli.Context, stack *node.Node) {
		// Start up the node itself
		utils.StartNode(stack)
	
		// Unlock any account specifically requested
		ks := stack.AccountManager().Backends(keystore.KeyStoreType)[0].(*keystore.KeyStore)
	
		passwords := utils.MakePasswordList(ctx)
		unlocks := strings.Split(ctx.GlobalString(utils.UnlockedAccountFlag.Name), ",")
		for i, account := range unlocks {
			if trimmed := strings.TrimSpace(account); trimmed != "" {
				unlockAccount(ctx, ks, trimmed, i, passwords)
			}
		}
		// Register wallet event handlers to open and auto-derive wallets
		events := make(chan accounts.WalletEvent, 16)
		stack.AccountManager().Subscribe(events)
	
		go func() {
			// Create an chain state reader for self-derivation
			rpcClient, err := stack.Attach()
			if err != nil {
				utils.Fatalf("Failed to attach to self: %v", err)
			}
			stateReader := ethclient.NewClient(rpcClient)
	
			// Open any wallets already attached
			for _, wallet := range stack.AccountManager().Wallets() {
				if err := wallet.Open(""); err != nil {
					log.Warn("Failed to open wallet", "url", wallet.URL(), "err", err)
				}
			}
			// Listen for wallet event till termination
			for event := range events {
				switch event.Kind {
				case accounts.WalletArrived:
					if err := event.Wallet.Open(""); err != nil {
						log.Warn("New wallet appeared, failed to open", "url", event.Wallet.URL(), "err", err)
					}
				case accounts.WalletOpened:
					status, _ := event.Wallet.Status()
					log.Info("New wallet appeared", "url", event.Wallet.URL(), "status", status)
	
					if event.Wallet.URL().Scheme == "ledger" {
						event.Wallet.SelfDerive(accounts.DefaultLedgerBaseDerivationPath, stateReader)
					} else {
						event.Wallet.SelfDerive(accounts.DefaultBaseDerivationPath, stateReader)
					}
	
				case accounts.WalletDropped:
					log.Info("Old wallet dropped", "url", event.Wallet.URL())
					event.Wallet.Close()
				}
			}
		}()
		// Start auxiliary services if enabled
		if ctx.GlobalBool(utils.MiningEnabledFlag.Name) {
			// Mining only makes sense if a full Ethereum node is running
			var ethereum *eth.Ethereum
			if err := stack.Service(&ethereum); err != nil {
				utils.Fatalf("ethereum service not running: %v", err)
			}
			// Use a reduced number of threads if requested
			if threads := ctx.GlobalInt(utils.MinerThreadsFlag.Name); threads > 0 {
				type threaded interface {
					SetThreads(threads int)
				}
				if th, ok := ethereum.Engine().(threaded); ok {
					th.SetThreads(threads)
				}
			}
			// Set the gas price to the limits from the CLI and start mining
			ethereum.TxPool().SetGasPrice(utils.GlobalBig(ctx, utils.GasPriceFlag.Name))
			if err := ethereum.StartMining(true); err != nil {
				utils.Fatalf("Failed to start mining: %v", err)
			}
		}
	}

总结:

整个启动过程其实就是解析参数。然后创建和启动节点。 然后把服务注入到节点中。 所有跟以太坊相关的功能都是以服务的形式实现的。 


如果除开所有注册进去的服务。 这个时候系统开启的goroutine有哪些。 这里做一个总结。


目前所有的常驻的goroutine有下面一些。  主要是p2p相关的服务。 以及RPC相关的服务。

![image](picture/geth_1.png)

