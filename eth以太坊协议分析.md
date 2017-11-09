
node中的服务的定义， eth其实就是实现了一个服务。

	type Service interface {
		// Protocols retrieves the P2P protocols the service wishes to start.
		Protocols() []p2p.Protocol
	
		// APIs retrieves the list of RPC descriptors the service provides
		APIs() []rpc.API
	
		// Start is called after all services have been constructed and the networking
		// layer was also initialized to spawn any goroutines required by the service.
		Start(server *p2p.Server) error
	
		// Stop terminates all goroutines belonging to the service, blocking until they
		// are all terminated.
		Stop() error
	}

go ethereum 的eth目录是以太坊服务的实现。 以太坊协议是通过node的Register方法注入的。


	// RegisterEthService adds an Ethereum client to the stack.
	func RegisterEthService(stack *node.Node, cfg *eth.Config) {
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
	}

以太坊协议的数据结构
	
	// Ethereum implements the Ethereum full node service.
	type Ethereum struct {
		config      *Config					配置
		chainConfig *params.ChainConfig		链配置
	
		// Channel for shutting down the service
		shutdownChan  chan bool    // Channel for shutting down the ethereum
		stopDbUpgrade func() error // stop chain db sequential key upgrade
	
		// Handlers
		txPool          *core.TxPool			交易池
		blockchain      *core.BlockChain		区块链
		protocolManager *ProtocolManager		协议管理
		lesServer       LesServer				轻量级客户端服务器
	
		// DB interfaces
		chainDb ethdb.Database // Block chain database	区块链数据库
	
		eventMux       *event.TypeMux
		engine         consensus.Engine				一致性引擎。 应该是Pow部分
		accountManager *accounts.Manager			账号管理
	
		bloomRequests chan chan *bloombits.Retrieval // Channel receiving bloom data retrieval requests	接收bloom过滤器数据请求的通道
		bloomIndexer  *core.ChainIndexer             // Bloom indexer operating during block imports  //在区块import的时候执行Bloom indexer操作 暂时不清楚是什么
	
		ApiBackend *EthApiBackend		//提供给RPC服务使用的API后端
	
		miner     *miner.Miner			//矿工
		gasPrice  *big.Int				//节点接收的gasPrice的最小值。 比这个值更小的交易会被本节点拒绝
		etherbase common.Address		//矿工地址
	
		networkId     uint64			//网络ID  testnet是0 mainnet是1 
		netRPCService *ethapi.PublicNetAPI	//RPC的服务
	
		lock sync.RWMutex // Protects the variadic fields (e.g. gas price and etherbase)
	}

以太坊协议的创建New. 暂时先不涉及core的内容。 只是大概介绍一下。 core里面的内容后续会分析。

	// New creates a new Ethereum object (including the
	// initialisation of the common Ethereum object)
	func New(ctx *node.ServiceContext, config *Config) (*Ethereum, error) {
		if config.SyncMode == downloader.LightSync {
			return nil, errors.New("can't run eth.Ethereum in light sync mode, use les.LightEthereum")
		}
		if !config.SyncMode.IsValid() {
			return nil, fmt.Errorf("invalid sync mode %d", config.SyncMode)
		}
		// 创建leveldb。 打开或者新建 chaindata目录
		chainDb, err := CreateDB(ctx, config, "chaindata")
		if err != nil {
			return nil, err
		}
		// 数据库格式升级
		stopDbUpgrade := upgradeDeduplicateData(chainDb)
		// 设置创世区块。 如果数据库里面已经有创世区块那么从数据库里面取出(私链)。或者是从代码里面获取默认值。
		chainConfig, genesisHash, genesisErr := core.SetupGenesisBlock(chainDb, config.Genesis)
		if _, ok := genesisErr.(*params.ConfigCompatError); genesisErr != nil && !ok {
			return nil, genesisErr
		}
		log.Info("Initialised chain configuration", "config", chainConfig)
	
		eth := &Ethereum{
			config:         config,
			chainDb:        chainDb,
			chainConfig:    chainConfig,
			eventMux:       ctx.EventMux,
			accountManager: ctx.AccountManager,
			engine:         CreateConsensusEngine(ctx, config, chainConfig, chainDb), // 一致性引擎。 这里我理解是Pow
			shutdownChan:   make(chan bool),
			stopDbUpgrade:  stopDbUpgrade,
			networkId:      config.NetworkId,  // 网络ID用来区别网路。 测试网络是0.主网是1
			gasPrice:       config.GasPrice,   // 可以通过配置 --gasprice 客户端接纳的交易的gasprice最小值。如果小于这个值那么会被节点丢弃。 
			etherbase:      config.Etherbase,  //挖矿的受益者
			bloomRequests:  make(chan chan *bloombits.Retrieval),  //bloom的请求
			bloomIndexer:   NewBloomIndexer(chainDb, params.BloomBitsBlocks),
		}
	
		log.Info("Initialising Ethereum protocol", "versions", ProtocolVersions, "network", config.NetworkId)
	
		if !config.SkipBcVersionCheck { // 检查数据库里面存储的BlockChainVersion和客户端的BlockChainVersion的版本是否一致
			bcVersion := core.GetBlockChainVersion(chainDb)
			if bcVersion != core.BlockChainVersion && bcVersion != 0 {
				return nil, fmt.Errorf("Blockchain DB version mismatch (%d / %d). Run geth upgradedb.\n", bcVersion, core.BlockChainVersion)
			}
			core.WriteBlockChainVersion(chainDb, core.BlockChainVersion)
		}
	
		vmConfig := vm.Config{EnablePreimageRecording: config.EnablePreimageRecording}
		// 使用数据库创建了区块链
		eth.blockchain, err = core.NewBlockChain(chainDb, eth.chainConfig, eth.engine, vmConfig)
		if err != nil {
			return nil, err
		}
		// Rewind the chain in case of an incompatible config upgrade.
		if compat, ok := genesisErr.(*params.ConfigCompatError); ok {
			log.Warn("Rewinding chain to upgrade configuration", "err", compat)
			eth.blockchain.SetHead(compat.RewindTo)
			core.WriteChainConfig(chainDb, genesisHash, chainConfig)
		}
		// bloomIndexer 暂时不知道是什么东西 这里面涉及得也不是很多。 暂时先不管了
		eth.bloomIndexer.Start(eth.blockchain.CurrentHeader(), eth.blockchain.SubscribeChainEvent)
	
		if config.TxPool.Journal != "" {
			config.TxPool.Journal = ctx.ResolvePath(config.TxPool.Journal)
		}
		// 创建交易池。 用来存储本地或者在网络上接收到的交易。
		eth.txPool = core.NewTxPool(config.TxPool, eth.chainConfig, eth.blockchain)
		// 创建协议管理器
		if eth.protocolManager, err = NewProtocolManager(eth.chainConfig, config.SyncMode, config.NetworkId, eth.eventMux, eth.txPool, eth.engine, eth.blockchain, chainDb); err != nil {
			return nil, err
		}
		// 创建矿工
		eth.miner = miner.New(eth, eth.chainConfig, eth.EventMux(), eth.engine)
		eth.miner.SetExtra(makeExtraData(config.ExtraData))
		// ApiBackend 用于给RPC调用提供后端支持
		eth.ApiBackend = &EthApiBackend{eth, nil}
		// gpoParams GPO Gas Price Oracle 的缩写。 GasPrice预测。 通过最近的交易来预测当前的GasPrice的值。这个值可以作为之后发送交易的费用的参考。
		gpoParams := config.GPO
		if gpoParams.Default == nil {
			gpoParams.Default = config.GasPrice
		}
		eth.ApiBackend.gpo = gasprice.NewOracle(eth.ApiBackend, gpoParams)
	
		return eth, nil
	}

