txpool主要用来存放当前提交的等待写入区块的交易，有远端和本地的。

txpool里面的交易分为两种，
1. 提交但是还不能执行的，放在queue里面等待能够执行(比如说nonce太高)。
2. 等待执行的，放在pending里面等待执行。

从txpool的测试案例来看，txpool主要功能有下面几点。

1. 交易验证的功能，包括余额不足，Gas不足，Nonce太低, value值是合法的，不能为负数。
2. 能够缓存Nonce比当前本地账号状态高的交易。 存放在queue字段。 如果是能够执行的交易存放在pending字段
3. 相同用户的相同Nonce的交易只会保留一个GasPrice最大的那个。 其他的插入不成功。
4. 如果账号没有钱了，那么queue和pending中对应账号的交易会被删除。
5. 如果账号的余额小于一些交易的额度，那么对应的交易会被删除，同时有效的交易会从pending移动到queue里面。防止被广播。
6. txPool支持一些限制PriceLimit(remove的最低GasPrice限制)，PriceBump(替换相同Nonce的交易的价格的百分比) AccountSlots(每个账户的pending的槽位的最小值) GlobalSlots(全局pending队列的最大值)AccountQueue(每个账户的queueing的槽位的最小值) GlobalQueue(全局queueing的最大值) Lifetime(在queue队列的最长等待时间)
7. 有限的资源情况下按照GasPrice的优先级进行替换。
8. 本地的交易会使用journal的功能存放在磁盘上，重启之后会重新导入。 远程的交易不会。




数据结构
	
	// TxPool contains all currently known transactions. Transactions
	// enter the pool when they are received from the network or submitted
	// locally. They exit the pool when they are included in the blockchain.
	// TxPool 包含了当前知的交易， 当前网络接收到交易，或者本地提交的交易会加入到TxPool。
	// 当他们已经被添加到区块链的时候被移除。
	// The pool separates processable transactions (which can be applied to the
	// current state) and future transactions. Transactions move between those
	// two states over time as they are received and processed.
	// TxPool分为可执行的交易(可以应用到当前的状态)和未来的交易。 交易在这两种状态之间转换，
	type TxPool struct {
		config       TxPoolConfig
		chainconfig  *params.ChainConfig
		chain        blockChain
		gasPrice     *big.Int             //最低的GasPrice限制
		txFeed       event.Feed	          //通过txFeed来订阅TxPool的消息
		scope        event.SubscriptionScope
		chainHeadCh  chan ChainHeadEvent  // 订阅了区块头的消息，当有了新的区块头生成的时候会在这里收到通知
		chainHeadSub event.Subscription   // 区块头消息的订阅器。
		signer       types.Signer		  // 封装了事务签名处理。
		mu           sync.RWMutex
	
		currentState  *state.StateDB      // Current state in the blockchain head
		pendingState  *state.ManagedState // Pending state tracking virtual nonces
		currentMaxGas *big.Int            // Current gas limit for transaction caps 目前交易上限的GasLimit
	
		locals  *accountSet // Set of local transaction to exepmt from evicion rules  本地交易免除驱逐规则
		journal *txJournal  // Journal of local transaction to back up to disk 本地交易会写入磁盘
	
		pending map[common.Address]*txList         // All currently processable transactions 所有当前可以处理的交易
		queue   map[common.Address]*txList         // Queued but non-processable transactions 当前还不能处理的交易
		beats   map[common.Address]time.Time       // Last heartbeat from each known account 每一个已知账号的最后一次心跳信息的时间
		all     map[common.Hash]*types.Transaction // All transactions to allow lookups 可以查找到所有交易
		priced  *txPricedList                      // All transactions sorted by price 按照价格排序的交易
	
		wg sync.WaitGroup // for shutdown sync
	
		homestead bool  // 家园版本
	}



