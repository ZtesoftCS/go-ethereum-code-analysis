fetcher包含基于块通知的同步。当我们接收到NewBlockHashesMsg消息得时候，我们只收到了很多Block的hash值。 需要通过hash值来同步区块，然后更新本地区块链。 fetcher就提供了这样的功能。


数据结构

	// announce is the hash notification of the availability of a new block in the
	// network.
	// announce 是一个hash通知，表示网络上有合适的新区块出现。
	type announce struct {
		hash   common.Hash   // Hash of the block being announced //新区块的hash值
		number uint64        // Number of the block being announced (0 = unknown | old protocol) 区块的高度值，
		header *types.Header // Header of the block partially reassembled (new protocol)	重新组装的区块头
		time   time.Time     // Timestamp of the announcement
	
		origin string // Identifier of the peer originating the notification
	
		fetchHeader headerRequesterFn // Fetcher function to retrieve the header of an announced block  获取区块头的函数指针， 里面包含了peer的信息。就是说找谁要这个区块头
		fetchBodies bodyRequesterFn   // Fetcher function to retrieve the body of an announced block 获取区块体的函数指针
	}
	
	// headerFilterTask represents a batch of headers needing fetcher filtering.
	type headerFilterTask struct {
		peer    string          // The source peer of block headers
		headers []*types.Header // Collection of headers to filter
		time    time.Time       // Arrival time of the headers
	}
	
	// headerFilterTask represents a batch of block bodies (transactions and uncles)
	// needing fetcher filtering.
	type bodyFilterTask struct {
		peer         string                 // The source peer of block bodies
		transactions [][]*types.Transaction // Collection of transactions per block bodies
		uncles       [][]*types.Header      // Collection of uncles per block bodies
		time         time.Time              // Arrival time of the blocks' contents
	}
	
	// inject represents a schedules import operation. 
	// 当节点收到NewBlockMsg的消息时候，会插入一个区块
	type inject struct {
		origin string
		block  *types.Block
	}
	
	// Fetcher is responsible for accumulating block announcements from various peers
	// and scheduling them for retrieval.
	type Fetcher struct {
		// Various event channels
		notify chan *announce	//announce的通道，
		inject chan *inject		//inject的通道
	
		blockFilter  chan chan []*types.Block	 //通道的通道？
		headerFilter chan chan *headerFilterTask
		bodyFilter   chan chan *bodyFilterTask
	
		done chan common.Hash
		quit chan struct{}
	
		// Announce states
		announces  map[string]int              // Per peer announce counts to prevent memory exhaustion key是peer的名字， value是announce的count， 为了避免内存占用太大。
		announced  map[common.Hash][]*announce // Announced blocks, scheduled for fetching 等待调度fetching的announce
		fetching   map[common.Hash]*announce   // Announced blocks, currently fetching 正在fetching的announce
		fetched    map[common.Hash][]*announce // Blocks with headers fetched, scheduled for body retrieval // 已经获取区块头的，等待获取区块body
		completing map[common.Hash]*announce   // Blocks with headers, currently body-completing  //头和体都已经获取完成的announce
	
		// Block cache
		queue  *prque.Prque            // Queue containing the import operations (block number sorted) //包含了import操作的队列(按照区块号排列)
		queues map[string]int          // Per peer block counts to prevent memory exhaustion key是peer，value是block数量。 避免内存消耗太多。
		queued map[common.Hash]*inject // Set of already queued blocks (to dedup imports)  已经放入队列的区块。 为了去重。
	
		// Callbacks  依赖了一些回调函数。
		getBlock       blockRetrievalFn   // Retrieves a block from the local chain
		verifyHeader   headerVerifierFn   // Checks if a block's headers have a valid proof of work
		broadcastBlock blockBroadcasterFn // Broadcasts a block to connected peers
		chainHeight    chainHeightFn      // Retrieves the current chain's height
		insertChain    chainInsertFn      // Injects a batch of blocks into the chain
		dropPeer       peerDropFn         // Drops a peer for misbehaving
	
		// Testing hooks  仅供测试使用。
		announceChangeHook func(common.Hash, bool) // Method to call upon adding or deleting a hash from the announce list
		queueChangeHook    func(common.Hash, bool) // Method to call upon adding or deleting a block from the import queue
		fetchingHook       func([]common.Hash)     // Method to call upon starting a block (eth/61) or header (eth/62) fetch
		completingHook     func([]common.Hash)     // Method to call upon starting a block body fetch (eth/62)
		importedHook       func(*types.Block)      // Method to call upon successful block import (both eth/61 and eth/62)
	}