ApiBackend 定义在 api_backend.go文件中。 封装了一些函数。

	// EthApiBackend implements ethapi.Backend for full nodes
	type EthApiBackend struct {
		eth *Ethereum
		gpo *gasprice.Oracle
	}
	func (b *EthApiBackend) SetHead(number uint64) {
		b.eth.protocolManager.downloader.Cancel()
		b.eth.blockchain.SetHead(number)
	}

New方法中除了core中的一些方法， 有一个ProtocolManager的对象在以太坊协议中比较重要， 以太坊本来是一个协议。ProtocolManager中又可以管理多个以太坊的子协议。

	
	// NewProtocolManager returns a new ethereum sub protocol manager. The Ethereum sub protocol manages peers capable
	// with the ethereum network.
	func NewProtocolManager(config *params.ChainConfig, mode downloader.SyncMode, networkId uint64, mux *event.TypeMux, txpool txPool, engine consensus.Engine, blockchain *core.BlockChain, chaindb ethdb.Database) (*ProtocolManager, error) {
		// Create the protocol manager with the base fields
		manager := &ProtocolManager{
			networkId:   networkId,
			eventMux:    mux,
			txpool:      txpool,
			blockchain:  blockchain,
			chaindb:     chaindb,
			chainconfig: config,
			peers:       newPeerSet(),
			newPeerCh:   make(chan *peer),
			noMorePeers: make(chan struct{}),
			txsyncCh:    make(chan *txsync),
			quitSync:    make(chan struct{}),
		}
		// Figure out whether to allow fast sync or not
		if mode == downloader.FastSync && blockchain.CurrentBlock().NumberU64() > 0 {
			log.Warn("Blockchain not empty, fast sync disabled")
			mode = downloader.FullSync
		}
		if mode == downloader.FastSync {
			manager.fastSync = uint32(1)
		}
		// Initiate a sub-protocol for every implemented version we can handle
		manager.SubProtocols = make([]p2p.Protocol, 0, len(ProtocolVersions))
		for i, version := range ProtocolVersions {
			// Skip protocol version if incompatible with the mode of operation
			if mode == downloader.FastSync && version < eth63 {
				continue
			}
			// Compatible; initialise the sub-protocol
			version := version // Closure for the run
			manager.SubProtocols = append(manager.SubProtocols, p2p.Protocol{
				Name:    ProtocolName,
				Version: version,
				Length:  ProtocolLengths[i],
				// 还记得p2p里面的Protocol么。 p2p的peer连接成功之后会调用Run方法
				Run: func(p *p2p.Peer, rw p2p.MsgReadWriter) error {
					peer := manager.newPeer(int(version), p, rw)
					select {
					case manager.newPeerCh <- peer:
						manager.wg.Add(1)
						defer manager.wg.Done()
						return manager.handle(peer)
					case <-manager.quitSync:
						return p2p.DiscQuitting
					}
				},
				NodeInfo: func() interface{} {
					return manager.NodeInfo()
				},
				PeerInfo: func(id discover.NodeID) interface{} {
					if p := manager.peers.Peer(fmt.Sprintf("%x", id[:8])); p != nil {
						return p.Info()
					}
					return nil
				},
			})
		}
		if len(manager.SubProtocols) == 0 {
			return nil, errIncompatibleConfig
		}
		// Construct the different synchronisation mechanisms
		// downloader是负责从其他的peer来同步自身数据。
		// downloader是全链同步工具
		manager.downloader = downloader.New(mode, chaindb, manager.eventMux, blockchain, nil, manager.removePeer)
		// validator 是使用一致性引擎来验证区块头的函数
		validator := func(header *types.Header) error {
			return engine.VerifyHeader(blockchain, header, true)
		}
		// 返回区块高度的函数
		heighter := func() uint64 {
			return blockchain.CurrentBlock().NumberU64()
		}
		// 如果fast sync开启了。 那么不会调用inserter。
		inserter := func(blocks types.Blocks) (int, error) {
			// If fast sync is running, deny importing weird blocks
			if atomic.LoadUint32(&manager.fastSync) == 1 {
				log.Warn("Discarded bad propagated block", "number", blocks[0].Number(), "hash", blocks[0].Hash())
				return 0, nil
			}
			// 设置开始接收交易
			atomic.StoreUint32(&manager.acceptTxs, 1) // Mark initial sync done on any fetcher import
			// 插入区块
			return manager.blockchain.InsertChain(blocks)
		}
		// 生成一个fetcher 
		// Fetcher负责积累来自各个peer的区块通知并安排进行检索。
		manager.fetcher = fetcher.New(blockchain.GetBlockByHash, validator, manager.BroadcastBlock, heighter, inserter, manager.removePeer)
	
		return manager, nil
	}