构建
	
	
	// NewTxPool creates a new transaction pool to gather, sort and filter inbound
	// trnsactions from the network.
	func NewTxPool(config TxPoolConfig, chainconfig *params.ChainConfig, chain blockChain) *TxPool {
		// Sanitize the input to ensure no vulnerable gas prices are set
		config = (&config).sanitize()
	
		// Create the transaction pool with its initial settings
		pool := &TxPool{
			config:      config,
			chainconfig: chainconfig,
			chain:       chain,
			signer:      types.NewEIP155Signer(chainconfig.ChainId),
			pending:     make(map[common.Address]*txList),
			queue:       make(map[common.Address]*txList),
			beats:       make(map[common.Address]time.Time),
			all:         make(map[common.Hash]*types.Transaction),
			chainHeadCh: make(chan ChainHeadEvent, chainHeadChanSize),
			gasPrice:    new(big.Int).SetUint64(config.PriceLimit),
		}
		pool.locals = newAccountSet(pool.signer)
		pool.priced = newTxPricedList(&pool.all)
		pool.reset(nil, chain.CurrentBlock().Header())
	
		// If local transactions and journaling is enabled, load from disk
		// 如果本地交易被允许,而且配置的Journal目录不为空,那么从指定的目录加载日志.
		// 然后rotate交易日志. 因为老的交易可能已经失效了, 所以调用add方法之后再把被接收的交易写入日志.
		// 
		if !config.NoLocals && config.Journal != "" {
			pool.journal = newTxJournal(config.Journal)
	
			if err := pool.journal.load(pool.AddLocal); err != nil {
				log.Warn("Failed to load transaction journal", "err", err)
			}
			if err := pool.journal.rotate(pool.local()); err != nil {
				log.Warn("Failed to rotate transaction journal", "err", err)
			}
		}
		// Subscribe events from blockchain 从区块链订阅事件。
		pool.chainHeadSub = pool.chain.SubscribeChainHeadEvent(pool.chainHeadCh)
	
		// Start the event loop and return
		pool.wg.Add(1)
		go pool.loop()
	
		return pool
	}

reset方法检索区块链的当前状态并且确保事务池的内容关于当前的区块链状态是有效的。主要功能包括：

1. 因为更换了区块头，所以原有的区块中有一些交易因为区块头的更换而作废，这部分交易需要重新加入到txPool里面等待插入新的区块
2. 生成新的currentState和pendingState
3. 因为状态的改变。将pending中的部分交易移到queue里面
4. 因为状态的改变，将queue里面的交易移入到pending里面。

reset代码

	// reset retrieves the current state of the blockchain and ensures the content
	// of the transaction pool is valid with regard to the chain state.
	func (pool *TxPool) reset(oldHead, newHead *types.Header) {
		// If we're reorging an old state, reinject all dropped transactions
		var reinject types.Transactions
	
		if oldHead != nil && oldHead.Hash() != newHead.ParentHash {
			// If the reorg is too deep, avoid doing it (will happen during fast sync)
			oldNum := oldHead.Number.Uint64()
			newNum := newHead.Number.Uint64()
	
			if depth := uint64(math.Abs(float64(oldNum) - float64(newNum))); depth > 64 { //如果老的头和新的头差距太远, 那么取消重建
				log.Warn("Skipping deep transaction reorg", "depth", depth)
			} else {
				// Reorg seems shallow enough to pull in all transactions into memory
				var discarded, included types.Transactions
	
				var (
					rem = pool.chain.GetBlock(oldHead.Hash(), oldHead.Number.Uint64())
					add = pool.chain.GetBlock(newHead.Hash(), newHead.Number.Uint64())
				)
				// 如果老的高度大于新的.那么需要把多的全部删除.
				for rem.NumberU64() > add.NumberU64() {
					discarded = append(discarded, rem.Transactions()...)
					if rem = pool.chain.GetBlock(rem.ParentHash(), rem.NumberU64()-1); rem == nil {
						log.Error("Unrooted old chain seen by tx pool", "block", oldHead.Number, "hash", oldHead.Hash())
						return
					}
				}
				// 如果新的高度大于老的, 那么需要增加.
				for add.NumberU64() > rem.NumberU64() {
					included = append(included, add.Transactions()...)
					if add = pool.chain.GetBlock(add.ParentHash(), add.NumberU64()-1); add == nil {
						log.Error("Unrooted new chain seen by tx pool", "block", newHead.Number, "hash", newHead.Hash())
						return
					}
				}
				// 高度相同了.如果hash不同,那么需要往后找,一直找到他们相同hash根的节点.
				for rem.Hash() != add.Hash() {
					discarded = append(discarded, rem.Transactions()...)
					if rem = pool.chain.GetBlock(rem.ParentHash(), rem.NumberU64()-1); rem == nil {
						log.Error("Unrooted old chain seen by tx pool", "block", oldHead.Number, "hash", oldHead.Hash())
						return
					}
					included = append(included, add.Transactions()...)
					if add = pool.chain.GetBlock(add.ParentHash(), add.NumberU64()-1); add == nil {
						log.Error("Unrooted new chain seen by tx pool", "block", newHead.Number, "hash", newHead.Hash())
						return
					}
				}
				// 找出所有存在discard里面,但是不在included里面的值.
				// 需要等下把这些交易重新插入到pool里面。
				reinject = types.TxDifference(discarded, included)
			}
		}
		// Initialize the internal state to the current head
		if newHead == nil {
			newHead = pool.chain.CurrentBlock().Header() // Special case during testing
		}
		statedb, err := pool.chain.StateAt(newHead.Root)
		if err != nil {
			log.Error("Failed to reset txpool state", "err", err)
			return
		}
		pool.currentState = statedb
		pool.pendingState = state.ManageState(statedb)
		pool.currentMaxGas = newHead.GasLimit
	
		// Inject any transactions discarded due to reorgs
		log.Debug("Reinjecting stale transactions", "count", len(reinject))
		pool.addTxsLocked(reinject, false)
	
		// validate the pool of pending transactions, this will remove
		// any transactions that have been included in the block or
		// have been invalidated because of another transaction (e.g.
		// higher gas price)
		// 验证pending transaction池里面的交易， 会移除所有已经存在区块链里面的交易，或者是因为其他交易导致不可用的交易(比如有一个更高的gasPrice)
		// demote 降级 将pending中的一些交易降级到queue里面。
		pool.demoteUnexecutables()
	
		// Update all accounts to the latest known pending nonce
		// 根据pending队列的nonce更新所有账号的nonce
		for addr, list := range pool.pending {
			txs := list.Flatten() // Heavy but will be cached and is needed by the miner anyway
			pool.pendingState.SetNonce(addr, txs[len(txs)-1].Nonce()+1)
		}
		// Check the queue and move transactions over to the pending if possible
		// or remove those that have become invalid
		// 检查队列并尽可能地将事务移到pending，或删除那些已经失效的事务
		// promote 升级 
		pool.promoteExecutables(nil)
	}
