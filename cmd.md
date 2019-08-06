# Cmd 
## File structure
|文件|package|说明|
|-----|----------|-----------------------------------------------------------------------------------|
|cmd  |	         |命令行工具，下面又分了很多的命令行工具|
|cmd  |abigen	将智能合约源代码转换成容易使用的，编译时类型安全的Go语言包|
|cmd  |bootnode	 |启动一个仅仅实现网络发现的节点|
|cmd  | checkpoint-admin|  checkpoint-admin is a utility that can be used to query checkpoint information and register stable checkpoints into an oracle contract.|
|cmd  |  clef    | Clef is an account management tool|
|cmd  | devp2p   | ethereum p2p tool|
|cmd  |  ethkey  | an Ethereum key manager|
|cmd  |	evm	 |以太坊虚拟机的开发工具， 用来提供一个可配置的，受隔离的代码调试环境|
|cmd  |	faucet	 |faucet is a Ether faucet backend by a light client.|
|cmd  |geth	 |以太坊命令行客户端，最重要的一个工具|
|cmd  |p2psim	 |提供了一个工具来模拟http的API|
|cmd  |puppeth	 |创建一个新的以太坊网络的向导,一个命令组装和维护私人网路|
|cmd  |rlpdump	 |提供了一个RLP数据的格式化输出|
|cmd  |swarm	 |swarm网络的接入点|
|cmd  |util	 |提供了一些公共的工具,为Go-Ethereum命令提供说明|
|cmd  |wnode     |这是一个简单的Whisper节点。 它可以用作独立的引导节点。此外，可以用于不同的测试和诊断目的。|

## Cmd/geth
geth是ｃｍｄ中最重要的命令，他是以太坊的入口。ｇｅｔｈ的命令行是通过ｕｒｆａｖｅ/cli这个库进行实现的，通过这个库，我们可以轻松定义命令行程序的子命令，命令选项，命令参数，描述信息等等。