服务的APIs()方法会返回服务暴露的RPC方法。

	// APIs returns the collection of RPC services the ethereum package offers.
	// NOTE, some of these services probably need to be moved to somewhere else.
	func (s *Ethereum) APIs() []rpc.API {
		apis := ethapi.GetAPIs(s.ApiBackend)
	
		// Append any APIs exposed explicitly by the consensus engine
		apis = append(apis, s.engine.APIs(s.BlockChain())...)
	
		// Append all the local APIs and return
		return append(apis, []rpc.API{
			{
				Namespace: "eth",
				Version:   "1.0",
				Service:   NewPublicEthereumAPI(s),
				Public:    true,
			},
			...
			, {
				Namespace: "net",
				Version:   "1.0",
				Service:   s.netRPCService,
				Public:    true,
			},
		}...)
	}

服务的Protocols方法会返回服务提供了那些p2p的Protocol。 返回协议管理器里面的所有SubProtocols. 如果有lesServer那么还提供lesServer的Protocol。可以看到。所有的网络功能都是通过Protocol的方式提供出来的。

	// Protocols implements node.Service, returning all the currently configured
	// network protocols to start.
	func (s *Ethereum) Protocols() []p2p.Protocol {
		if s.lesServer == nil {
			return s.protocolManager.SubProtocols
		}
		return append(s.protocolManager.SubProtocols, s.lesServer.Protocols()...)
	}


Ethereum服务在创建之后，会被调用服务的Start方法。下面我们来看看Start方法
	
	// Start implements node.Service, starting all internal goroutines needed by the
	// Ethereum protocol implementation.
	func (s *Ethereum) Start(srvr *p2p.Server) error {
		// Start the bloom bits servicing goroutines
		// 启动布隆过滤器请求处理的goroutine TODO
		s.startBloomHandlers()
	
		// Start the RPC service
		// 创建网络的API net
		s.netRPCService = ethapi.NewPublicNetAPI(srvr, s.NetVersion())
	
		// Figure out a max peers count based on the server limits
		maxPeers := srvr.MaxPeers
		if s.config.LightServ > 0 {
			maxPeers -= s.config.LightPeers
			if maxPeers < srvr.MaxPeers/2 {
				maxPeers = srvr.MaxPeers / 2
			}
		}
		// Start the networking layer and the light server if requested
		// 启动协议管理器
		s.protocolManager.Start(maxPeers)
		if s.lesServer != nil {
			// 如果lesServer不为nil 启动它。
			s.lesServer.Start(srvr)
		}
		return nil
	}

协议管理器的数据结构

	type ProtocolManager struct {
		networkId uint64
	
		fastSync  uint32 // Flag whether fast sync is enabled (gets disabled if we already have blocks)
		acceptTxs uint32 // Flag whether we're considered synchronised (enables transaction processing)
	
		txpool      txPool
		blockchain  *core.BlockChain
		chaindb     ethdb.Database
		chainconfig *params.ChainConfig
		maxPeers    int
	
		downloader *downloader.Downloader
		fetcher    *fetcher.Fetcher
		peers      *peerSet
	
		SubProtocols []p2p.Protocol
	
		eventMux      *event.TypeMux
		txCh          chan core.TxPreEvent
		txSub         event.Subscription
		minedBlockSub *event.TypeMuxSubscription
	
		// channels for fetcher, syncer, txsyncLoop
		newPeerCh   chan *peer
		txsyncCh    chan *txsync
		quitSync    chan struct{}
		noMorePeers chan struct{}
	
		// wait group is used for graceful shutdowns during downloading
		// and processing
		wg sync.WaitGroup
	}

协议管理器的Start方法。这个方法里面启动了大量的goroutine用来处理各种事务，可以推测，这个类应该是以太坊服务的主要实现类。
	
	func (pm *ProtocolManager) Start(maxPeers int) {
		pm.maxPeers = maxPeers
		
		// broadcast transactions
		// 广播交易的通道。 txCh会作为txpool的TxPreEvent订阅通道。txpool有了这种消息会通知给这个txCh。 广播交易的goroutine会把这个消息广播出去。
		pm.txCh = make(chan core.TxPreEvent, txChanSize)
		// 订阅的回执
		pm.txSub = pm.txpool.SubscribeTxPreEvent(pm.txCh)
		// 启动广播的goroutine
		go pm.txBroadcastLoop()
	
		// broadcast mined blocks
		// 订阅挖矿消息。当新的Block被挖出来的时候会产生消息。 这个订阅和上面的那个订阅采用了两种不同的模式，这种是标记为Deprecated的订阅方式。
		pm.minedBlockSub = pm.eventMux.Subscribe(core.NewMinedBlockEvent{})
		// 挖矿广播 goroutine 当挖出来的时候需要尽快的广播到网络上面去。
		go pm.minedBroadcastLoop()
	
		// start sync handlers
		// 同步器负责周期性地与网络同步，下载散列和块以及处理通知处理程序。
		go pm.syncer()
		// txsyncLoop负责每个新连接的初始事务同步。 当新的peer出现时，我们转发所有当前待处理的事务。 为了最小化出口带宽使用，我们一次只发送一个小包。
		go pm.txsyncLoop()
	}


当p2p的server启动的时候，会主动的找节点去连接，或者被其他的节点连接。 连接的过程是首先进行加密信道的握手，然后进行协议的握手。 最后为每个协议启动goroutine 执行Run方法来把控制交给最终的协议。 这个run方法首先创建了一个peer对象，然后调用了handle方法来处理这个peer
	
	Run: func(p *p2p.Peer, rw p2p.MsgReadWriter) error {
						peer := manager.newPeer(int(version), p, rw)
						select {
						case manager.newPeerCh <- peer:  //把peer发送到newPeerCh通道
							manager.wg.Add(1)
							defer manager.wg.Done()
							return manager.handle(peer)  // 调用handlo方法
						case <-manager.quitSync:
							return p2p.DiscQuitting
						}
					},