启动fetcher， 直接启动了一个goroutine来处理。 这个函数有点长。 后续再分析。

	// Start boots up the announcement based synchroniser, accepting and processing
	// hash notifications and block fetches until termination requested.
	func (f *Fetcher) Start() {
		go f.loop()
	}


loop函数函数太长。 我先帖一个省略版本的出来。fetcher通过四个map(announced,fetching,fetched,completing )记录了announce的状态(等待fetch,正在fetch,fetch完头等待fetch body, fetch完成)。 loop其实通过定时器和各种消息来对各种map里面的announce进行状态转换。


	// Loop is the main fetcher loop, checking and processing various notification
	// events.
	func (f *Fetcher) loop() {
		// Iterate the block fetching until a quit is requested
		fetchTimer := time.NewTimer(0)  //fetch的定时器。
		completeTimer := time.NewTimer(0) // compelte的定时器。
	
		for {
			// Clean up any expired block fetches
			// 如果fetching的时间超过5秒，那么放弃掉这个fetching
			for hash, announce := range f.fetching {
				if time.Since(announce.time) > fetchTimeout {
					f.forgetHash(hash)
				}
			}
			// Import any queued blocks that could potentially fit
			// 这个fetcher.queue里面缓存了已经完成fetch的block等待按照顺序插入到本地的区块链中
			//fetcher.queue是一个优先级队列。 优先级别就是他们的区块号的负数，这样区块数小的排在最前面。
			height := f.chainHeight()
			for !f.queue.Empty() { // 
				op := f.queue.PopItem().(*inject)
				if f.queueChangeHook != nil {
					f.queueChangeHook(op.block.Hash(), false)
				}
				// If too high up the chain or phase, continue later
				number := op.block.NumberU64()
				if number > height+1 { //当前的区块的高度太高，还不能import
					f.queue.Push(op, -float32(op.block.NumberU64()))
					if f.queueChangeHook != nil {
						f.queueChangeHook(op.block.Hash(), true)
					}
					break
				}
				// Otherwise if fresh and still unknown, try and import
				hash := op.block.Hash()
				if number+maxUncleDist < height || f.getBlock(hash) != nil {
					// 区块的高度太低 低于当前的height-maxUncleDist
					// 或者区块已经被import了
					f.forgetBlock(hash)
					continue
				}
				// 插入区块
				f.insert(op.origin, op.block)
			}
			// Wait for an outside event to occur
			select {
			case <-f.quit:
				// Fetcher terminating, abort all operations
				return
	
			case notification := <-f.notify: //在接收到NewBlockHashesMsg的时候，对于本地区块链还没有的区块的hash值会调用fetcher的Notify方法发送到notify通道。
				...
	
			case op := <-f.inject: // 在接收到NewBlockMsg的时候会调用fetcher的Enqueue方法，这个方法会把当前接收到的区块发送到inject通道。
				...
				f.enqueue(op.origin, op.block)
	
			case hash := <-f.done: //当完成一个区块的import的时候会发送该区块的hash值到done通道。
				...
	
			case <-fetchTimer.C: // fetchTimer定时器，定期对需要fetch的区块头进行fetch
				...
	
			case <-completeTimer.C: // completeTimer定时器定期对需要fetch的区块体进行fetch
				...
	
			case filter := <-f.headerFilter: //当接收到BlockHeadersMsg的消息的时候(接收到一些区块头),会把这些消息投递到headerFilter队列。 这边会把属于fetcher请求的数据留下，其他的会返回出来，给其他系统使用。
				...
	
			case filter := <-f.bodyFilter: //当接收到BlockBodiesMsg消息的时候，会把这些消息投递给bodyFilter队列。这边会把属于fetcher请求的数据留下，其他的会返回出来，给其他系统使用。
				...
			}
		}
	}