addTx 
	
	// addTx enqueues a single transaction into the pool if it is valid.
	func (pool *TxPool) addTx(tx *types.Transaction, local bool) error {
		pool.mu.Lock()
		defer pool.mu.Unlock()
	
		// Try to inject the transaction and update any state
		replace, err := pool.add(tx, local)
		if err != nil {
			return err
		}
		// If we added a new transaction, run promotion checks and return
		if !replace {
			from, _ := types.Sender(pool.signer, tx) // already validated
			pool.promoteExecutables([]common.Address{from})
		}
		return nil
	}

addTxsLocked
	
	// addTxsLocked attempts to queue a batch of transactions if they are valid,
	// whilst assuming the transaction pool lock is already held.
	// addTxsLocked尝试把有效的交易放入queue队列，调用这个函数的时候假设已经获取到锁
	func (pool *TxPool) addTxsLocked(txs []*types.Transaction, local bool) error {
		// Add the batch of transaction, tracking the accepted ones
		dirty := make(map[common.Address]struct{})
		for _, tx := range txs {
			if replace, err := pool.add(tx, local); err == nil {
				if !replace { // replace 是替换的意思， 如果不是替换，那么就说明状态有更新，有可以下一步处理的可能。
					from, _ := types.Sender(pool.signer, tx) // already validated
					dirty[from] = struct{}{}
				}
			}
		}
		// Only reprocess the internal state if something was actually added
		if len(dirty) > 0 {
			addrs := make([]common.Address, 0, len(dirty))
			for addr, _ := range dirty {
				addrs = append(addrs, addr)
			}	
			// 传入了被修改的地址，
			pool.promoteExecutables(addrs)
		}
		return nil
	}
demoteUnexecutables 从pending删除无效的或者是已经处理过的交易，其他的不可执行的交易会被移动到future queue中。
	
	// demoteUnexecutables removes invalid and processed transactions from the pools
	// executable/pending queue and any subsequent transactions that become unexecutable
	// are moved back into the future queue.
	func (pool *TxPool) demoteUnexecutables() {
		// Iterate over all accounts and demote any non-executable transactions
		for addr, list := range pool.pending {
			nonce := pool.currentState.GetNonce(addr)
	
			// Drop all transactions that are deemed too old (low nonce)
			// 删除所有小于当前地址的nonce的交易，并从pool.all删除。
			for _, tx := range list.Forward(nonce) {
				hash := tx.Hash()
				log.Trace("Removed old pending transaction", "hash", hash)
				delete(pool.all, hash)
				pool.priced.Removed()
			}
			// Drop all transactions that are too costly (low balance or out of gas), and queue any invalids back for later
			// 删除所有的太昂贵的交易。 用户的balance可能不够用。或者是out of gas
			drops, invalids := list.Filter(pool.currentState.GetBalance(addr), pool.currentMaxGas)
			for _, tx := range drops {
				hash := tx.Hash()
				log.Trace("Removed unpayable pending transaction", "hash", hash)
				delete(pool.all, hash)
				pool.priced.Removed()
				pendingNofundsCounter.Inc(1)
			}
			for _, tx := range invalids {
				hash := tx.Hash()
				log.Trace("Demoting pending transaction", "hash", hash)
				pool.enqueueTx(hash, tx)
			}
			// If there's a gap in front, warn (should never happen) and postpone all transactions
			// 如果存在一个空洞(nonce空洞)， 那么需要把所有的交易都放入future queue。
			// 这一步确实应该不可能发生，因为Filter已经把 invalids的都处理了。 应该不存在invalids的交易，也就是不存在空洞的。
			if list.Len() > 0 && list.txs.Get(nonce) == nil {
				for _, tx := range list.Cap(0) {
					hash := tx.Hash()
					log.Error("Demoting invalidated transaction", "hash", hash)
					pool.enqueueTx(hash, tx)
				}
			}
			// Delete the entire queue entry if it became empty.
			if list.Empty() { 
				delete(pool.pending, addr)
				delete(pool.beats, addr)
			}
		}
	}