handle方法,

	
	// handle is the callback invoked to manage the life cycle of an eth peer. When
	// this function terminates, the peer is disconnected.
	// handle是一个回调方法，用来管理eth的peer的生命周期管理。 当这个方法退出的时候，peer的连接也会断开。
	func (pm *ProtocolManager) handle(p *peer) error {
		if pm.peers.Len() >= pm.maxPeers {
			return p2p.DiscTooManyPeers
		}
		p.Log().Debug("Ethereum peer connected", "name", p.Name())
	
		// Execute the Ethereum handshake
		td, head, genesis := pm.blockchain.Status()
		// td是total difficult, head是当前的区块头，genesis是创世区块的信息。 只有创世区块相同才能握手成功。
		if err := p.Handshake(pm.networkId, td, head, genesis); err != nil {
			p.Log().Debug("Ethereum handshake failed", "err", err)
			return err
		}
		if rw, ok := p.rw.(*meteredMsgReadWriter); ok {
			rw.Init(p.version)
		}
		// Register the peer locally
		// 把peer注册到本地
		if err := pm.peers.Register(p); err != nil {
			p.Log().Error("Ethereum peer registration failed", "err", err)
			return err
		}
		defer pm.removePeer(p.id)
	
		// Register the peer in the downloader. If the downloader considers it banned, we disconnect
		// 把peer注册给downloader. 如果downloader认为这个peer被禁，那么断开连接。
		if err := pm.downloader.RegisterPeer(p.id, p.version, p); err != nil {
			return err
		}
		// Propagate existing transactions. new transactions appearing
		// after this will be sent via broadcasts.
		// 把当前pending的交易发送给对方，这个只在连接刚建立的时候发生
		pm.syncTransactions(p)
	
		// If we're DAO hard-fork aware, validate any remote peer with regard to the hard-fork
		// 验证peer的DAO硬分叉
		if daoBlock := pm.chainconfig.DAOForkBlock; daoBlock != nil {
			// Request the peer's DAO fork header for extra-data validation
			if err := p.RequestHeadersByNumber(daoBlock.Uint64(), 1, 0, false); err != nil {
				return err
			}
			// Start a timer to disconnect if the peer doesn't reply in time
			// 如果15秒内没有接收到回应。那么断开连接。
			p.forkDrop = time.AfterFunc(daoChallengeTimeout, func() {
				p.Log().Debug("Timed out DAO fork-check, dropping")
				pm.removePeer(p.id)
			})
			// Make sure it's cleaned up if the peer dies off
			defer func() {
				if p.forkDrop != nil {
					p.forkDrop.Stop()
					p.forkDrop = nil
				}
			}()
		}
		// main loop. handle incoming messages.
		// 主循环。 处理进入的消息。
		for {
			if err := pm.handleMsg(p); err != nil {
				p.Log().Debug("Ethereum message handling failed", "err", err)
				return err
			}
		}
	}


Handshake
	
	// Handshake executes the eth protocol handshake, negotiating version number,
	// network IDs, difficulties, head and genesis blocks.
	func (p *peer) Handshake(network uint64, td *big.Int, head common.Hash, genesis common.Hash) error {
		// Send out own handshake in a new thread
		// error的channel的大小是2， 就是为了一次性处理下面的两个goroutine方法
		errc := make(chan error, 2)
		var status statusData // safe to read after two values have been received from errc
	
		go func() {
			errc <- p2p.Send(p.rw, StatusMsg, &statusData{
				ProtocolVersion: uint32(p.version),
				NetworkId:       network,
				TD:              td,
				CurrentBlock:    head,
				GenesisBlock:    genesis,
			})
		}()
		go func() {
			errc <- p.readStatus(network, &status, genesis)
		}()
		timeout := time.NewTimer(handshakeTimeout)
		defer timeout.Stop()
		// 如果接收到任何一个错误(发送，接收),或者是超时， 那么就断开连接。
		for i := 0; i < 2; i++ {
			select {
			case err := <-errc:
				if err != nil {
					return err
				}
			case <-timeout.C:
				return p2p.DiscReadTimeout
			}
		}
		p.td, p.head = status.TD, status.CurrentBlock
		return nil
	}

readStatus，检查对端返回的各种情况，

	func (p *peer) readStatus(network uint64, status *statusData, genesis common.Hash) (err error) {
		msg, err := p.rw.ReadMsg()
		if err != nil {
			return err
		}
		if msg.Code != StatusMsg {
			return errResp(ErrNoStatusMsg, "first msg has code %x (!= %x)", msg.Code, StatusMsg)
		}
		if msg.Size > ProtocolMaxMsgSize {
			return errResp(ErrMsgTooLarge, "%v > %v", msg.Size, ProtocolMaxMsgSize)
		}
		// Decode the handshake and make sure everything matches
		if err := msg.Decode(&status); err != nil {
			return errResp(ErrDecode, "msg %v: %v", msg, err)
		}
		if status.GenesisBlock != genesis {
			return errResp(ErrGenesisBlockMismatch, "%x (!= %x)", status.GenesisBlock[:8], genesis[:8])
		}
		if status.NetworkId != network {
			return errResp(ErrNetworkIdMismatch, "%d (!= %d)", status.NetworkId, network)
		}
		if int(status.ProtocolVersion) != p.version {
			return errResp(ErrProtocolVersionMismatch, "%d (!= %d)", status.ProtocolVersion, p.version)
		}
		return nil
	}

Register 简单的把peer加入到自己的peers的map

	// Register injects a new peer into the working set, or returns an error if the
	// peer is already known.
	func (ps *peerSet) Register(p *peer) error {
		ps.lock.Lock()
		defer ps.lock.Unlock()
	
		if ps.closed {
			return errClosed
		}
		if _, ok := ps.peers[p.id]; ok {
			return errAlreadyRegistered
		}
		ps.peers[p.id] = p
		return nil
	}