### 区块头的过滤流程
#### FilterHeaders请求
FilterHeaders方法在接收到BlockHeadersMsg的时候被调用。这个方法首先投递了一个channel filter到headerFilter。 然后往filter投递了一个headerFilterTask的任务。然后阻塞等待filter队列返回消息。


	// FilterHeaders extracts all the headers that were explicitly requested by the fetcher,
	// returning those that should be handled differently.
	func (f *Fetcher) FilterHeaders(peer string, headers []*types.Header, time time.Time) []*types.Header {
		log.Trace("Filtering headers", "peer", peer, "headers", len(headers))
	
		// Send the filter channel to the fetcher
		filter := make(chan *headerFilterTask)
	
		select {
		case f.headerFilter <- filter:
		case <-f.quit:
			return nil
		}
		// Request the filtering of the header list
		select {
		case filter <- &headerFilterTask{peer: peer, headers: headers, time: time}:
		case <-f.quit:
			return nil
		}
		// Retrieve the headers remaining after filtering
		select {
		case task := <-filter:
			return task.headers
		case <-f.quit:
			return nil
		}
	}


#### headerFilter的处理
这个处理在loop()的goroutine中。

	case filter := <-f.headerFilter:
				// Headers arrived from a remote peer. Extract those that were explicitly
				// requested by the fetcher, and return everything else so it's delivered
				// to other parts of the system.
				var task *headerFilterTask
				select {
				case task = <-filter:
				case <-f.quit:
					return
				}
				headerFilterInMeter.Mark(int64(len(task.headers)))
	
				// Split the batch of headers into unknown ones (to return to the caller),
				// known incomplete ones (requiring body retrievals) and completed blocks.
				unknown, incomplete, complete := []*types.Header{}, []*announce{}, []*types.Block{}
				for _, header := range task.headers {
					hash := header.Hash()
	
					// Filter fetcher-requested headers from other synchronisation algorithms
					// 根据情况看这个是否是我们的请求返回的信息。
					if announce := f.fetching[hash]; announce != nil && announce.origin == task.peer && f.fetched[hash] == nil && f.completing[hash] == nil && f.queued[hash] == nil {
						// If the delivered header does not match the promised number, drop the announcer
						// 如果返回的header的区块高度和我们请求的不同，那么删除掉返回这个header的peer。 并且忘记掉这个hash(以便于重新获取区块信息)
						if header.Number.Uint64() != announce.number {
							log.Trace("Invalid block number fetched", "peer", announce.origin, "hash", header.Hash(), "announced", announce.number, "provided", header.Number)
							f.dropPeer(announce.origin)
							f.forgetHash(hash)
							continue
						}
						// Only keep if not imported by other means
						if f.getBlock(hash) == nil {
							announce.header = header
							announce.time = task.time
	
							// If the block is empty (header only), short circuit into the final import queue
							// 根据区块头查看，如果这个区块不包含任何交易或者是Uncle区块。那么我们就不用获取区块的body了。 那么直接插入完成列表。
							if header.TxHash == types.DeriveSha(types.Transactions{}) && header.UncleHash == types.CalcUncleHash([]*types.Header{}) {
								log.Trace("Block empty, skipping body retrieval", "peer", announce.origin, "number", header.Number, "hash", header.Hash())
	
								block := types.NewBlockWithHeader(header)
								block.ReceivedAt = task.time
	
								complete = append(complete, block)
								f.completing[hash] = announce
								continue
							}
							// Otherwise add to the list of blocks needing completion
							// 否则，插入到未完成列表等待fetch blockbody
							incomplete = append(incomplete, announce)
						} else {
							log.Trace("Block already imported, discarding header", "peer", announce.origin, "number", header.Number, "hash", header.Hash())
							f.forgetHash(hash)
						}
					} else {
						// Fetcher doesn't know about it, add to the return list
						// Fetcher并不知道这个header。 增加到返回列表等待返回。
						unknown = append(unknown, header)
					}
				}
				headerFilterOutMeter.Mark(int64(len(unknown)))
				select {
				// 把返回结果返回。
				case filter <- &headerFilterTask{headers: unknown, time: task.time}:
				case <-f.quit:
					return
				}
				// Schedule the retrieved headers for body completion
				for _, announce := range incomplete {
					hash := announce.header.Hash()
					if _, ok := f.completing[hash]; ok { //如果已经在其他的地方完成
						continue
					}
					// 放到等待获取body的map等待处理。
					f.fetched[hash] = append(f.fetched[hash], announce)
					if len(f.fetched) == 1 { //如果fetched map只有刚刚加入的一个元素。 那么重置计时器。
						f.rescheduleComplete(completeTimer)
					}
				}
				// Schedule the header-only blocks for import
				// 这些只有header的区块放入queue等待import
				for _, block := range complete {
					if announce := f.completing[block.Hash()]; announce != nil {
						f.enqueue(announce.origin, block)
					}
				}


