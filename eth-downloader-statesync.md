statesync 用来获取pivot point所指定的区块的所有的state 的trie树，也就是所有的账号的信息，包括普通账号和合约账户。

## 数据结构
stateSync调度下载由给定state root所定义的特定state trie的请求。

	// stateSync schedules requests for downloading a particular state trie defined
	// by a given state root.
	type stateSync struct {
		d *Downloader // Downloader instance to access and manage current peerset
	
		sched  *trie.TrieSync             // State trie sync scheduler defining the tasks
		keccak hash.Hash                  // Keccak256 hasher to verify deliveries with
		tasks  map[common.Hash]*stateTask // Set of tasks currently queued for retrieval
	
		numUncommitted   int
		bytesUncommitted int
	
		deliver    chan *stateReq // Delivery channel multiplexing peer responses
		cancel     chan struct{}  // Channel to signal a termination request
		cancelOnce sync.Once      // Ensures cancel only ever gets called once
		done       chan struct{}  // Channel to signal termination completion
		err        error          // Any error hit during sync (set before completion)
	}

构造函数

	func newStateSync(d *Downloader, root common.Hash) *stateSync {
		return &stateSync{
			d:       d,
			sched:   state.NewStateSync(root, d.stateDB),
			keccak:  sha3.NewKeccak256(),
			tasks:   make(map[common.Hash]*stateTask),
			deliver: make(chan *stateReq),
			cancel:  make(chan struct{}),
			done:    make(chan struct{}),
		}
	}

NewStateSync
	
	// NewStateSync create a new state trie download scheduler.
	func NewStateSync(root common.Hash, database trie.DatabaseReader) *trie.TrieSync {
		var syncer *trie.TrieSync
		callback := func(leaf []byte, parent common.Hash) error {
			var obj Account
			if err := rlp.Decode(bytes.NewReader(leaf), &obj); err != nil {
				return err
			}
			syncer.AddSubTrie(obj.Root, 64, parent, nil)
			syncer.AddRawEntry(common.BytesToHash(obj.CodeHash), 64, parent)
			return nil
		}
		syncer = trie.NewTrieSync(root, database, callback)
		return syncer
	}

syncState， 这个函数是downloader调用的。

	// syncState starts downloading state with the given root hash.
	func (d *Downloader) syncState(root common.Hash) *stateSync {
		s := newStateSync(d, root)
		select {
		case d.stateSyncStart <- s:
		case <-d.quitCh:
			s.err = errCancelStateFetch
			close(s.done)
		}
		return s
	}

## 启动
在downloader中启动了一个新的goroutine 来运行stateFetcher函数。 这个函数首先试图往stateSyncStart通道来以获取信息。  而syncState这个函数会给stateSyncStart通道发送数据。

	// stateFetcher manages the active state sync and accepts requests
	// on its behalf.
	func (d *Downloader) stateFetcher() {
		for {
			select {
			case s := <-d.stateSyncStart:
				for next := s; next != nil; { // 这个for循环代表了downloader可以通过发送信号来随时改变需要同步的对象。
					next = d.runStateSync(next)
				}
			case <-d.stateCh:
				// Ignore state responses while no sync is running.
			case <-d.quitCh:
				return
			}
		}
	}