geth 模块的入口在 cmd/geth/main.go 中，它会调用 urfave/cli 的中 app 的 run 方法，而 app 在 init 函数中初始化，在 Golang 中，如果有 init 方法，那么会在 main 函数之前执行 init 函数，它用于程序执行前的初始化工作。在 geth 模块中，init() 函数定义了命令行的入口是 geth，并且定义了 geth 的子命令、全局的命令选项、子命令的命令选项，按照 urfave/cli 的做法，不输入子命令会默认调用 geth，而 geth 方法其实就6行：
<pre><code>func geth(ctx *cli.Context) error {
	node := makeFullNode(ctx)
	startNode(ctx, node)
	node.Wait()
	return nil
}</code></pre>
它会调用 makeFullNode 函数初始化一个全节点，接着通过 startNode 函数启动一个全节点，以阻塞的方式运行，等待着节点被终止。
<pre><code>func makeFullNode(ctx *cli.Context) *node.Node {
	stack, cfg := makeConfigNode(ctx)
	utils.RegisterEthService(stack, &cfg.Eth)
	if ctx.GlobalBool(utils.DashboardEnabledFlag.Name) {
		utils.RegisterDashboardService(stack, &cfg.Dashboard, gitCommit)
	}
	// whether enable whisper ...
	// whether register eth stats ...
	return stack
}</code></pre>
makeFullNode核心的逻辑是首先通过配置文件和 flag 生成系统级的配置，然后将服务注入到节点。
<pre><code>func makeConfigNode(ctx *cli.Context) (*node.Node, gethConfig) {
	cfg := gethConfig{
		Eth:       eth.DefaultConfig,
		Shh:       whisper.DefaultConfig,
		Node:      defaultNodeConfig(),
		Dashboard: dashboard.DefaultConfig,
	}
	if file := ctx.GlobalString(configFileFlag.Name); file != "" {
		if err := loadConfig(file, &cfg); err != nil {
			utils.Fatalf("%v", err)
		}
	}
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
	utils.SetDashboardConfig(ctx, &cfg.Dashboard)
	return stack, cfg
}</code></pre>
makeConfigNode 会先载入默认配置，再载入配置文件中的配置，然后通过上下文的配置(在 cmd/geth/main.go 中的 init 方法中定义)进行设置。
<pre><code>func RegisterEthService(stack *node.Node, cfg *eth.Config) {
	var err error
	if cfg.SyncMode == downloader.LightSync {
		err = stack.Register(func(ctx *node.ServiceContext) (node.Service, error) {
			return les.New(ctx, cfg)
		})
	} else {
		err = stack.Register(func(ctx *node.ServiceContext) (node.Service, error) {
			fullNode, err := eth.New(ctx, cfg)
			if fullNode != nil && cfg.LightServ > 0 {
				ls, _ := les.NewLesServer(fullNode, cfg)
				fullNode.AddLesServer(ls)
			}
			return fullNode, err
		})
	}
	if err != nil {
		Fatalf("Failed to register the Ethereum service: %v", err)
	}
}</code></pre>
RegisterEthService 的代码在 cmd/utils/flags.go 中，如果同步模式是轻量级同步模式，启动轻量级客户端，否则启动全节点，实际的注册方法是 stack.Register。注入服务其实就是将新的服务注入到 node 对象的 serviceFuncs 数组中。
### geth/main.go
<pre><code>func startNode(ctx *cli.Context, stack *node.Node) {
	debug.Memsize.Add("node", stack)
	utils.StartNode(stack)
	ks := stack.AccountManager().Backends(keystore.KeyStoreType)[0].(*keystore.KeyStore)
	passwords := utils.MakePasswordList(ctx)
	unlocks := strings.Split(ctx.GlobalString(utils.UnlockedAccountFlag.Name), ",")
	for i, account := range unlocks {
		if trimmed := strings.TrimSpace(account); trimmed != "" {
			unlockAccount(ctx, ks, trimmed, i, passwords)
		}
	}
	events := make(chan accounts.WalletEvent, 16)
	stack.AccountManager().Subscribe(events)
	go func() {
		rpcClient, err := stack.Attach()
		if err != nil {
			utils.Fatalf("Failed to attach to self: %v", err)
		}
		stateReader := ethclient.NewClient(rpcClient)
		for _, wallet := range stack.AccountManager().Wallets() {
			if err := wallet.Open(""); err != nil {
				log.Warn("Failed to open wallet", "url", wallet.URL(), "err", err)
			}
		}
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
	if ctx.GlobalBool(utils.MiningEnabledFlag.Name) || ctx.GlobalBool(utils.DeveloperFlag.Name) {
		if ctx.GlobalBool(utils.LightModeFlag.Name) || ctx.GlobalString(utils.SyncModeFlag.Name) == "light" {
			utils.Fatalf("Light clients do not support mining")
		}
		var ethereum *eth.Ethereum
		if err := stack.Service(&ethereum); err != nil {
			utils.Fatalf("Ethereum service not running: %v", err)
		}
		if threads := ctx.GlobalInt(utils.MinerThreadsFlag.Name); threads > 0 {
			type threaded interface {
				SetThreads(threads int)
			}
			if th, ok := ethereum.Engine().(threaded); ok {
				th.SetThreads(threads)
			}
		}
		ethereum.TxPool().SetGasPrice(utils.GlobalBig(ctx, utils.GasPriceFlag.Name))
		if err := ethereum.StartMining(true); err != nil {
			utils.Fatalf("Failed to start mining: %v", err)
		}
	}
}</code></pre>
startNode 方法启动节点，会开启所有已经注册的协议，解锁请求的账户，开启 RPC/IPC 接口，并开始挖矿。
### geth/chaincmd.go
<pre><code>func initGenesis(ctx *cli.Context) error {
	genesisPath := ctx.Args().First()
	if len(genesisPath) == 0 {
		utils.Fatalf("Must supply path to genesis JSON file")
	}
	file, err := os.Open(genesisPath)
	if err != nil {
		utils.Fatalf("Failed to read genesis file: %v", err)
	}
	defer file.Close()
	genesis := new(core.Genesis)
	if err := json.NewDecoder(file).Decode(genesis); err != nil {
		utils.Fatalf("invalid genesis file: %v", err)
	}
	stack := makeFullNode(ctx)
	for _, name := range []string{"chaindata", "lightchaindata"} {
		chaindb, err := stack.OpenDatabase(name, 0, 0)
		if err != nil {
			utils.Fatalf("Failed to open database: %v", err)
		}
		_, hash, err := core.SetupGenesisBlock(chaindb, genesis)
		if err != nil {
			utils.Fatalf("Failed to write genesis block: %v", err)
		}
		log.Info("Successfully wrote genesis state", "database", name, "hash", hash)
	}
	return nil
}</code></pre>
initCommand会进行初始化，生成初始区块，调用了ＳｅｔｕｐGenesisBlock
<pre><code>func importChain(ctx *cli.Context) error {
	if len(ctx.Args()) < 1 {
		utils.Fatalf("This command requires an argument.")
	}
	stack := makeFullNode(ctx)
	chain, chainDb := utils.MakeChain(ctx, stack)
	defer chainDb.Close()
	var peakMemAlloc, peakMemSys uint64
	go func() {
		stats := new(runtime.MemStats)
		for {
			runtime.ReadMemStats(stats)
			if atomic.LoadUint64(&peakMemAlloc) < stats.Alloc {
				atomic.StoreUint64(&peakMemAlloc, stats.Alloc)
			}
			if atomic.LoadUint64(&peakMemSys) < stats.Sys {
				atomic.StoreUint64(&peakMemSys, stats.Sys)
			}
			time.Sleep(5 * time.Second)
		}
	}()
	start := time.Now()
	if len(ctx.Args()) == 1 {
		if err := utils.ImportChain(chain, ctx.Args().First()); err != nil {
			log.Error("Import error", "err", err)
		}
	} else {
		for _, arg := range ctx.Args() {
			if err := utils.ImportChain(chain, arg); err != nil {
				log.Error("Import error", "file", arg, "err", err)
			}
		}
	}
	chain.Stop()
	fmt.Printf("Import done in %v.\n\n", time.Since(start))
	db := chainDb.(*ethdb.LDBDatabase)
	stats, err := db.LDB().GetProperty("leveldb.stats")
	if err != nil {
		utils.Fatalf("Failed to read database stats: %v", err)
	}
	fmt.Println(stats)
	ioStats, err := db.LDB().GetProperty("leveldb.iostats")
	if err != nil {
		utils.Fatalf("Failed to read database iostats: %v", err)
	}
	fmt.Println(ioStats)
	fmt.Printf("Trie cache misses:  %d\n", trie.CacheMisses())
	fmt.Printf("Trie cache unloads: %d\n\n", trie.CacheUnloads())
	mem := new(runtime.MemStats)
	runtime.ReadMemStats(mem)
	fmt.Printf("Object memory: %.3f MB current, %.3f MB peak\n", float64(mem.Alloc)/1024/1024, float64(atomic.LoadUint64(&peakMemAlloc))/1024/1024)
	fmt.Printf("System memory: %.3f MB current, %.3f MB peak\n", float64(mem.Sys)/1024/1024, float64(atomic.LoadUint64(&peakMemSys))/1024/1024)
	fmt.Printf("Allocations:   %.3f million\n", float64(mem.Mallocs)/1000000)
	fmt.Printf("GC pause:      %v\n\n", time.Duration(mem.PauseTotalNs))
	if ctx.GlobalIsSet(utils.NoCompactionFlag.Name) {
		return nil
	}
	start = time.Now()
	fmt.Println("Compacting entire database...")
	if err = db.LDB().CompactRange(util.Range{}); err != nil {
		utils.Fatalf("Compaction failed: %v", err)
	}
	fmt.Printf("Compaction done in %v.\n\n", time.Since(start))
	stats, err = db.LDB().GetProperty("leveldb.stats")
	if err != nil {
		utils.Fatalf("Failed to read database stats: %v", err)
	}
	fmt.Println(stats)
	ioStats, err = db.LDB().GetProperty("leveldb.iostats")
	if err != nil {
		utils.Fatalf("Failed to read database iostats: %v", err)
	}
	fmt.Println(ioStats)
	return nil
}</code></pre>
ImportChain导入了一个区块链文件
<pre><code>func exportChain(ctx *cli.Context) error {
	if len(ctx.Args()) < 1 {
		utils.Fatalf("This command requires an argument.")
	}
	stack := makeFullNode(ctx)
	chain, _ := utils.MakeChain(ctx, stack)
	start := time.Now()
	var err error
	fp := ctx.Args().First()
	if len(ctx.Args()) < 3 {
		err = utils.ExportChain(chain, fp)
	} else {
		first, ferr := strconv.ParseInt(ctx.Args().Get(1), 10, 64)
		last, lerr := strconv.ParseInt(ctx.Args().Get(2), 10, 64)
		if ferr != nil || lerr != nil {
			utils.Fatalf("Export error in parsing parameters: block number not an integer\n")
		}
		if first < 0 || last < 0 {
			utils.Fatalf("Export error: block number must be greater than 0\n")
		}
		err = utils.ExportAppendChain(chain, fp, uint64(first), uint64(last))
	}
	if err != nil {
		utils.Fatalf("Export error: %v\n", err)
	}
	fmt.Printf("Export done in %v\n", time.Since(start))
	return nil
}</code></pre>
ｅｘｐｏｒｔCommand导出一个区块链ｇｚ文件
<pre><code>func importPreimages(ctx *cli.Context) error {
	if len(ctx.Args()) < 1 {
		utils.Fatalf("This command requires an argument.")
	}
	stack := makeFullNode(ctx)
	diskdb := utils.MakeChainDatabase(ctx, stack).(*ethdb.LDBDatabase)
	start := time.Now()
	if err := utils.ImportPreimages(diskdb, ctx.Args().First()); err != nil {
		utils.Fatalf("Export error: %v\n", err)
	}
	fmt.Printf("Export done in %v\n", time.Since(start))
	return nil
}</code></pre>
将一个ｐｒｅｉｍａｇｅｓ导入当前节点
<pre><code>func exportPreimages(ctx *cli.Context) error {
	if len(ctx.Args()) < 1 {
		utils.Fatalf("This command requires an argument.")
	}
	stack := makeFullNode(ctx)
	diskdb := utils.MakeChainDatabase(ctx, stack).(*ethdb.LDBDatabase)
	start := time.Now()
	if err := utils.ExportPreimages(diskdb, ctx.Args().First()); err != nil {
		utils.Fatalf("Export error: %v\n", err)
	}
	fmt.Printf("Export done in %v\n", time.Since(start))
	return nil
}</code></pre>
从当前节点导出一个 image
<pre><code>func copyDb(ctx *cli.Context) error {
	if len(ctx.Args()) != 1 {
		utils.Fatalf("Source chaindata directory path argument missing")
	}
	stack := makeFullNode(ctx)
	chain, chainDb := utils.MakeChain(ctx, stack)
	syncmode := *utils.GlobalTextMarshaler(ctx, utils.SyncModeFlag.Name).(*downloader.SyncMode)
	dl := downloader.New(syncmode, chainDb, new(event.TypeMux), chain, nil, nil)
	db, err := ethdb.NewLDBDatabase(ctx.Args().First(), ctx.GlobalInt(utils.CacheFlag.Name), 256)
	if err != nil {
		return err
	}
	hc, err := core.NewHeaderChain(db, chain.Config(), chain.Engine(), func() bool { return false })
	if err != nil {
		return err
	}
	peer := downloader.NewFakePeer("local", db, hc, dl)
	if err = dl.RegisterPeer("local", 63, peer); err != nil {
		return err
	}
	start := time.Now()
	currentHeader := hc.CurrentHeader()
	if err = dl.Synchronise("local", currentHeader.Hash(), hc.GetTd(currentHeader.Hash(), currentHeader.Number.Uint64()), syncmode); err != nil {
		return err
	}
	for dl.Synchronising() {
		time.Sleep(10 * time.Millisecond)
	}
	fmt.Printf("Database copy done in %v\n", time.Since(start))
	start = time.Now()
	fmt.Println("Compacting entire database...")
	if err = chainDb.(*ethdb.LDBDatabase).LDB().CompactRange(util.Range{}); err != nil {
		utils.Fatalf("Compaction failed: %v", err)
	}
	fmt.Printf("Compaction done in %v.\n\n", time.Since(start))
	return nil
}</code></pre>
复制一个本地区块文件到文件夹;在一个文件夹中创建一个本地区块链,但是这个过程并不是直接复制过去的，而是通过 downloader 模块里的 NewFakePeer 创建一个虚拟对等节点，然后再进行数据同步完成的。
<pre><code>func removeDB(ctx *cli.Context) error {
	stack, _ := makeConfigNode(ctx)
	for _, name := range []string{"chaindata", "lightchaindata"} {
		logger := log.New("database", name)
		dbdir := stack.ResolvePath(name)
		if !common.FileExist(dbdir) {
			logger.Info("Database doesn't exist, skipping", "path", dbdir)
			continue
		}
		fmt.Println(dbdir)
		confirm, err := console.Stdin.PromptConfirm("Remove this database?")
		switch {
		case err != nil:
			utils.Fatalf("%v", err)
		case !confirm:
			logger.Warn("Database deletion aborted")
		default:
			start := time.Now()
			os.RemoveAll(dbdir)
			logger.Info("Database successfully deleted", "elapsed", common.PrettyDuration(time.Since(start)))
		}
	}
	return nil
}</code></pre>
在当前数据库中移除区块链,删除数据库是直接通过 os 模块移除这个文件夹。
<pre><code>func dump(ctx *cli.Context) error {
	stack := makeFullNode(ctx)
	chain, chainDb := utils.MakeChain(ctx, stack)
	for _, arg := range ctx.Args() {
		var block *types.Block
		if hashish(arg) {
			block = chain.GetBlockByHash(common.HexToHash(arg))
		} else {
			num, _ := strconv.Atoi(arg)
			block = chain.GetBlockByNumber(uint64(num))
		}
		if block == nil {
			fmt.Println("{}")
			utils.Fatalf("block not found")
		} else {
			state, err := state.New(block.Root(), state.NewDatabase(chainDb))
			if err != nil {
				utils.Fatalf("could not create new state: %v", err)
			}
			fmt.Printf("%s\n", state.Dump())
		}
	}
	chainDb.Close()
	return nil
}</code></pre>
dump 子命令可以移除一个或多个特定的区块,先根据区块号获取区块，然后调用 state 的 Dump 移除即可

### geth/accountCommand.go
这部分主要是管理账户
<pre><code>func accountList(ctx *cli.Context) error {
	stack, _ := makeConfigNode(ctx)
	var index int
	for _, wallet := range stack.AccountManager().Wallets() {
		for _, account := range wallet.Accounts() {
			fmt.Printf("Account #%d: {%x} %s\n", index, account.Address, &account.URL)
			index++
		}
	}
	return nil
}</code></pre>
拿到ｗａｌｌｅｔｓ中的所有账户
<pre><code>func accountCreate(ctx *cli.Context) error {
	cfg := gethConfig{Node: defaultNodeConfig()}
	if file := ctx.GlobalString(configFileFlag.Name); file != "" {
		if err := loadConfig(file, &cfg); err != nil {
			utils.Fatalf("%v", err)
		}
	}
	utils.SetNodeConfig(ctx, &cfg.Node)
	scryptN, scryptP, keydir, err := cfg.Node.AccountConfig()
	if err != nil {
		utils.Fatalf("Failed to read configuration: %v", err)
	}
	password := getPassPhrase("Your new account is locked with a password. Please give a password. Do not forget this password.", true, 0, utils.MakePasswordList(ctx))
	address, err := keystore.StoreKey(keydir, password, scryptN, scryptP)
	if err != nil {
		utils.Fatalf("Failed to create account: %v", err)
	}
	fmt.Printf("Address: {%x}\n", address)
	return nil
}</code></pre>
创建一个账户，成功后输出地址
<pre><code>func accountUpdate(ctx *cli.Context) error {
	if len(ctx.Args()) == 0 {
		utils.Fatalf("No accounts specified to update")
	}
	stack, _ := makeConfigNode(ctx)
	ks := stack.AccountManager().Backends(keystore.KeyStoreType)[0].(*keystore.KeyStore)
	for _, addr := range ctx.Args() {
		account, oldPassword := unlockAccount(ctx, ks, addr, 0, nil)
		newPassword := getPassPhrase("Please give a new password. Do not forget this password.", true, 0, nil)
		if err := ks.Update(account, oldPassword, newPassword); err != nil {
			utils.Fatalf("Could not update the account: %v", err)
		}
	}
	return nil
}</code></pre>
先通过 AccountManager 拿到 keystore，然后调用 Update 更新密码
<pre><code>func accountImport(ctx *cli.Context) error {
	keyfile := ctx.Args().First()
	if len(keyfile) == 0 {
		utils.Fatalf("keyfile must be given as argument")
	}
	key, err := crypto.LoadECDSA(keyfile)
	if err != nil {
		utils.Fatalf("Failed to load the private key: %v", err)
	}
	stack, _ := makeConfigNode(ctx)
	passphrase := getPassPhrase("Your new account is locked with a password. Please give a password. Do not forget this password.", true, 0, utils.MakePasswordList(ctx))
	ks := stack.AccountManager().Backends(keystore.KeyStoreType)[0].(*keystore.KeyStore)
	acct, err := ks.ImportECDSA(key, passphrase)
	if err != nil {
		utils.Fatalf("Could not create the account: %v", err)
	}
	fmt.Printf("Address: {%x}\n", acct.Address)
	return nil
}</code></pre>
先通过 AccountManager 拿到 keystore，调用 ImportPreSaleKey 导入账户

### geth/consolecmd.go
<pre><code>func localConsole(ctx *cli.Context) error {
	node := makeFullNode(ctx)
	startNode(ctx, node)
	defer node.Stop()
	client, err := node.Attach()
	if err != nil {
		utils.Fatalf("Failed to attach to the inproc geth: %v", err)
	}
	config := console.Config{
		DataDir: utils.MakeDataDir(ctx),
		DocRoot: ctx.GlobalString(utils.JSpathFlag.Name),
		Client:  client,
		Preload: utils.MakeConsolePreloads(ctx),
	}
	console, err := console.New(config)
	if err != nil {
		utils.Fatalf("Failed to start the JavaScript console: %v", err)
	}
	defer console.Stop(false)
	if script := ctx.GlobalString(utils.ExecFlag.Name); script != "" {
		console.Evaluate(script)
		return nil
	}
	console.Welcome()
	console.Interactive()
	return nil
}</code></pre>
启动本地的一个交互式 Javascript 环境，功能是通过 console 模块提供的，而 console 模块是对 robertkrimen/otto 的一个封装。otto 是一个 Golang 实现的 Javascript 解释器，可以实现在 Golang 中执行 Javascript，并且可以让在虚拟机里的 Javascript 调用 Golang 函数，实现 Golang 和 Javascript 的相互操作
<pre><code>func remoteConsole(ctx *cli.Context) error {
	endpoint := ctx.Args().First()
	if endpoint == "" {
		path := node.DefaultDataDir()
		if ctx.GlobalIsSet(utils.DataDirFlag.Name) {
			path = ctx.GlobalString(utils.DataDirFlag.Name)
		}
		if path != "" {
			if ctx.GlobalBool(utils.TestnetFlag.Name) {
				path = filepath.Join(path, "testnet")
			} else if ctx.GlobalBool(utils.RinkebyFlag.Name) {
				path = filepath.Join(path, "rinkeby")
			}
		}
		endpoint = fmt.Sprintf("%s/geth.ipc", path)
	}
	client, err := dialRPC(endpoint)
	if err != nil {
		utils.Fatalf("Unable to attach to remote geth: %v", err)
	}
	config := console.Config{
		DataDir: utils.MakeDataDir(ctx),
		DocRoot: ctx.GlobalString(utils.JSpathFlag.Name),
		Client:  client,
		Preload: utils.MakeConsolePreloads(ctx),
	}
	console, err := console.New(config)
	if err != nil {
		utils.Fatalf("Failed to start the JavaScript console: %v", err)
	}
	defer console.Stop(false)
	if script := ctx.GlobalString(utils.ExecFlag.Name); script != "" {
		console.Evaluate(script)
		return nil
	}
	console.Welcome()
	console.Interactive()
	return nil
}</code></pre>
启动一个 JS 交互式环境(连接到节点),通过指定 endpoint 的方式，连接到某个节点的交互式 Javascript 环境
<pre><code>func ephemeralConsole(ctx *cli.Context) error {
	node := makeFullNode(ctx)
	startNode(ctx, node)
	defer node.Stop()
	client, err := node.Attach()
	if err != nil {
		utils.Fatalf("Failed to attach to the inproc geth: %v", err)
	}
	config := console.Config{
		DataDir: utils.MakeDataDir(ctx),
		DocRoot: ctx.GlobalString(utils.JSpathFlag.Name),
		Client:  client,
		Preload: utils.MakeConsolePreloads(ctx),
	}
	console, err := console.New(config)
	if err != nil {
		utils.Fatalf("Failed to start the JavaScript console: %v", err)
	}
	defer console.Stop(false)
	for _, file := range ctx.Args() {
		if err = console.Execute(file); err != nil {
			utils.Fatalf("Failed to execute %s: %v", file, err)
		}
	}
	abort := make(chan os.Signal, 1)
	signal.Notify(abort, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-abort
		os.Exit(0)
	}()
	console.Stop(true)
	return nil
}</code></pre>
执行 Javascript 文件中的命令(可以为多个文件),通过遍历调用传输的文件路径，执行 console.Execute，执行 js 命令。

### geth/misccmd.go
<pre><code>func makecache(ctx *cli.Context) error {
	args := ctx.Args()
	if len(args) != 2 {
		utils.Fatalf(`Usage: geth makecache <block number> <outputdir>`)
	}
	block, err := strconv.ParseUint(args[0], 0, 64)
	if err != nil {
		utils.Fatalf("Invalid block number: %v", err)
	}
	ethash.MakeCache(block, args[1])
	return nil
}</code></pre>
生成 ethash 的验证缓存
<pre><code>func makedag(ctx *cli.Context) error {
	args := ctx.Args()
	if len(args) != 2 {
		utils.Fatalf(`Usage: geth makedag <block number> <outputdir>`)
	}
	block, err := strconv.ParseUint(args[0], 0, 64)
	if err != nil {
		utils.Fatalf("Invalid block number: %v", err)
	}
	ethash.MakeDataset(block, args[1])
	return nil
}</code></pre>
通过调用 ethash 的 MakeDataset，生成挖矿需要的 DAG 数据集
- versionCommand: 输出版本号
- bugCommand: 给 https://github.com/ethereum/go-ethereum/issues/new 这个 url 拼接参数，给源代码仓库提一个 issue
- licenseCommand: 输出 License 信息

### geth/config.go
<pre><code>func dumpConfig(ctx *cli.Context) error {
	_, cfg := makeConfigNode(ctx)
	comment := ""
	if cfg.Eth.Genesis != nil {
		cfg.Eth.Genesis = nil
		comment += "# Note: this config doesn't contain the genesis block.\n\n"
	}
	out, err := tomlSettings.Marshal(&cfg)
	if err != nil {
		return err
	}
	io.WriteString(os.Stdout, comment)
	os.Stdout.Write(out)
	return nil
}</code></pre>
dumpConfig 函数通过 makeConfigNode 获取配置，然后将其输出在屏幕