经过一系列的检查和握手之后， 循环的调用了handleMsg方法来处理事件循环。 这个方法很长，主要是处理接收到各种消息之后的应对措施。
	
	// handleMsg is invoked whenever an inbound message is received from a remote
	// peer. The remote connection is turn down upon returning any error.
	func (pm *ProtocolManager) handleMsg(p *peer) error {
		// Read the next message from the remote peer, and ensure it's fully consumed
		msg, err := p.rw.ReadMsg()
		if err != nil {
			return err
		}
		if msg.Size > ProtocolMaxMsgSize {
			return errResp(ErrMsgTooLarge, "%v > %v", msg.Size, ProtocolMaxMsgSize)
		}
		defer msg.Discard()
	
		// Handle the message depending on its contents
		switch {
		case msg.Code == StatusMsg:
			// Status messages should never arrive after the handshake
			// StatusMsg应该在HandleShake阶段接收到。 经过了HandleShake之后是不应该接收到这种消息的。
			return errResp(ErrExtraStatusMsg, "uncontrolled status message")
	
		// Block header query, collect the requested headers and reply
		// 接收到请求区块头的消息， 会根据请求返回区块头信息。
		case msg.Code == GetBlockHeadersMsg:
			// Decode the complex header query
			var query getBlockHeadersData
			if err := msg.Decode(&query); err != nil {
				return errResp(ErrDecode, "%v: %v", msg, err)
			}
			hashMode := query.Origin.Hash != (common.Hash{})
	
			// Gather headers until the fetch or network limits is reached
			var (
				bytes   common.StorageSize
				headers []*types.Header
				unknown bool
			)
			for !unknown && len(headers) < int(query.Amount) && bytes < softResponseLimit && len(headers) < downloader.MaxHeaderFetch {
				// Retrieve the next header satisfying the query
				var origin *types.Header
				if hashMode {
					origin = pm.blockchain.GetHeaderByHash(query.Origin.Hash)
				} else {
					origin = pm.blockchain.GetHeaderByNumber(query.Origin.Number)
				}
				if origin == nil {
					break
				}
				number := origin.Number.Uint64()
				headers = append(headers, origin)
				bytes += estHeaderRlpSize
	
				// Advance to the next header of the query
				switch {
				case query.Origin.Hash != (common.Hash{}) && query.Reverse:
					// Hash based traversal towards the genesis block
					// 从Hash指定的开始朝创世区块移动。 也就是反向移动。  通过hash查找
					for i := 0; i < int(query.Skip)+1; i++ {
						if header := pm.blockchain.GetHeader(query.Origin.Hash, number); header != nil {// 通过hash和number获取前一个区块头
						
							query.Origin.Hash = header.ParentHash
							number--
						} else {
							unknown = true
							break //break是跳出switch。 unknow用来跳出循环。
						}
					}
				case query.Origin.Hash != (common.Hash{}) && !query.Reverse:
					// Hash based traversal towards the leaf block
					// 通过hash来查找
					var (
						current = origin.Number.Uint64()
						next    = current + query.Skip + 1
					)
					if next <= current { //正向， 但是next比当前还小，防备整数溢出攻击。
						infos, _ := json.MarshalIndent(p.Peer.Info(), "", "  ")
						p.Log().Warn("GetBlockHeaders skip overflow attack", "current", current, "skip", query.Skip, "next", next, "attacker", infos)
						unknown = true
					} else {
						if header := pm.blockchain.GetHeaderByNumber(next); header != nil {
							if pm.blockchain.GetBlockHashesFromHash(header.Hash(), query.Skip+1)[query.Skip] == query.Origin.Hash {
								// 如果可以找到这个header，而且这个header和origin在同一个链上。
								query.Origin.Hash = header.Hash()
							} else {
								unknown = true
							}
						} else {
							unknown = true
						}
					}
				case query.Reverse:		// 通过number查找
					// Number based traversal towards the genesis block
					//  query.Origin.Hash == (common.Hash{}) 
					if query.Origin.Number >= query.Skip+1 {
						query.Origin.Number -= (query.Skip + 1)
					} else {
						unknown = true
					}
	
				case !query.Reverse:	 //通过number查找
					// Number based traversal towards the leaf block
					query.Origin.Number += (query.Skip + 1)
				}
			}
			return p.SendBlockHeaders(headers)
	
		case msg.Code == BlockHeadersMsg: //接收到了GetBlockHeadersMsg的回答。
			// A batch of headers arrived to one of our previous requests
			var headers []*types.Header
			if err := msg.Decode(&headers); err != nil {
				return errResp(ErrDecode, "msg %v: %v", msg, err)
			}
			// If no headers were received, but we're expending a DAO fork check, maybe it's that
			// 如果对端没有返回任何的headers,而且forkDrop不为空，那么应该是我们的DAO检查的请求，我们之前在HandShake发送了DAO header的请求。
			if len(headers) == 0 && p.forkDrop != nil {
				// Possibly an empty reply to the fork header checks, sanity check TDs
				verifyDAO := true
	
				// If we already have a DAO header, we can check the peer's TD against it. If
				// the peer's ahead of this, it too must have a reply to the DAO check
				if daoHeader := pm.blockchain.GetHeaderByNumber(pm.chainconfig.DAOForkBlock.Uint64()); daoHeader != nil {
					if _, td := p.Head(); td.Cmp(pm.blockchain.GetTd(daoHeader.Hash(), daoHeader.Number.Uint64())) >= 0 {
						//这个时候检查对端的total difficult 是否已经超过了DAO分叉区块的td值， 如果超过了，说明对端应该存在这个区块头， 但是返回的空白的，那么这里验证失败。 这里什么都没有做。 如果对端还不发送，那么会被超时退出。
						verifyDAO = false
					}
				}
				// If we're seemingly on the same chain, disable the drop timer
				if verifyDAO { // 如果验证成功，那么删除掉计时器，然后返回。
					p.Log().Debug("Seems to be on the same side of the DAO fork")
					p.forkDrop.Stop()
					p.forkDrop = nil
					return nil
				}
			}
			// Filter out any explicitly requested headers, deliver the rest to the downloader
			// 过滤出任何非常明确的请求， 然后把剩下的投递给downloader
			// 如果长度是1 那么filter为true
			filter := len(headers) == 1
			if filter {
				// If it's a potential DAO fork check, validate against the rules
				if p.forkDrop != nil && pm.chainconfig.DAOForkBlock.Cmp(headers[0].Number) == 0 {  //DAO检查
					// Disable the fork drop timer
					p.forkDrop.Stop()
					p.forkDrop = nil
	
					// Validate the header and either drop the peer or continue
					if err := misc.VerifyDAOHeaderExtraData(pm.chainconfig, headers[0]); err != nil {
						p.Log().Debug("Verified to be on the other side of the DAO fork, dropping")
						return err
					}
					p.Log().Debug("Verified to be on the same side of the DAO fork")
					return nil
				}
				// Irrelevant of the fork checks, send the header to the fetcher just in case
				// 如果不是DAO的请求，交给过滤器进行过滤。过滤器会返回需要继续处理的headers，这些headers会被交给downloader进行分发。
				headers = pm.fetcher.FilterHeaders(p.id, headers, time.Now())
			}
			if len(headers) > 0 || !filter {
				err := pm.downloader.DeliverHeaders(p.id, headers)
				if err != nil {
					log.Debug("Failed to deliver headers", "err", err)
				}
			}
	
		case msg.Code == GetBlockBodiesMsg:
			//  Block Body的请求 这个比较简单。 从blockchain里面获取body返回就行。
			// Decode the retrieval message
			msgStream := rlp.NewStream(msg.Payload, uint64(msg.Size))
			if _, err := msgStream.List(); err != nil {
				return err
			}
			// Gather blocks until the fetch or network limits is reached
			var (
				hash   common.Hash
				bytes  int
				bodies []rlp.RawValue
			)
			for bytes < softResponseLimit && len(bodies) < downloader.MaxBlockFetch {
				// Retrieve the hash of the next block
				if err := msgStream.Decode(&hash); err == rlp.EOL {
					break
				} else if err != nil {
					return errResp(ErrDecode, "msg %v: %v", msg, err)
				}
				// Retrieve the requested block body, stopping if enough was found
				if data := pm.blockchain.GetBodyRLP(hash); len(data) != 0 {
					bodies = append(bodies, data)
					bytes += len(data)
				}
			}
			return p.SendBlockBodiesRLP(bodies)
	
		case msg.Code == BlockBodiesMsg:
			// A batch of block bodies arrived to one of our previous requests
			var request blockBodiesData
			if err := msg.Decode(&request); err != nil {
				return errResp(ErrDecode, "msg %v: %v", msg, err)
			}
			// Deliver them all to the downloader for queuing
			trasactions := make([][]*types.Transaction, len(request))
			uncles := make([][]*types.Header, len(request))
	
			for i, body := range request {
				trasactions[i] = body.Transactions
				uncles[i] = body.Uncles
			}
			// Filter out any explicitly requested bodies, deliver the rest to the downloader
			// 过滤掉任何显示的请求， 剩下的交给downloader
			filter := len(trasactions) > 0 || len(uncles) > 0
			if filter {
				trasactions, uncles = pm.fetcher.FilterBodies(p.id, trasactions, uncles, time.Now())
			}
			if len(trasactions) > 0 || len(uncles) > 0 || !filter {
				err := pm.downloader.DeliverBodies(p.id, trasactions, uncles)
				if err != nil {
					log.Debug("Failed to deliver bodies", "err", err)
				}
			}
	
		case p.version >= eth63 && msg.Code == GetNodeDataMsg:
			// 对端的版本是eth63 而且是请求NodeData
			// Decode the retrieval message
			msgStream := rlp.NewStream(msg.Payload, uint64(msg.Size))
			if _, err := msgStream.List(); err != nil {
				return err
			}
			// Gather state data until the fetch or network limits is reached
			var (
				hash  common.Hash
				bytes int
				data  [][]byte
			)
			for bytes < softResponseLimit && len(data) < downloader.MaxStateFetch {
				// Retrieve the hash of the next state entry
				if err := msgStream.Decode(&hash); err == rlp.EOL {
					break
				} else if err != nil {
					return errResp(ErrDecode, "msg %v: %v", msg, err)
				}
				// Retrieve the requested state entry, stopping if enough was found
				// 请求的任何hash值都会返回给对方。 
				if entry, err := pm.chaindb.Get(hash.Bytes()); err == nil {
					data = append(data, entry)
					bytes += len(entry)
				}
			}
			return p.SendNodeData(data)
	
		case p.version >= eth63 && msg.Code == NodeDataMsg:
			// A batch of node state data arrived to one of our previous requests
			var data [][]byte
			if err := msg.Decode(&data); err != nil {
				return errResp(ErrDecode, "msg %v: %v", msg, err)
			}
			// Deliver all to the downloader
			// 数据交给downloader
			if err := pm.downloader.DeliverNodeData(p.id, data); err != nil {
				log.Debug("Failed to deliver node state data", "err", err)
			}
	
		case p.version >= eth63 && msg.Code == GetReceiptsMsg:
			// 请求收据
			// Decode the retrieval message
			msgStream := rlp.NewStream(msg.Payload, uint64(msg.Size))
			if _, err := msgStream.List(); err != nil {
				return err
			}
			// Gather state data until the fetch or network limits is reached
			var (
				hash     common.Hash
				bytes    int
				receipts []rlp.RawValue
			)
			for bytes < softResponseLimit && len(receipts) < downloader.MaxReceiptFetch {
				// Retrieve the hash of the next block
				if err := msgStream.Decode(&hash); err == rlp.EOL {
					break
				} else if err != nil {
					return errResp(ErrDecode, "msg %v: %v", msg, err)
				}
				// Retrieve the requested block's receipts, skipping if unknown to us
				results := core.GetBlockReceipts(pm.chaindb, hash, core.GetBlockNumber(pm.chaindb, hash))
				if results == nil {
					if header := pm.blockchain.GetHeaderByHash(hash); header == nil || header.ReceiptHash != types.EmptyRootHash {
						continue
					}
				}
				// If known, encode and queue for response packet
				if encoded, err := rlp.EncodeToBytes(results); err != nil {
					log.Error("Failed to encode receipt", "err", err)
				} else {
					receipts = append(receipts, encoded)
					bytes += len(encoded)
				}
			}
			return p.SendReceiptsRLP(receipts)
	
		case p.version >= eth63 && msg.Code == ReceiptsMsg:
			// A batch of receipts arrived to one of our previous requests
			var receipts [][]*types.Receipt
			if err := msg.Decode(&receipts); err != nil {
				return errResp(ErrDecode, "msg %v: %v", msg, err)
			}
			// Deliver all to the downloader
			if err := pm.downloader.DeliverReceipts(p.id, receipts); err != nil {
				log.Debug("Failed to deliver receipts", "err", err)
			}
	
		case msg.Code == NewBlockHashesMsg:
			// 接收到BlockHashesMsg消息
			var announces newBlockHashesData
			if err := msg.Decode(&announces); err != nil {
				return errResp(ErrDecode, "%v: %v", msg, err)
			}
			// Mark the hashes as present at the remote node
			for _, block := range announces {
				p.MarkBlock(block.Hash)
			}
			// Schedule all the unknown hashes for retrieval
			unknown := make(newBlockHashesData, 0, len(announces))
			for _, block := range announces {
				if !pm.blockchain.HasBlock(block.Hash, block.Number) {
					unknown = append(unknown, block)
				}
			}
			for _, block := range unknown {
				// 通知fetcher有一个潜在的block需要下载
				pm.fetcher.Notify(p.id, block.Hash, block.Number, time.Now(), p.RequestOneHeader, p.RequestBodies)
			}
	
		case msg.Code == NewBlockMsg:
			// Retrieve and decode the propagated block
			var request newBlockData
			if err := msg.Decode(&request); err != nil {
				return errResp(ErrDecode, "%v: %v", msg, err)
			}
			request.Block.ReceivedAt = msg.ReceivedAt
			request.Block.ReceivedFrom = p
	
			// Mark the peer as owning the block and schedule it for import
			p.MarkBlock(request.Block.Hash())
			pm.fetcher.Enqueue(p.id, request.Block)
	
			// Assuming the block is importable by the peer, but possibly not yet done so,
			// calculate the head hash and TD that the peer truly must have.
			var (
				trueHead = request.Block.ParentHash()
				trueTD   = new(big.Int).Sub(request.TD, request.Block.Difficulty())
			)
			// Update the peers total difficulty if better than the previous
			if _, td := p.Head(); trueTD.Cmp(td) > 0 {
				// 如果peer的真实的TD和head和我们这边记载的不同， 设置peer真实的head和td，
				p.SetHead(trueHead, trueTD)
	
				// Schedule a sync if above ours. Note, this will not fire a sync for a gap of
				// a singe block (as the true TD is below the propagated block), however this
				// scenario should easily be covered by the fetcher.
				// 如果真实的TD比我们的TD大，那么请求和这个peer同步。
				currentBlock := pm.blockchain.CurrentBlock()
				if trueTD.Cmp(pm.blockchain.GetTd(currentBlock.Hash(), currentBlock.NumberU64())) > 0 {
					go pm.synchronise(p)
				}
			}
	
		case msg.Code == TxMsg:
			// Transactions arrived, make sure we have a valid and fresh chain to handle them
			// 交易信息返回。 在我们没用同步完成之前不会接收交易信息。
			if atomic.LoadUint32(&pm.acceptTxs) == 0 {
				break
			}
			// Transactions can be processed, parse all of them and deliver to the pool
			var txs []*types.Transaction
			if err := msg.Decode(&txs); err != nil {
				return errResp(ErrDecode, "msg %v: %v", msg, err)
			}
			for i, tx := range txs {
				// Validate and mark the remote transaction
				if tx == nil {
					return errResp(ErrDecode, "transaction %d is nil", i)
				}
				p.MarkTransaction(tx.Hash())
			}
			// 添加到txpool
			pm.txpool.AddRemotes(txs)
	
		default:
			return errResp(ErrInvalidMsgCode, "%v", msg.Code)
		}
		return nil
	}

