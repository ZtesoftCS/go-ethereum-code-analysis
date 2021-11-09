产生一个随机seed,赋给nonce随机数，
然后进行sha256的hash运算,如果算出的hash难度不符合目标难度,则nonce+1，继续运算



worker.go/wait()
func (self *worker) wait() {
	for {
		mustCommitNewWork := true
		for result := range self.recv {
			atomic.AddInt32(&self.atWork, -1)

			if result == nil {
				continue
			}


agent.go/mine()方法


func (self *CpuAgent) mine(work *Work, stop <-chan struct{}) {
	if result, err := self.engine.Seal(self.chain, work.Block, stop); result != nil {
		log.Info("Successfully sealed new block", "number", result.Number(), "hash", result.Hash())
		self.returnCh <- &Result{work, result}
	} else {
		if err != nil {
			log.Warn("Block sealing failed", "err", err)
		}
		self.returnCh <- nil
	}
}

如果挖到一个新块，则将结果写到self的return管道中


写块的方法WriteBlockAndState

wait方法接收self.recv管道的结果，如果有结果，说明本地挖到新块了，则将新块进行存储，
并把该块放到待确认的block判定区

miner.go/update方法，如果有新块出来，则停止挖矿进行下载同步新块，如果下载完成或失败的事件，则继续开始挖矿.



/geth/main.go/geth　--> makeFullNode --> utils.RegisterEthService

--> eth.New(ctx, cfg)　--> miner.New(eth, eth.chainConfig, eth.EventMux(), eth.engine)


这个是启动链后到挖矿，共识代码的整个调用栈，开始分析核心方法


func New(eth Backend, config *params.ChainConfig, mux *event.TypeMux, engine consensus.Engine) *Miner {
	miner := &Miner{
		eth:      eth,
		mux:      mux,
		engine:   engine,
		worker:   newWorker(config, engine, common.Address{}, eth, mux),
		canStart: 1,
	}
	miner.Register(NewCpuAgent(eth.BlockChain(), engine))
	go miner.update()

	return miner
}

从miner.Update()的逻辑可以看出，对于任何一个Ethereum网络中的节点来说，挖掘一个新区块和从其他节点下载、同步一个新区块，根本是相互冲突的。这样的规定，保证了在某个节点上，一个新区块只可能有一种来源，这可以大大降低可能出现的区块冲突，并避免全网中计算资源的浪费。

首先是:

func (self *Miner) Register(agent Agent) {
	if self.Mining() {
		agent.Start()
	}
	self.worker.register(agent)
}

func (self *worker) register(agent Agent) {
	self.mu.Lock()
	defer self.mu.Unlock()
	self.agents[agent] = struct{}{}
	agent.SetReturnCh(self.recv)
}

该方法中将self的recv管道绑定在了agent的return管道


然后是newWorker方法

func newWorker(config *params.ChainConfig, engine consensus.Engine, coinbase common.Address, eth Backend, mux *event.TypeMux) *worker {
	worker := &worker{
		config:         config,
		engine:         engine,
		eth:            eth,
		mux:            mux,
		txCh:           make(chan core.TxPreEvent, txChanSize),
		chainHeadCh:    make(chan core.ChainHeadEvent, chainHeadChanSize),
		chainSideCh:    make(chan core.ChainSideEvent, chainSideChanSize),
		chainDb:        eth.ChainDb(),
		recv:           make(chan *Result, resultQueueSize),
		chain:          eth.BlockChain(),
		proc:           eth.BlockChain().Validator(),
		possibleUncles: make(map[common.Hash]*types.Block),
		coinbase:       coinbase,
		agents:         make(map[Agent]struct{}),
		unconfirmed:    newUnconfirmedBlocks(eth.BlockChain(), miningLogAtDepth),
	}
	// Subscribe TxPreEvent for tx pool
	worker.txSub = eth.TxPool().SubscribeTxPreEvent(worker.txCh)
	// Subscribe events for blockchain
	worker.chainHeadSub = eth.BlockChain().SubscribeChainHeadEvent(worker.chainHeadCh)
	worker.chainSideSub = eth.BlockChain().SubscribeChainSideEvent(worker.chainSideCh)
	go worker.update()

	go worker.wait()
	worker.commitNewWork()

	return worker
}


该方法中绑定了三个管道,额外启动了两个goroutine执行update和wait方法,
func (self *worker) update() {
	defer self.txSub.Unsubscribe()
	defer self.chainHeadSub.Unsubscribe()
	defer self.chainSideSub.Unsubscribe()

	for {
		// A real event arrived, process interesting content
		select {
		// Handle ChainHeadEvent
		case <-self.chainHeadCh:
			self.commitNewWork()

		// Handle ChainSideEvent
		case ev := <-self.chainSideCh:
			self.uncleMu.Lock()
			self.possibleUncles[ev.Block.Hash()] = ev.Block
			self.uncleMu.Unlock()

		// Handle TxPreEvent
		case ev := <-self.txCh:
			// Apply transaction to the pending state if we're not mining
			if atomic.LoadInt32(&self.mining) == 0 {
				self.currentMu.Lock()
				acc, _ := types.Sender(self.current.signer, ev.Tx)
				txs := map[common.Address]types.Transactions{acc: {ev.Tx}}
				txset := types.NewTransactionsByPriceAndNonce(self.current.signer, txs)

				self.current.commitTransactions(self.mux, txset, self.chain, self.coinbase)
				self.currentMu.Unlock()
			} else {
				// If we're mining, but nothing is being processed, wake on new transactions
				if self.config.Clique != nil && self.config.Clique.Period == 0 {
					self.commitNewWork()
				}
			}

		// System stopped
		case <-self.txSub.Err():
			return
		case <-self.chainHeadSub.Err():
			return
		case <-self.chainSideSub.Err():
			return
		}
	}
}



worker.update方法中接收各种事件，并且是永久循环，如果有错误事件发生，则终止，如果有新的交易事件，则执行commitTransactions验证提交交易到本地的trx判定池中,供下次出块使用
worker.wait的方法接收self.recv管道的结果，也就是本地新挖出的块，如果有挖出，则写入块数据，并广播一个chainHeadEvent事件,同时将
该块添加到待确认列表中，并且提交一个新的工作量，commitNewWork方法相当于共识的第一个阶段，它会组装一个标准的块，其他包含产出该块需要的难度，
然后将产出该块的工作以及块信息广播给所有代理，
接着agent.go中的update方法监听到广播新块工作量的任务，开始挖矿，抢该块的出块权

func (self *CpuAgent) mine(work *Work, stop <-chan struct{}) {
	if result, err := self.engine.Seal(self.chain, work.Block, stop); result != nil {
		log.Info("Successfully sealed new block", "number", result.Number(), "hash", result.Hash())
		self.returnCh <- &Result{work, result}
	} else {
		if err != nil {
			log.Warn("Block sealing failed", "err", err)
		}
		self.returnCh <- nil
	}
}

该方法中开始进行块的hash难度计算，如果返回的result结果不为空，说明挖矿成功，将结果写入到returnCh通道中

然后worker.go中的wait方法又接收到了信息开始处理.


如果不是组装好带有随机数hash的，那么存储块将会返回错误,
	stat, err := self.chain.WriteBlockAndState(block, work.receipts, work.state)
			if err != nil {
				log.Error("Failed writing block to chain", "err", err)
				continue
			}
			
			
remote_agent 提供了一套RPC接口，可以实现远程矿工进行采矿的功能。 比如我有一个矿机，矿机内部没有运行以太坊节点，矿机首先从remote_agent获取当前的任务，然后进行挖矿计算，当挖矿完成后，提交计算结果，完成挖矿。			