enqueueTx 把一个新的交易插入到future queue。 这个方法假设已经获取了池的锁。
	
	// enqueueTx inserts a new transaction into the non-executable transaction queue.
	//
	// Note, this method assumes the pool lock is held!
	func (pool *TxPool) enqueueTx(hash common.Hash, tx *types.Transaction) (bool, error) {
		// Try to insert the transaction into the future queue
		from, _ := types.Sender(pool.signer, tx) // already validated
		if pool.queue[from] == nil {
			pool.queue[from] = newTxList(false)
		}
		inserted, old := pool.queue[from].Add(tx, pool.config.PriceBump)
		if !inserted {
			// An older transaction was better, discard this
			queuedDiscardCounter.Inc(1)
			return false, ErrReplaceUnderpriced
		}
		// Discard any previous transaction and mark this
		if old != nil {
			delete(pool.all, old.Hash())
			pool.priced.Removed()
			queuedReplaceCounter.Inc(1)
		}
		pool.all[hash] = tx
		pool.priced.Put(tx)
		return old != nil, nil
	}

promoteExecutables方法把 已经变得可以执行的交易从future queue 插入到pending queue。通过这个处理过程，所有的无效的交易(nonce太低，余额不足)会被删除。
	
	// promoteExecutables moves transactions that have become processable from the
	// future queue to the set of pending transactions. During this process, all
	// invalidated transactions (low nonce, low balance) are deleted.
	func (pool *TxPool) promoteExecutables(accounts []common.Address) {
		// Gather all the accounts potentially needing updates
		// accounts存储了所有潜在需要更新的账户。 如果账户传入为nil，代表所有已知的账户。
		if accounts == nil {
			accounts = make([]common.Address, 0, len(pool.queue))
			for addr, _ := range pool.queue {
				accounts = append(accounts, addr)
			}
		}
		// Iterate over all accounts and promote any executable transactions
		for _, addr := range accounts {
			list := pool.queue[addr]
			if list == nil {
				continue // Just in case someone calls with a non existing account
			}
			// Drop all transactions that are deemed too old (low nonce)
			// 删除所有的nonce太低的交易
			for _, tx := range list.Forward(pool.currentState.GetNonce(addr)) {
				hash := tx.Hash()
				log.Trace("Removed old queued transaction", "hash", hash)
				delete(pool.all, hash)
				pool.priced.Removed()
			}
			// Drop all transactions that are too costly (low balance or out of gas)
			// 删除所有余额不足的交易。
			drops, _ := list.Filter(pool.currentState.GetBalance(addr), pool.currentMaxGas)
			for _, tx := range drops {
				hash := tx.Hash()
				log.Trace("Removed unpayable queued transaction", "hash", hash)
				delete(pool.all, hash)
				pool.priced.Removed()
				queuedNofundsCounter.Inc(1)
			}
			// Gather all executable transactions and promote them
			// 得到所有的可以执行的交易，并promoteTx加入pending
			for _, tx := range list.Ready(pool.pendingState.GetNonce(addr)) {
				hash := tx.Hash()
				log.Trace("Promoting queued transaction", "hash", hash)
				pool.promoteTx(addr, hash, tx)
			}
			// Drop all transactions over the allowed limit
			// 删除所有超过限制的交易。
			if !pool.locals.contains(addr) {
				for _, tx := range list.Cap(int(pool.config.AccountQueue)) {
					hash := tx.Hash()
					delete(pool.all, hash)
					pool.priced.Removed()
					queuedRateLimitCounter.Inc(1)
					log.Trace("Removed cap-exceeding queued transaction", "hash", hash)
				}
			}
			// Delete the entire queue entry if it became empty.
			if list.Empty() {
				delete(pool.queue, addr)
			}
		}
		// If the pending limit is overflown, start equalizing allowances
		pending := uint64(0)
		for _, list := range pool.pending {
			pending += uint64(list.Len())
		}
		// 如果pending的总数超过系统的配置。 
		if pending > pool.config.GlobalSlots {
			
			pendingBeforeCap := pending
			// Assemble a spam order to penalize large transactors first
			spammers := prque.New()
			for addr, list := range pool.pending {
				// Only evict transactions from high rollers
				// 首先把所有大于AccountSlots最小值的账户记录下来， 会从这些账户里面剔除一些交易。
				// 注意spammers是一个优先级队列，也就是说是按照交易的多少从大到小排序的。
				if !pool.locals.contains(addr) && uint64(list.Len()) > pool.config.AccountSlots {
					spammers.Push(addr, float32(list.Len()))
				}
			}
			// Gradually drop transactions from offenders
			offenders := []common.Address{}
			for pending > pool.config.GlobalSlots && !spammers.Empty() {
				/*	
				模拟一下offenders队列的账户交易数量的变化情况。 
					第一次循环   [10]    循环结束  [10]
					第二次循环   [10, 9] 循环结束  [9,9]
					第三次循环   [9, 9, 7] 循环结束 [7, 7, 7]
					第四次循环   [7, 7 , 7 ,2] 循环结束 [2, 2 ,2, 2]
				*/
				// Retrieve the next offender if not local address
				offender, _ := spammers.Pop()
				offenders = append(offenders, offender.(common.Address))
	
				// Equalize balances until all the same or below threshold
				if len(offenders) > 1 { // 第一次进入这个循环的时候， offenders队列里面有交易数量最大的两个账户
					// Calculate the equalization threshold for all current offenders
					// 把最后加入的账户的交易数量当成本次的阈值
					threshold := pool.pending[offender.(common.Address)].Len()
	
					// Iteratively reduce all offenders until below limit or threshold reached
					// 遍历直到pending有效，或者是倒数第二个的交易数量等于最后一个的交易数量
					for pending > pool.config.GlobalSlots && pool.pending[offenders[len(offenders)-2]].Len() > threshold {
						// 遍历除了最后一个账户以外的所有账户， 把他们的交易数量减去1.
						for i := 0; i < len(offenders)-1; i++ {
							list := pool.pending[offenders[i]]
							for _, tx := range list.Cap(list.Len() - 1) {
								// Drop the transaction from the global pools too
								hash := tx.Hash()
								delete(pool.all, hash)
								pool.priced.Removed()
	
								// Update the account nonce to the dropped transaction
								if nonce := tx.Nonce(); pool.pendingState.GetNonce(offenders[i]) > nonce {
									pool.pendingState.SetNonce(offenders[i], nonce)
								}
								log.Trace("Removed fairness-exceeding pending transaction", "hash", hash)
							}
							pending--
						}
					}
				}
			}
			// If still above threshold, reduce to limit or min allowance
			// 经过上面的循环，所有的超过AccountSlots的账户的交易数量都变成了之前的最小值。
			// 如果还是超过阈值，那么在继续从offenders里面每次删除一个。
			if pending > pool.config.GlobalSlots && len(offenders) > 0 {
				for pending > pool.config.GlobalSlots && uint64(pool.pending[offenders[len(offenders)-1]].Len()) > pool.config.AccountSlots {
					for _, addr := range offenders {
						list := pool.pending[addr]
						for _, tx := range list.Cap(list.Len() - 1) {
							// Drop the transaction from the global pools too
							hash := tx.Hash()
							delete(pool.all, hash)
							pool.priced.Removed()
	
							// Update the account nonce to the dropped transaction
							if nonce := tx.Nonce(); pool.pendingState.GetNonce(addr) > nonce {
								pool.pendingState.SetNonce(addr, nonce)
							}
							log.Trace("Removed fairness-exceeding pending transaction", "hash", hash)
						}
						pending--
					}
				}
			}
			pendingRateLimitCounter.Inc(int64(pendingBeforeCap - pending))
		}  //end if pending > pool.config.GlobalSlots {
		// If we've queued more transactions than the hard limit, drop oldest ones
		// 我们处理了pending的限制， 下面需要处理future queue的限制了。
		queued := uint64(0)
		for _, list := range pool.queue {
			queued += uint64(list.Len())
		}
		if queued > pool.config.GlobalQueue {
			// Sort all accounts with queued transactions by heartbeat
			addresses := make(addresssByHeartbeat, 0, len(pool.queue))
			for addr := range pool.queue {
				if !pool.locals.contains(addr) { // don't drop locals
					addresses = append(addresses, addressByHeartbeat{addr, pool.beats[addr]})
				}
			}
			sort.Sort(addresses)
	
			// Drop transactions until the total is below the limit or only locals remain
			// 从后往前，也就是心跳越新的就越会被删除。
			for drop := queued - pool.config.GlobalQueue; drop > 0 && len(addresses) > 0; {
				addr := addresses[len(addresses)-1]
				list := pool.queue[addr.address]
	
				addresses = addresses[:len(addresses)-1]
	
				// Drop all transactions if they are less than the overflow
				if size := uint64(list.Len()); size <= drop {
					for _, tx := range list.Flatten() {
						pool.removeTx(tx.Hash())
					}
					drop -= size
					queuedRateLimitCounter.Inc(int64(size))
					continue
				}
				// Otherwise drop only last few transactions
				txs := list.Flatten()
				for i := len(txs) - 1; i >= 0 && drop > 0; i-- {
					pool.removeTx(txs[i].Hash())
					drop--
					queuedRateLimitCounter.Inc(1)
				}
			}
		}
	}