几种同步synchronise, 之前发现对方的节点比自己节点要更新的时候会调用这个方法synchronise，


	// synchronise tries to sync up our local block chain with a remote peer.
	// synchronise 尝试 让本地区块链跟远端同步。
	func (pm *ProtocolManager) synchronise(peer *peer) {
		// Short circuit if no peers are available
		if peer == nil {
			return
		}
		// Make sure the peer's TD is higher than our own
		currentBlock := pm.blockchain.CurrentBlock()
		td := pm.blockchain.GetTd(currentBlock.Hash(), currentBlock.NumberU64())
	
		pHead, pTd := peer.Head()
		if pTd.Cmp(td) <= 0 {
			return
		}
		// Otherwise try to sync with the downloader
		mode := downloader.FullSync
		if atomic.LoadUint32(&pm.fastSync) == 1 { //如果显式申明是fast
			// Fast sync was explicitly requested, and explicitly granted
			mode = downloader.FastSync
		} else if currentBlock.NumberU64() == 0 && pm.blockchain.CurrentFastBlock().NumberU64() > 0 {  //如果数据库是空白的
			// The database seems empty as the current block is the genesis. Yet the fast
			// block is ahead, so fast sync was enabled for this node at a certain point.
			// The only scenario where this can happen is if the user manually (or via a
			// bad block) rolled back a fast sync node below the sync point. In this case
			// however it's safe to reenable fast sync.
			atomic.StoreUint32(&pm.fastSync, 1)
			mode = downloader.FastSync
		}
		// Run the sync cycle, and disable fast sync if we've went past the pivot block
		err := pm.downloader.Synchronise(peer.id, pHead, pTd, mode)
	
		if atomic.LoadUint32(&pm.fastSync) == 1 {
			// Disable fast sync if we indeed have something in our chain
			if pm.blockchain.CurrentBlock().NumberU64() > 0 {
				log.Info("Fast sync complete, auto disabling")
				atomic.StoreUint32(&pm.fastSync, 0)
			}
		}
		if err != nil {
			return
		}
		atomic.StoreUint32(&pm.acceptTxs, 1) // Mark initial sync done
		// 同步完成 开始接收交易。
		if head := pm.blockchain.CurrentBlock(); head.NumberU64() > 0 {
			// We've completed a sync cycle, notify all peers of new state. This path is
			// essential in star-topology networks where a gateway node needs to notify
			// all its out-of-date peers of the availability of a new block. This failure
			// scenario will most often crop up in private and hackathon networks with
			// degenerate connectivity, but it should be healthy for the mainnet too to
			// more reliably update peers or the local TD state.
			// 我们告诉所有的peer我们的状态。
			go pm.BroadcastBlock(head, false)
		}
	}