#### bodyFilter的处理
和上面的处理类似。

		case filter := <-f.bodyFilter:
			// Block bodies arrived, extract any explicitly requested blocks, return the rest
			var task *bodyFilterTask
			select {
			case task = <-filter:
			case <-f.quit:
				return
			}
			bodyFilterInMeter.Mark(int64(len(task.transactions)))

			blocks := []*types.Block{}
			for i := 0; i < len(task.transactions) && i < len(task.uncles); i++ {
				// Match up a body to any possible completion request
				matched := false

				for hash, announce := range f.completing {
					if f.queued[hash] == nil {
						txnHash := types.DeriveSha(types.Transactions(task.transactions[i]))
						uncleHash := types.CalcUncleHash(task.uncles[i])

						if txnHash == announce.header.TxHash && uncleHash == announce.header.UncleHash && announce.origin == task.peer {
							// Mark the body matched, reassemble if still unknown
							matched = true
							
							if f.getBlock(hash) == nil {
								block := types.NewBlockWithHeader(announce.header).WithBody(task.transactions[i], task.uncles[i])
								block.ReceivedAt = task.time

								blocks = append(blocks, block)
							} else {
								f.forgetHash(hash)
							}
						}
					}
				}
				if matched {
					task.transactions = append(task.transactions[:i], task.transactions[i+1:]...)
					task.uncles = append(task.uncles[:i], task.uncles[i+1:]...)
					i--
					continue
				}
			}

			bodyFilterOutMeter.Mark(int64(len(task.transactions)))
			select {
			case filter <- task:
			case <-f.quit:
				return
			}
			// Schedule the retrieved blocks for ordered import
			for _, block := range blocks {
				if announce := f.completing[block.Hash()]; announce != nil {
					f.enqueue(announce.origin, block)
				}
			}

#### notification的处理
在接收到NewBlockHashesMsg的时候，对于本地区块链还没有的区块的hash值会调用fetcher的Notify方法发送到notify通道。


	// Notify announces the fetcher of the potential availability of a new block in
	// the network.
	func (f *Fetcher) Notify(peer string, hash common.Hash, number uint64, time time.Time,
		headerFetcher headerRequesterFn, bodyFetcher bodyRequesterFn) error {
		block := &announce{
			hash:        hash,
			number:      number,
			time:        time,
			origin:      peer,
			fetchHeader: headerFetcher,
			fetchBodies: bodyFetcher,
		}
		select {
		case f.notify <- block:
			return nil
		case <-f.quit:
			return errTerminated
		}
	}

在loop中的处理，主要是检查一下然后加入了announced这个容器等待定时处理。

	case notification := <-f.notify:
			// A block was announced, make sure the peer isn't DOSing us
			propAnnounceInMeter.Mark(1)

			count := f.announces[notification.origin] + 1
			if count > hashLimit {  //hashLimit 256 一个远端最多只存在256个announces
				log.Debug("Peer exceeded outstanding announces", "peer", notification.origin, "limit", hashLimit)
				propAnnounceDOSMeter.Mark(1)
				break
			}
			// If we have a valid block number, check that it's potentially useful
			// 查看是潜在是否有用。 根据这个区块号和本地区块链的距离， 太大和太小对于我们都没有意义。
			if notification.number > 0 {
				if dist := int64(notification.number) - int64(f.chainHeight()); dist < -maxUncleDist || dist > maxQueueDist {
					log.Debug("Peer discarded announcement", "peer", notification.origin, "number", notification.number, "hash", notification.hash, "distance", dist)
					propAnnounceDropMeter.Mark(1)
					break
				}
			}
			// All is well, schedule the announce if block's not yet downloading
			// 检查我们是否已经存在了。
			if _, ok := f.fetching[notification.hash]; ok {
				break
			}
			if _, ok := f.completing[notification.hash]; ok {
				break
			}
			f.announces[notification.origin] = count
			f.announced[notification.hash] = append(f.announced[notification.hash], notification)
			if f.announceChangeHook != nil && len(f.announced[notification.hash]) == 1 {
				f.announceChangeHook(notification.hash, true)
			}
			if len(f.announced) == 1 {
				f.rescheduleFetch(fetchTimer)
			}