promoteTx把某个交易加入到pending 队列. 这个方法假设已经获取到了锁.

	// promoteTx adds a transaction to the pending (processable) list of transactions.
	//
	// Note, this method assumes the pool lock is held!
	func (pool *TxPool) promoteTx(addr common.Address, hash common.Hash, tx *types.Transaction) {
		// Try to insert the transaction into the pending queue
		if pool.pending[addr] == nil {
			pool.pending[addr] = newTxList(true)
		}
		list := pool.pending[addr]
	
		inserted, old := list.Add(tx, pool.config.PriceBump)
		if !inserted { // 如果不能替换, 已经存在一个老的交易了. 删除.
			// An older transaction was better, discard this
			delete(pool.all, hash)
			pool.priced.Removed()
	
			pendingDiscardCounter.Inc(1)
			return
		}
		// Otherwise discard any previous transaction and mark this
		if old != nil { 
			delete(pool.all, old.Hash())
			pool.priced.Removed()
	
			pendingReplaceCounter.Inc(1)
		}
		// Failsafe to work around direct pending inserts (tests)
		if pool.all[hash] == nil {
			pool.all[hash] = tx
			pool.priced.Put(tx)
		}
		// Set the potentially new pending nonce and notify any subsystems of the new tx
		// 把交易加入到队列,并发送消息告诉所有的订阅者, 这个订阅者在eth协议内部. 会接收这个消息并把这个消息通过网路广播出去.
		pool.beats[addr] = time.Now()
		pool.pendingState.SetNonce(addr, tx.Nonce()+1)
		go pool.txFeed.Send(TxPreEvent{tx})
	}
	