交易广播。txBroadcastLoop 在start的时候启动的goroutine。  txCh在txpool接收到一条合法的交易的时候会往这个上面写入事件。 然后把交易广播给所有的peers

	func (self *ProtocolManager) txBroadcastLoop() {
		for {
			select {
			case event := <-self.txCh:
				self.BroadcastTx(event.Tx.Hash(), event.Tx)
	
			// Err() channel will be closed when unsubscribing.
			case <-self.txSub.Err():
				return
			}
		}
	}


挖矿广播。当收到订阅的事件的时候把新挖到的矿广播出去。

	// Mined broadcast loop
	func (self *ProtocolManager) minedBroadcastLoop() {
		// automatically stops if unsubscribe
		for obj := range self.minedBlockSub.Chan() {
			switch ev := obj.Data.(type) {
			case core.NewMinedBlockEvent:
				self.BroadcastBlock(ev.Block, true)  // First propagate block to peers
				self.BroadcastBlock(ev.Block, false) // Only then announce to the rest
			}
		}
	}

syncer负责定期和网络同步，

	// syncer is responsible for periodically synchronising with the network, both
	// downloading hashes and blocks as well as handling the announcement handler.
	//同步器负责周期性地与网络同步，下载散列和块以及处理通知处理程序。
	func (pm *ProtocolManager) syncer() {
		// Start and ensure cleanup of sync mechanisms
		pm.fetcher.Start()
		defer pm.fetcher.Stop()
		defer pm.downloader.Terminate()
	
		// Wait for different events to fire synchronisation operations
		forceSync := time.NewTicker(forceSyncCycle)
		defer forceSync.Stop()
	
		for {
			select {
			case <-pm.newPeerCh: //当有新的Peer增加的时候 会同步。 这个时候还可能触发区块广播。
				// Make sure we have peers to select from, then sync
				if pm.peers.Len() < minDesiredPeerCount {
					break
				}
				go pm.synchronise(pm.peers.BestPeer())
	
			case <-forceSync.C:
				// 定时触发 10秒一次
				// Force a sync even if not enough peers are present
				// BestPeer() 选择总难度最大的节点。
				go pm.synchronise(pm.peers.BestPeer())
	
			case <-pm.noMorePeers: // 退出信号
				return
			}
		}
	}

