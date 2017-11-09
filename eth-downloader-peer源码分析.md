peer模块包含了downloader使用的peer节点，封装了吞吐量，是否空闲，并记录了之前失败的信息。


## peer
	
	// peerConnection represents an active peer from which hashes and blocks are retrieved.
	type peerConnection struct {
		id string // Unique identifier of the peer
	
		headerIdle  int32 // Current header activity state of the peer (idle = 0, active = 1) 当前的header获取的工作状态。
		blockIdle   int32 // Current block activity state of the peer (idle = 0, active = 1)	当前的区块获取的工作状态
		receiptIdle int32 // Current receipt activity state of the peer (idle = 0, active = 1) 当前的收据获取的工作状态
		stateIdle   int32 // Current node data activity state of the peer (idle = 0, active = 1) 当前节点状态的工作状态
	
		headerThroughput  float64 // Number of headers measured to be retrievable per second	//记录每秒能够接收多少个区块头的度量值
		blockThroughput   float64 // Number of blocks (bodies) measured to be retrievable per second  //记录每秒能够接收多少个区块的度量值
		receiptThroughput float64 // Number of receipts measured to be retrievable per second 记录每秒能够接收多少个收据的度量值
		stateThroughput   float64 // Number of node data pieces measured to be retrievable per second  记录每秒能够接收多少个账户状态的度量值
	
		rtt time.Duration // Request round trip time to track responsiveness (QoS)  请求回应时间
	
		headerStarted  time.Time // Time instance when the last header fetch was started	记录最后一个header fetch的请求时间
		blockStarted   time.Time // Time instance when the last block (body) fetch was started
		receiptStarted time.Time // Time instance when the last receipt fetch was started
		stateStarted   time.Time // Time instance when the last node data fetch was started
		
		lacking map[common.Hash]struct{} // Set of hashes not to request (didn't have previously)  记录的Hash值不会去请求，一般是因为之前的请求失败
	
		peer Peer			// eth的peer
	
		version int        // Eth protocol version number to switch strategies
		log     log.Logger // Contextual logger to add extra infos to peer logs
		lock    sync.RWMutex
	}



FetchXXX
FetchHeaders FetchBodies等函数 主要调用了eth.peer的功能来进行发送数据请求。

	// FetchHeaders sends a header retrieval request to the remote peer.
	func (p *peerConnection) FetchHeaders(from uint64, count int) error {
		// Sanity check the protocol version
		if p.version < 62 {
			panic(fmt.Sprintf("header fetch [eth/62+] requested on eth/%d", p.version))
		}
		// Short circuit if the peer is already fetching
		if !atomic.CompareAndSwapInt32(&p.headerIdle, 0, 1) {
			return errAlreadyFetching
		}
		p.headerStarted = time.Now()
	
		// Issue the header retrieval request (absolut upwards without gaps)
		go p.peer.RequestHeadersByNumber(from, count, 0, false)
	
		return nil
	}

SetXXXIdle函数
SetHeadersIdle, SetBlocksIdle 等函数 设置peer的状态为空闲状态，允许它执行新的请求。 同时还会通过本次传输的数据的多少来重新评估链路的吞吐量。
	
	// SetHeadersIdle sets the peer to idle, allowing it to execute new header retrieval
	// requests. Its estimated header retrieval throughput is updated with that measured
	// just now.
	func (p *peerConnection) SetHeadersIdle(delivered int) {
		p.setIdle(p.headerStarted, delivered, &p.headerThroughput, &p.headerIdle)
	}

setIdle

	// setIdle sets the peer to idle, allowing it to execute new retrieval requests.
	// Its estimated retrieval throughput is updated with that measured just now.
	func (p *peerConnection) setIdle(started time.Time, delivered int, throughput *float64, idle *int32) {
		// Irrelevant of the scaling, make sure the peer ends up idle
		defer atomic.StoreInt32(idle, 0)
	
		p.lock.Lock()
		defer p.lock.Unlock()
	
		// If nothing was delivered (hard timeout / unavailable data), reduce throughput to minimum
		if delivered == 0 {
			*throughput = 0
			return
		}
		// Otherwise update the throughput with a new measurement
		elapsed := time.Since(started) + 1 // +1 (ns) to ensure non-zero divisor
		measured := float64(delivered) / (float64(elapsed) / float64(time.Second))
		
		// measurementImpact = 0.1 , 新的吞吐量=老的吞吐量*0.9 + 这次的吞吐量*0.1
		*throughput = (1-measurementImpact)*(*throughput) + measurementImpact*measured	
		// 更新RTT
		p.rtt = time.Duration((1-measurementImpact)*float64(p.rtt) + measurementImpact*float64(elapsed))
	
		p.log.Trace("Peer throughput measurements updated",
			"hps", p.headerThroughput, "bps", p.blockThroughput,
			"rps", p.receiptThroughput, "sps", p.stateThroughput,
			"miss", len(p.lacking), "rtt", p.rtt)
	}


XXXCapacity函数，用来返回当前的链接允许的吞吐量。

	// HeaderCapacity retrieves the peers header download allowance based on its
	// previously discovered throughput.
	func (p *peerConnection) HeaderCapacity(targetRTT time.Duration) int {
		p.lock.RLock()
		defer p.lock.RUnlock()
		// 这里有点奇怪，targetRTT越大，请求的数量就越多。
		return int(math.Min(1+math.Max(1, p.headerThroughput*float64(targetRTT)/float64(time.Second)), float64(MaxHeaderFetch)))
	}