#### Enqueue处理
在接收到NewBlockMsg的时候会调用fetcher的Enqueue方法，这个方法会把当前接收到的区块发送到inject通道。 可以看到这个方法生成了一个inject对象然后发送到inject通道
	
	// Enqueue tries to fill gaps the the fetcher's future import queue.
	func (f *Fetcher) Enqueue(peer string, block *types.Block) error {
		op := &inject{
			origin: peer,
			block:  block,
		}
		select {
		case f.inject <- op:
			return nil
		case <-f.quit:
			return errTerminated
		}
	}

inject通道处理非常简单，直接加入到队列等待import

	case op := <-f.inject:
			// A direct block insertion was requested, try and fill any pending gaps
			propBroadcastInMeter.Mark(1)
			f.enqueue(op.origin, op.block)

enqueue

	// enqueue schedules a new future import operation, if the block to be imported
	// has not yet been seen.
	func (f *Fetcher) enqueue(peer string, block *types.Block) {
		hash := block.Hash()
	
		// Ensure the peer isn't DOSing us
		count := f.queues[peer] + 1
		if count > blockLimit { blockLimit 64 如果缓存的对方的block太多。
			log.Debug("Discarded propagated block, exceeded allowance", "peer", peer, "number", block.Number(), "hash", hash, "limit", blockLimit)
			propBroadcastDOSMeter.Mark(1)
			f.forgetHash(hash)
			return
		}
		// Discard any past or too distant blocks
		// 距离我们的区块链太远。
		if dist := int64(block.NumberU64()) - int64(f.chainHeight()); dist < -maxUncleDist || dist > maxQueueDist { 
			log.Debug("Discarded propagated block, too far away", "peer", peer, "number", block.Number(), "hash", hash, "distance", dist)
			propBroadcastDropMeter.Mark(1)
			f.forgetHash(hash)
			return
		}
		// Schedule the block for future importing
		// 插入到队列。
		if _, ok := f.queued[hash]; !ok {
			op := &inject{
				origin: peer,
				block:  block,
			}
			f.queues[peer] = count
			f.queued[hash] = op
			f.queue.Push(op, -float32(block.NumberU64()))
			if f.queueChangeHook != nil {
				f.queueChangeHook(op.block.Hash(), true)
			}
			log.Debug("Queued propagated block", "peer", peer, "number", block.Number(), "hash", hash, "queued", f.queue.Size())
		}
	}

#### 定时器的处理
一共存在两个定时器。fetchTimer和completeTimer，分别负责获取区块头和获取区块body。

状态转换 announced  --fetchTimer(fetch header)---> fetching  --(headerFilter)--> fetched --completeTimer(fetch body)-->completing --(bodyFilter)--> enqueue --task.done--> forgetHash