removeTx，删除某个交易， 并把所有后续的交易移动到future queue

	
	// removeTx removes a single transaction from the queue, moving all subsequent
	// transactions back to the future queue.
	func (pool *TxPool) removeTx(hash common.Hash) {
		// Fetch the transaction we wish to delete
		tx, ok := pool.all[hash]
		if !ok {
			return
		}
		addr, _ := types.Sender(pool.signer, tx) // already validated during insertion
	
		// Remove it from the list of known transactions
		delete(pool.all, hash)
		pool.priced.Removed()
	
		// Remove the transaction from the pending lists and reset the account nonce
		// 把交易从pending删除， 并把因为这个交易的删除而变得无效的交易放到future queue
		// 然后更新pendingState的状态
		if pending := pool.pending[addr]; pending != nil {
			if removed, invalids := pending.Remove(tx); removed {
				// If no more transactions are left, remove the list
				if pending.Empty() {
					delete(pool.pending, addr)
					delete(pool.beats, addr)
				} else {
					// Otherwise postpone any invalidated transactions
					for _, tx := range invalids {
						pool.enqueueTx(tx.Hash(), tx)
					}
				}
				// Update the account nonce if needed
				if nonce := tx.Nonce(); pool.pendingState.GetNonce(addr) > nonce {
					pool.pendingState.SetNonce(addr, nonce)
				}
				return
			}
		}
		// Transaction is in the future queue
		// 把交易从future queue删除.
		if future := pool.queue[addr]; future != nil {
			future.Remove(tx)
			if future.Empty() {
				delete(pool.queue, addr)
			}
		}
	}