我们下面看看哪里会调用syncState()函数。processFastSyncContent这个函数会在最开始发现peer的时候启动。

	// processFastSyncContent takes fetch results from the queue and writes them to the
	// database. It also controls the synchronisation of state nodes of the pivot block.
	func (d *Downloader) processFastSyncContent(latest *types.Header) error {
		// Start syncing state of the reported head block.
		// This should get us most of the state of the pivot block.
		stateSync := d.syncState(latest.Root)

	

runStateSync,这个方法从stateCh获取已经下载好的状态，然后把他投递到deliver通道上等待别人处理。
	
	// runStateSync runs a state synchronisation until it completes or another root
	// hash is requested to be switched over to.
	func (d *Downloader) runStateSync(s *stateSync) *stateSync {
		var (
			active   = make(map[string]*stateReq) // Currently in-flight requests
			finished []*stateReq                  // Completed or failed requests
			timeout  = make(chan *stateReq)       // Timed out active requests
		)
		defer func() {
			// Cancel active request timers on exit. Also set peers to idle so they're
			// available for the next sync.
			for _, req := range active {
				req.timer.Stop()
				req.peer.SetNodeDataIdle(len(req.items))
			}
		}()
		// Run the state sync.
		// 运行状态同步
		go s.run()
		defer s.Cancel()
	
		// Listen for peer departure events to cancel assigned tasks
		peerDrop := make(chan *peerConnection, 1024)
		peerSub := s.d.peers.SubscribePeerDrops(peerDrop)
		defer peerSub.Unsubscribe()
	
		for {
			// Enable sending of the first buffered element if there is one.
			var (
				deliverReq   *stateReq
				deliverReqCh chan *stateReq
			)
			if len(finished) > 0 {
				deliverReq = finished[0]
				deliverReqCh = s.deliver
			}
	
			select {
			// The stateSync lifecycle:
			// 另外一个stateSync申请运行。 我们退出。
			case next := <-d.stateSyncStart:
				return next
	
			case <-s.done:
				return nil
	
			// Send the next finished request to the current sync:
			// 发送已经下载好的数据给sync
			case deliverReqCh <- deliverReq:
				finished = append(finished[:0], finished[1:]...)
	
			// Handle incoming state packs:
			// 处理进入的数据包。 downloader接收到state的数据会发送到这个通道上面。
			case pack := <-d.stateCh:
				// Discard any data not requested (or previsouly timed out)
				req := active[pack.PeerId()]
				if req == nil {
					log.Debug("Unrequested node data", "peer", pack.PeerId(), "len", pack.Items())
					continue
				}
				// Finalize the request and queue up for processing
				req.timer.Stop()
				req.response = pack.(*statePack).states
	
				finished = append(finished, req)
				delete(active, pack.PeerId())
	
				// Handle dropped peer connections:
			case p := <-peerDrop:
				// Skip if no request is currently pending
				req := active[p.id]
				if req == nil {
					continue
				}
				// Finalize the request and queue up for processing
				req.timer.Stop()
				req.dropped = true
	
				finished = append(finished, req)
				delete(active, p.id)
	
			// Handle timed-out requests:
			case req := <-timeout:
				// If the peer is already requesting something else, ignore the stale timeout.
				// This can happen when the timeout and the delivery happens simultaneously,
				// causing both pathways to trigger.
				if active[req.peer.id] != req {
					continue
				}
				// Move the timed out data back into the download queue
				finished = append(finished, req)
				delete(active, req.peer.id)
	
			// Track outgoing state requests:
			case req := <-d.trackStateReq:
				// If an active request already exists for this peer, we have a problem. In
				// theory the trie node schedule must never assign two requests to the same
				// peer. In practive however, a peer might receive a request, disconnect and
				// immediately reconnect before the previous times out. In this case the first
				// request is never honored, alas we must not silently overwrite it, as that
				// causes valid requests to go missing and sync to get stuck.
				if old := active[req.peer.id]; old != nil {
					log.Warn("Busy peer assigned new state fetch", "peer", old.peer.id)
	
					// Make sure the previous one doesn't get siletly lost
					old.timer.Stop()
					old.dropped = true
	
					finished = append(finished, old)
				}
				// Start a timer to notify the sync loop if the peer stalled.
				req.timer = time.AfterFunc(req.timeout, func() {
					select {
					case timeout <- req:
					case <-s.done:
						// Prevent leaking of timer goroutines in the unlikely case where a
						// timer is fired just before exiting runStateSync.
					}
				})
				active[req.peer.id] = req
			}
		}
	}


run和loop方法，获取任务，分配任务，获取结果。

	func (s *stateSync) run() {
		s.err = s.loop()
		close(s.done)
	}
	
	// loop is the main event loop of a state trie sync. It it responsible for the
	// assignment of new tasks to peers (including sending it to them) as well as
	// for the processing of inbound data. Note, that the loop does not directly
	// receive data from peers, rather those are buffered up in the downloader and
	// pushed here async. The reason is to decouple processing from data receipt
	// and timeouts.
	func (s *stateSync) loop() error {
		// Listen for new peer events to assign tasks to them
		newPeer := make(chan *peerConnection, 1024)
		peerSub := s.d.peers.SubscribeNewPeers(newPeer)
		defer peerSub.Unsubscribe()
	
		// Keep assigning new tasks until the sync completes or aborts
		// 一直等到 sync完成或者被被终止
		for s.sched.Pending() > 0 {
			// 把数据从缓存里面刷新到持久化存储里面。 这也就是命令行 --cache指定的大小。
			if err := s.commit(false); err != nil {
				return err
			}
			// 指派任务，
			s.assignTasks()
			// Tasks assigned, wait for something to happen
			select {
			case <-newPeer:
				// New peer arrived, try to assign it download tasks
	
			case <-s.cancel:
				return errCancelStateFetch
	
			case req := <-s.deliver:
				// 接收到runStateSync方法投递过来的返回信息，注意 返回信息里面包含了成功请求的也包含了未成功请求的。
				// Response, disconnect or timeout triggered, drop the peer if stalling
				log.Trace("Received node data response", "peer", req.peer.id, "count", len(req.response), "dropped", req.dropped, "timeout", !req.dropped && req.timedOut())
				if len(req.items) <= 2 && !req.dropped && req.timedOut() {
					// 2 items are the minimum requested, if even that times out, we've no use of
					// this peer at the moment.
					log.Warn("Stalling state sync, dropping peer", "peer", req.peer.id)
					s.d.dropPeer(req.peer.id)
				}
				// Process all the received blobs and check for stale delivery
				stale, err := s.process(req)
				if err != nil {
					log.Warn("Node data write error", "err", err)
					return err
				}
				// The the delivery contains requested data, mark the node idle (otherwise it's a timed out delivery)
				if !stale {
					req.peer.SetNodeDataIdle(len(req.response))
				}
			}
		}
		return s.commit(true)
	}