Lacks 用来标记上次是否失败，以便下次同样的请求不通过这个peer
		
		// MarkLacking appends a new entity to the set of items (blocks, receipts, states)
		// that a peer is known not to have (i.e. have been requested before). If the
		// set reaches its maximum allowed capacity, items are randomly dropped off.
		func (p *peerConnection) MarkLacking(hash common.Hash) {
			p.lock.Lock()
			defer p.lock.Unlock()
		
			for len(p.lacking) >= maxLackingHashes {
				for drop := range p.lacking {
					delete(p.lacking, drop)
					break
				}
			}
			p.lacking[hash] = struct{}{}
		}
		
		// Lacks retrieves whether the hash of a blockchain item is on the peers lacking
		// list (i.e. whether we know that the peer does not have it).
		func (p *peerConnection) Lacks(hash common.Hash) bool {
			p.lock.RLock()
			defer p.lock.RUnlock()
		
			_, ok := p.lacking[hash]
			return ok
		}


## peerSet

	// peerSet represents the collection of active peer participating in the chain
	// download procedure.
	type peerSet struct {
		peers        map[string]*peerConnection
		newPeerFeed  event.Feed
		peerDropFeed event.Feed
		lock         sync.RWMutex
	}


Register 和 UnRegister

	// Register injects a new peer into the working set, or returns an error if the
	// peer is already known.
	//
	// The method also sets the starting throughput values of the new peer to the
	// average of all existing peers, to give it a realistic chance of being used
	// for data retrievals.
	func (ps *peerSet) Register(p *peerConnection) error {
		// Retrieve the current median RTT as a sane default
		p.rtt = ps.medianRTT()
	
		// Register the new peer with some meaningful defaults
		ps.lock.Lock()
		if _, ok := ps.peers[p.id]; ok {
			ps.lock.Unlock()
			return errAlreadyRegistered
		}
		if len(ps.peers) > 0 {
			p.headerThroughput, p.blockThroughput, p.receiptThroughput, p.stateThroughput = 0, 0, 0, 0
	
			for _, peer := range ps.peers {
				peer.lock.RLock()
				p.headerThroughput += peer.headerThroughput
				p.blockThroughput += peer.blockThroughput
				p.receiptThroughput += peer.receiptThroughput
				p.stateThroughput += peer.stateThroughput
				peer.lock.RUnlock()
			}
			p.headerThroughput /= float64(len(ps.peers))
			p.blockThroughput /= float64(len(ps.peers))
			p.receiptThroughput /= float64(len(ps.peers))
			p.stateThroughput /= float64(len(ps.peers))
		}
		ps.peers[p.id] = p
		ps.lock.Unlock()
	
		ps.newPeerFeed.Send(p)
		return nil
	}
	
	// Unregister removes a remote peer from the active set, disabling any further
	// actions to/from that particular entity.
	func (ps *peerSet) Unregister(id string) error {
		ps.lock.Lock()
		p, ok := ps.peers[id]
		if !ok {
			defer ps.lock.Unlock()
			return errNotRegistered
		}
		delete(ps.peers, id)
		ps.lock.Unlock()
	
		ps.peerDropFeed.Send(p)
		return nil
	}

XXXIdlePeers

	// HeaderIdlePeers retrieves a flat list of all the currently header-idle peers
	// within the active peer set, ordered by their reputation.
	func (ps *peerSet) HeaderIdlePeers() ([]*peerConnection, int) {
		idle := func(p *peerConnection) bool {
			return atomic.LoadInt32(&p.headerIdle) == 0
		}
		throughput := func(p *peerConnection) float64 {
			p.lock.RLock()
			defer p.lock.RUnlock()
			return p.headerThroughput
		}
		return ps.idlePeers(62, 64, idle, throughput)
	}

	// idlePeers retrieves a flat list of all currently idle peers satisfying the
	// protocol version constraints, using the provided function to check idleness.
	// The resulting set of peers are sorted by their measure throughput.
	func (ps *peerSet) idlePeers(minProtocol, maxProtocol int, idleCheck func(*peerConnection) bool, throughput func(*peerConnection) float64) ([]*peerConnection, int) {
		ps.lock.RLock()
		defer ps.lock.RUnlock()
	
		idle, total := make([]*peerConnection, 0, len(ps.peers)), 0
		for _, p := range ps.peers { //首先抽取idle的peer
			if p.version >= minProtocol && p.version <= maxProtocol {
				if idleCheck(p) {
					idle = append(idle, p)
				}
				total++
			}
		}
		for i := 0; i < len(idle); i++ { // 冒泡排序， 从吞吐量大到吞吐量小。
			for j := i + 1; j < len(idle); j++ {
				if throughput(idle[i]) < throughput(idle[j]) {
					idle[i], idle[j] = idle[j], idle[i]
				}
			}
		}
		return idle, total
	}

medianRTT,求得peerset的RTT的中位数，
	
	// medianRTT returns the median RTT of te peerset, considering only the tuning
	// peers if there are more peers available.
	func (ps *peerSet) medianRTT() time.Duration {
		// Gather all the currnetly measured round trip times
		ps.lock.RLock()
		defer ps.lock.RUnlock()
	
		rtts := make([]float64, 0, len(ps.peers))
		for _, p := range ps.peers {
			p.lock.RLock()
			rtts = append(rtts, float64(p.rtt))
			p.lock.RUnlock()
		}
		sort.Float64s(rtts)
	
		median := rttMaxEstimate
		if qosTuningPeers <= len(rtts) {
			median = time.Duration(rtts[qosTuningPeers/2]) // Median of our tuning peers
		} else if len(rtts) > 0 {
			median = time.Duration(rtts[len(rtts)/2]) // Median of our connected peers (maintain even like this some baseline qos)
		}
		// Restrict the RTT into some QoS defaults, irrelevant of true RTT
		if median < rttMinEstimate {
			median = rttMinEstimate
		}
		if median > rttMaxEstimate {
			median = rttMaxEstimate
		}
		return median
	}