loop是txPool的一个goroutine.也是主要的事件循环.等待和响应外部区块链事件以及各种报告和交易驱逐事件。
	
	// loop is the transaction pool's main event loop, waiting for and reacting to
	// outside blockchain events as well as for various reporting and transaction
	// eviction events.
	func (pool *TxPool) loop() {
		defer pool.wg.Done()
	
		// Start the stats reporting and transaction eviction tickers
		var prevPending, prevQueued, prevStales int
	
		report := time.NewTicker(statsReportInterval)
		defer report.Stop()
	
		evict := time.NewTicker(evictionInterval)
		defer evict.Stop()
	
		journal := time.NewTicker(pool.config.Rejournal)
		defer journal.Stop()
	
		// Track the previous head headers for transaction reorgs
		head := pool.chain.CurrentBlock()
	
		// Keep waiting for and reacting to the various events
		for {
			select {
			// Handle ChainHeadEvent
			// 监听到区块头的事件, 获取到新的区块头.
			// 调用reset方法
			case ev := <-pool.chainHeadCh:
				if ev.Block != nil {
					pool.mu.Lock()
					if pool.chainconfig.IsHomestead(ev.Block.Number()) {
						pool.homestead = true
					}
					pool.reset(head.Header(), ev.Block.Header())
					head = ev.Block
	
					pool.mu.Unlock()
				}
			// Be unsubscribed due to system stopped
			case <-pool.chainHeadSub.Err():
				return
	
			// Handle stats reporting ticks 报告就是打印了一些日志
			case <-report.C:
				pool.mu.RLock()
				pending, queued := pool.stats()
				stales := pool.priced.stales
				pool.mu.RUnlock()
	
				if pending != prevPending || queued != prevQueued || stales != prevStales {
					log.Debug("Transaction pool status report", "executable", pending, "queued", queued, "stales", stales)
					prevPending, prevQueued, prevStales = pending, queued, stales
				}
	
			// Handle inactive account transaction eviction
			// 处理超时的交易信息,
			case <-evict.C:
				pool.mu.Lock()
				for addr := range pool.queue {
					// Skip local transactions from the eviction mechanism
					if pool.locals.contains(addr) {
						continue
					}
					// Any non-locals old enough should be removed
					if time.Since(pool.beats[addr]) > pool.config.Lifetime {
						for _, tx := range pool.queue[addr].Flatten() {
							pool.removeTx(tx.Hash())
						}
					}
				}
				pool.mu.Unlock()
	
			// Handle local transaction journal rotation 处理定时写交易日志的信息.
			case <-journal.C:
				if pool.journal != nil {
					pool.mu.Lock()
					if err := pool.journal.rotate(pool.local()); err != nil {
						log.Warn("Failed to rotate local tx journal", "err", err)
					}
					pool.mu.Unlock()
				}
			}
		}
	}