发现一个问题。 completing的容器有可能泄露。如果发送了一个hash的body请求。 但是请求失败，对方并没有返回。 这个时候completing容器没有清理。 是否有可能导致问题。

		case <-fetchTimer.C:
			// At least one block's timer ran out, check for needing retrieval
			request := make(map[string][]common.Hash)

			for hash, announces := range f.announced {
				// TODO 这里的时间限制是什么意思
				// 最早收到的announce，并经过arriveTimeout-gatherSlack这么长的时间。
				if time.Since(announces[0].time) > arriveTimeout-gatherSlack {
					// Pick a random peer to retrieve from, reset all others
					// announces代表了同一个区块的来自多个peer的多个announce
					announce := announces[rand.Intn(len(announces))]
					f.forgetHash(hash)

					// If the block still didn't arrive, queue for fetching
					if f.getBlock(hash) == nil {
						request[announce.origin] = append(request[announce.origin], hash)
						f.fetching[hash] = announce
					}
				}
			}
			// Send out all block header requests
			// 发送所有的请求。
			for peer, hashes := range request {
				log.Trace("Fetching scheduled headers", "peer", peer, "list", hashes)

				// Create a closure of the fetch and schedule in on a new thread
				fetchHeader, hashes := f.fetching[hashes[0]].fetchHeader, hashes
				go func() {
					if f.fetchingHook != nil {
						f.fetchingHook(hashes)
					}
					for _, hash := range hashes {
						headerFetchMeter.Mark(1)
						fetchHeader(hash) // Suboptimal, but protocol doesn't allow batch header retrievals
					}
				}()
			}
			// Schedule the next fetch if blocks are still pending
			f.rescheduleFetch(fetchTimer)

		case <-completeTimer.C:
			// At least one header's timer ran out, retrieve everything
			request := make(map[string][]common.Hash)

			for hash, announces := range f.fetched {
				// Pick a random peer to retrieve from, reset all others
				announce := announces[rand.Intn(len(announces))]
				f.forgetHash(hash)

				// If the block still didn't arrive, queue for completion
				if f.getBlock(hash) == nil {
					request[announce.origin] = append(request[announce.origin], hash)
					f.completing[hash] = announce
				}
			}
			// Send out all block body requests
			for peer, hashes := range request {
				log.Trace("Fetching scheduled bodies", "peer", peer, "list", hashes)

				// Create a closure of the fetch and schedule in on a new thread
				if f.completingHook != nil {
					f.completingHook(hashes)
				}
				bodyFetchMeter.Mark(int64(len(hashes)))
				go f.completing[hashes[0]].fetchBodies(hashes)
			}
			// Schedule the next fetch if blocks are still pending
			f.rescheduleComplete(completeTimer)



#### 其他的一些方法

fetcher insert方法。 这个方法把给定的区块插入本地的区块链。

	// insert spawns a new goroutine to run a block insertion into the chain. If the
	// block's number is at the same height as the current import phase, if updates
	// the phase states accordingly.
	func (f *Fetcher) insert(peer string, block *types.Block) {
		hash := block.Hash()
	
		// Run the import on a new thread
		log.Debug("Importing propagated block", "peer", peer, "number", block.Number(), "hash", hash)
		go func() {
			defer func() { f.done <- hash }()
	
			// If the parent's unknown, abort insertion
			parent := f.getBlock(block.ParentHash())
			if parent == nil {
				log.Debug("Unknown parent of propagated block", "peer", peer, "number", block.Number(), "hash", hash, "parent", block.ParentHash())
				return
			}
			// Quickly validate the header and propagate the block if it passes
			// 如果区块头通过验证，那么马上对区块进行广播。 NewBlockMsg
			switch err := f.verifyHeader(block.Header()); err {
			case nil:
				// All ok, quickly propagate to our peers
				propBroadcastOutTimer.UpdateSince(block.ReceivedAt)
				go f.broadcastBlock(block, true)
	
			case consensus.ErrFutureBlock:
				// Weird future block, don't fail, but neither propagate
	
			default:
				// Something went very wrong, drop the peer
				log.Debug("Propagated block verification failed", "peer", peer, "number", block.Number(), "hash", hash, "err", err)
				f.dropPeer(peer)
				return
			}
			// Run the actual import and log any issues
			if _, err := f.insertChain(types.Blocks{block}); err != nil {
				log.Debug("Propagated block import failed", "peer", peer, "number", block.Number(), "hash", hash, "err", err)
				return
			}
			// If import succeeded, broadcast the block
			// 如果插入成功， 那么广播区块， 第二个参数为false。那么只会对区块的hash进行广播。NewBlockHashesMsg
			propAnnounceOutTimer.UpdateSince(block.ReceivedAt)
			go f.broadcastBlock(block, false)
	
			// Invoke the testing hook if needed
			if f.importedHook != nil {
				f.importedHook(block)
			}
		}()
	}