txsyncLoop负责把pending的交易发送给新建立的连接。


	// txsyncLoop takes care of the initial transaction sync for each new
	// connection. When a new peer appears, we relay all currently pending
	// transactions. In order to minimise egress bandwidth usage, we send
	// the transactions in small packs to one peer at a time.

	txsyncLoop负责每个新连接的初始事务同步。 当新的对等体出现时，我们转发所有当前待处理的事务。 为了最小化出口带宽使用，我们一次将一个小包中的事务发送给一个对等体。
	func (pm *ProtocolManager) txsyncLoop() {
		var (
			pending = make(map[discover.NodeID]*txsync)
			sending = false               // whether a send is active
			pack    = new(txsync)         // the pack that is being sent
			done    = make(chan error, 1) // result of the send
		)
	
		// send starts a sending a pack of transactions from the sync.
		send := func(s *txsync) {
			// Fill pack with transactions up to the target size.
			size := common.StorageSize(0)
			pack.p = s.p
			pack.txs = pack.txs[:0]
			for i := 0; i < len(s.txs) && size < txsyncPackSize; i++ {
				pack.txs = append(pack.txs, s.txs[i])
				size += s.txs[i].Size()
			}
			// Remove the transactions that will be sent.
			s.txs = s.txs[:copy(s.txs, s.txs[len(pack.txs):])]
			if len(s.txs) == 0 {
				delete(pending, s.p.ID())
			}
			// Send the pack in the background.
			s.p.Log().Trace("Sending batch of transactions", "count", len(pack.txs), "bytes", size)
			sending = true
			go func() { done <- pack.p.SendTransactions(pack.txs) }()
		}
	
		// pick chooses the next pending sync.
		// 随机挑选一个txsync来发送。
		pick := func() *txsync {
			if len(pending) == 0 {
				return nil
			}
			n := rand.Intn(len(pending)) + 1
			for _, s := range pending {
				if n--; n == 0 {
					return s
				}
			}
			return nil
		}
	
		for {
			select {
			case s := <-pm.txsyncCh: //从这里接收txsyncCh消息。
				pending[s.p.ID()] = s
				if !sending {
					send(s)
				}
			case err := <-done:
				sending = false
				// Stop tracking peers that cause send failures.
				if err != nil {
					pack.p.Log().Debug("Transaction send failed", "err", err)
					delete(pending, pack.p.ID())
				}
				// Schedule the next send.
				if s := pick(); s != nil {
					send(s)
				}
			case <-pm.quitSync:
				return
			}
		}
	}

txsyncCh队列的生产者，syncTransactions是在handle方法里面调用的。 在新链接刚刚创建的时候会被调用一次。

	// syncTransactions starts sending all currently pending transactions to the given peer.
	func (pm *ProtocolManager) syncTransactions(p *peer) {
		var txs types.Transactions
		pending, _ := pm.txpool.Pending()
		for _, batch := range pending {
			txs = append(txs, batch...)
		}
		if len(txs) == 0 {
			return
		}
		select {
		case pm.txsyncCh <- &txsync{p, txs}:
		case <-pm.quitSync:
		}
	}


总结一下。 我们现在的一些大的流程。

区块同步

1. 如果是自己挖的矿。通过goroutine minedBroadcastLoop()来进行广播。
2. 如果是接收到其他人的区块广播，(NewBlockHashesMsg/NewBlockMsg),是否fetcher会通知的peer？ TODO
3. goroutine syncer()中会定时的同BestPeer()来同步信息。

交易同步

1. 新建立连接。 把pending的交易发送给他。
2. 本地发送了一个交易，或者是接收到别人发来的交易信息。 txpool会产生一条消息，消息被传递到txCh通道。 然后被goroutine txBroadcastLoop()处理， 发送给其他不知道这个交易的peer。