add 方法, 验证交易并将其插入到future queue. 如果这个交易是替换了当前存在的某个交易,那么会返回之前的那个交易,这样外部就不用调用promote方法. 如果某个新增加的交易被标记为local, 那么它的发送账户会进入白名单,这个账户的关联的交易将不会因为价格的限制或者其他的一些限制被删除.
	
	// add validates a transaction and inserts it into the non-executable queue for
	// later pending promotion and execution. If the transaction is a replacement for
	// an already pending or queued one, it overwrites the previous and returns this
	// so outer code doesn't uselessly call promote.
	//
	// If a newly added transaction is marked as local, its sending account will be
	// whitelisted, preventing any associated transaction from being dropped out of
	// the pool due to pricing constraints.
	func (pool *TxPool) add(tx *types.Transaction, local bool) (bool, error) {
		// If the transaction is already known, discard it
		hash := tx.Hash()
		if pool.all[hash] != nil {
			log.Trace("Discarding already known transaction", "hash", hash)
			return false, fmt.Errorf("known transaction: %x", hash)
		}
		// If the transaction fails basic validation, discard it
		// 如果交易不能通过基本的验证,那么丢弃它
		if err := pool.validateTx(tx, local); err != nil {
			log.Trace("Discarding invalid transaction", "hash", hash, "err", err)
			invalidTxCounter.Inc(1)
			return false, err
		}
		// If the transaction pool is full, discard underpriced transactions
		// 如果交易池满了. 那么删除一些低价的交易.
		if uint64(len(pool.all)) >= pool.config.GlobalSlots+pool.config.GlobalQueue {
			// If the new transaction is underpriced, don't accept it
			// 如果新交易本身就是低价的.那么不接收它
			if pool.priced.Underpriced(tx, pool.locals) {
				log.Trace("Discarding underpriced transaction", "hash", hash, "price", tx.GasPrice())
				underpricedTxCounter.Inc(1)
				return false, ErrUnderpriced
			}
			// New transaction is better than our worse ones, make room for it
			// 否则删除低价值的给他腾空间.
			drop := pool.priced.Discard(len(pool.all)-int(pool.config.GlobalSlots+pool.config.GlobalQueue-1), pool.locals)
			for _, tx := range drop {
				log.Trace("Discarding freshly underpriced transaction", "hash", tx.Hash(), "price", tx.GasPrice())
				underpricedTxCounter.Inc(1)
				pool.removeTx(tx.Hash())
			}
		}
		// If the transaction is replacing an already pending one, do directly
		from, _ := types.Sender(pool.signer, tx) // already validated
		if list := pool.pending[from]; list != nil && list.Overlaps(tx) {
			// Nonce already pending, check if required price bump is met
			// 如果交易对应的Nonce已经在pending队列了,那么产看是否能够替换.
			inserted, old := list.Add(tx, pool.config.PriceBump)
			if !inserted {
				pendingDiscardCounter.Inc(1)
				return false, ErrReplaceUnderpriced
			}
			// New transaction is better, replace old one
			if old != nil {
				delete(pool.all, old.Hash())
				pool.priced.Removed()
				pendingReplaceCounter.Inc(1)
			}
			pool.all[tx.Hash()] = tx
			pool.priced.Put(tx)
			pool.journalTx(from, tx)
	
			log.Trace("Pooled new executable transaction", "hash", hash, "from", from, "to", tx.To())
			return old != nil, nil
		}
		// New transaction isn't replacing a pending one, push into queue
		// 新交易不能替换pending里面的任意一个交易,那么把他push到futuren 队列里面.
		replace, err := pool.enqueueTx(hash, tx)
		if err != nil {
			return false, err
		}
		// Mark local addresses and journal local transactions
		if local {
			pool.locals.add(from)
		}
		// 如果是本地的交易,会被记录进入journalTx
		pool.journalTx(from, tx)
	
		log.Trace("Pooled new future transaction", "hash", hash, "from", from, "to", tx.To())
		return replace, nil
	}


validateTx 使用一致性规则来检查一个交易是否有效,并采用本地节点的一些启发式的限制.

	// validateTx checks whether a transaction is valid according to the consensus
	// rules and adheres to some heuristic limits of the local node (price and size).
	func (pool *TxPool) validateTx(tx *types.Transaction, local bool) error {
		// Heuristic limit, reject transactions over 32KB to prevent DOS attacks
		if tx.Size() > 32*1024 {
			return ErrOversizedData
		}
		// Transactions can't be negative. This may never happen using RLP decoded
		// transactions but may occur if you create a transaction using the RPC.
		if tx.Value().Sign() < 0 {
			return ErrNegativeValue
		}
		// Ensure the transaction doesn't exceed the current block limit gas.
		if pool.currentMaxGas.Cmp(tx.Gas()) < 0 {
			return ErrGasLimit
		}
		// Make sure the transaction is signed properly
		// 确保交易被正确签名.
		from, err := types.Sender(pool.signer, tx)
		if err != nil {
			return ErrInvalidSender
		}
		// Drop non-local transactions under our own minimal accepted gas price
		local = local || pool.locals.contains(from) // account may be local even if the transaction arrived from the network
		// 如果不是本地的交易,并且GasPrice低于我们的设置,那么也不会接收.
		if !local && pool.gasPrice.Cmp(tx.GasPrice()) > 0 {
			return ErrUnderpriced
		}
		// Ensure the transaction adheres to nonce ordering
		// 确保交易遵守了Nonce的顺序
		if pool.currentState.GetNonce(from) > tx.Nonce() {
			return ErrNonceTooLow
		}
		// Transactor should have enough funds to cover the costs
		// cost == V + GP * GL
		// 确保用户有足够的余额来支付.
		if pool.currentState.GetBalance(from).Cmp(tx.Cost()) < 0 {
			return ErrInsufficientFunds
		}
		intrGas := IntrinsicGas(tx.Data(), tx.To() == nil, pool.homestead)
		// 如果交易是一个合约创建或者调用. 那么看看是否有足够的 初始Gas.
		if tx.Gas().Cmp(intrGas) < 0 {
			return ErrIntrinsicGas
		}
		return nil
	}
