table.go主要实现了p2p的Kademlia协议。

### Kademlia协议简介(建议阅读references里面的pdf文档)
Kademlia协议（以下简称Kad） 是美国纽约大学的PetarP. Maymounkov和David Mazieres.
在2002年发布的一项研究结果《Kademlia: A peerto -peer information system based on
the XOR metric》。
简单的说， Kad 是一种分布式哈希表（ DHT） 技术， 不过和其他 DHT 实现技术比较，如
Chord、 CAN、 Pastry 等， Kad 通过独特的以异或算法（ XOR）为距离度量基础，建立了一种
全新的 DHT 拓扑结构，相比于其他算法，大大提高了路由查询速度。


### table的结构和字段

	const (
		alpha      = 3  // Kademlia concurrency factor
		bucketSize = 16 // Kademlia bucket size
		hashBits   = len(common.Hash{}) * 8
		nBuckets   = hashBits + 1 // Number of buckets
	
		maxBondingPingPongs = 16
		maxFindnodeFailures = 5
	
		autoRefreshInterval = 1 * time.Hour
		seedCount           = 30
		seedMaxAge          = 5 * 24 * time.Hour
	)
	
	type Table struct {
		mutex   sync.Mutex        // protects buckets, their content, and nursery
		buckets [nBuckets]*bucket // index of known nodes by distance
		nursery []*Node           // bootstrap nodes
		db      *nodeDB           // database of known nodes
	
		refreshReq chan chan struct{}
		closeReq   chan struct{}
		closed     chan struct{}
	
		bondmu    sync.Mutex
		bonding   map[NodeID]*bondproc
		bondslots chan struct{} // limits total number of active bonding processes
	
		nodeAddedHook func(*Node) // for testing
	
		net  transport
		self *Node // metadata of the local node
	}


### 初始化


	func newTable(t transport, ourID NodeID, ourAddr *net.UDPAddr, nodeDBPath string) (*Table, error) {
		// If no node database was given, use an in-memory one
		//这个在之前的database.go里面有介绍。 打开leveldb。如果path为空。那么打开一个基于内存的db
		db, err := newNodeDB(nodeDBPath, Version, ourID)
		if err != nil {
			return nil, err
		}
		tab := &Table{
			net:        t,
			db:         db,
			self:       NewNode(ourID, ourAddr.IP, uint16(ourAddr.Port), uint16(ourAddr.Port)),
			bonding:    make(map[NodeID]*bondproc),
			bondslots:  make(chan struct{}, maxBondingPingPongs),
			refreshReq: make(chan chan struct{}),
			closeReq:   make(chan struct{}),
			closed:     make(chan struct{}),
		}
		for i := 0; i < cap(tab.bondslots); i++ {
			tab.bondslots <- struct{}{}
		}
		for i := range tab.buckets {
			tab.buckets[i] = new(bucket)
		}
		go tab.refreshLoop()
		return tab, nil
	}

上面的初始化启动了一个goroutine refreshLoop()，这个函数主要完成以下的工作。

1. 每一个小时进行一次刷新工作(autoRefreshInterval)
2. 如果接收到refreshReq请求。那么进行刷新工作。
3. 如果接收到关闭消息。那么进行关闭。

所以函数主要的工作就是启动刷新工作。doRefresh


	// refreshLoop schedules doRefresh runs and coordinates shutdown.
	func (tab *Table) refreshLoop() {
		var (
			timer   = time.NewTicker(autoRefreshInterval)
			waiting []chan struct{} // accumulates waiting callers while doRefresh runs
			done    chan struct{}   // where doRefresh reports completion
		)
	loop:
		for {
			select {
			case <-timer.C:
				if done == nil {
					done = make(chan struct{})
					go tab.doRefresh(done)
				}
			case req := <-tab.refreshReq:
				waiting = append(waiting, req)
				if done == nil {
					done = make(chan struct{})
					go tab.doRefresh(done)
				}
			case <-done:
				for _, ch := range waiting {
					close(ch)
				}
				waiting = nil
				done = nil
			case <-tab.closeReq:
				break loop
			}
		}
	
		if tab.net != nil {
			tab.net.close()
		}
		if done != nil {
			<-done
		}
		for _, ch := range waiting {
			close(ch)
		}
		tab.db.close()
		close(tab.closed)
	}


doRefresh函数

	// doRefresh performs a lookup for a random target to keep buckets
	// full. seed nodes are inserted if the table is empty (initial
	// bootstrap or discarded faulty peers).
	// doRefresh 随机查找一个目标，以便保持buckets是满的。如果table是空的，那么种子节点会插入。 （比如最开始的启动或者是删除错误的节点之后）
	func (tab *Table) doRefresh(done chan struct{}) {
		defer close(done)
	
		// The Kademlia paper specifies that the bucket refresh should
		// perform a lookup in the least recently used bucket. We cannot
		// adhere to this because the findnode target is a 512bit value
		// (not hash-sized) and it is not easily possible to generate a
		// sha3 preimage that falls into a chosen bucket.
		// We perform a lookup with a random target instead.
		//这里暂时没看懂
		var target NodeID
		rand.Read(target[:])
		result := tab.lookup(target, false) //lookup是查找距离target最近的k个节点
		if len(result) > 0 {  //如果结果不为0 说明表不是空的，那么直接返回。
			return
		}
	
		// The table is empty. Load nodes from the database and insert
		// them. This should yield a few previously seen nodes that are
		// (hopefully) still alive.
		//querySeeds函数在database.go章节有介绍，从数据库里面随机的查找可用的种子节点。
		//在最开始启动的时候数据库是空白的。也就是最开始的时候这个seeds返回的是空的。
		seeds := tab.db.querySeeds(seedCount, seedMaxAge)
		//调用bondall函数。会尝试联系这些节点，并插入到表中。
		//tab.nursery是在命令行中指定的种子节点。
		//最开始启动的时候。 tab.nursery的值是内置在代码里面的。 这里是有值的。
		//C:\GOPATH\src\github.com\ethereum\go-ethereum\mobile\params.go
		//这里面写死了值。 这个值是通过SetFallbackNodes方法写入的。 这个方法后续会分析。
		//这里会进行双向的pingpong交流。 然后把结果存储在数据库。
		seeds = tab.bondall(append(seeds, tab.nursery...))
	
		if len(seeds) == 0 { //没有种子节点被发现， 可能需要等待下一次刷新。
			log.Debug("No discv4 seed nodes found")
		}
		for _, n := range seeds {
			age := log.Lazy{Fn: func() time.Duration { return time.Since(tab.db.lastPong(n.ID)) }}
			log.Trace("Found seed node in database", "id", n.ID, "addr", n.addr(), "age", age)
		}
		tab.mutex.Lock()
		//这个方法把所有经过bond的seed加入到bucket(前提是bucket未满)
		tab.stuff(seeds) 
		tab.mutex.Unlock()
	
		// Finally, do a self lookup to fill up the buckets.
		tab.lookup(tab.self.ID, false) // 有了种子节点。那么查找自己来填充buckets。
	}

bondall方法，这个方法就是多线程的调用bond方法。 

	// bondall bonds with all given nodes concurrently and returns
	// those nodes for which bonding has probably succeeded.
	func (tab *Table) bondall(nodes []*Node) (result []*Node) {
		rc := make(chan *Node, len(nodes))
		for i := range nodes {
			go func(n *Node) {
				nn, _ := tab.bond(false, n.ID, n.addr(), uint16(n.TCP))
				rc <- nn
			}(nodes[i])
		}
		for range nodes {
			if n := <-rc; n != nil {
				result = append(result, n)
			}
		}
		return result
	}

bond方法。记得在udp.go中。当我们收到一个ping方法的时候，也有可能会调用这个方法


	// bond ensures the local node has a bond with the given remote node.
	// It also attempts to insert the node into the table if bonding succeeds.
	// The caller must not hold tab.mutex.
	// bond确保本地节点与给定的远程节点具有绑定。(远端的ID和远端的IP)。
	// 如果绑定成功，它也会尝试将节点插入表中。调用者必须持有tab.mutex锁
	// A bond is must be established before sending findnode requests.
	// Both sides must have completed a ping/pong exchange for a bond to
	// exist. The total number of active bonding processes is limited in
	// order to restrain network use.
	// 发送findnode请求之前必须建立一个绑定。	双方为了完成一个bond必须完成双向的ping/pong过程。
	// 为了节约网路资源。 同时存在的bonding处理流程的总数量是受限的。	
	// bond is meant to operate idempotently in that bonding with a remote
	// node which still remembers a previously established bond will work.
	// The remote node will simply not send a ping back, causing waitping
	// to time out.
	// bond 是幂等的操作，跟一个任然记得之前的bond的远程节点进行bond也可以完成。 远程节点会简单的不会发送ping。 等待waitping超时。
	// If pinged is true, the remote node has just pinged us and one half
	// of the process can be skipped.
	//	如果pinged是true。 那么远端节点已经给我们发送了ping消息。这样一半的流程可以跳过。
	func (tab *Table) bond(pinged bool, id NodeID, addr *net.UDPAddr, tcpPort uint16) (*Node, error) {
		if id == tab.self.ID {
			return nil, errors.New("is self")
		}
		// Retrieve a previously known node and any recent findnode failures
		node, fails := tab.db.node(id), 0
		if node != nil {
			fails = tab.db.findFails(id)
		}
		// If the node is unknown (non-bonded) or failed (remotely unknown), bond from scratch
		var result error
		age := time.Since(tab.db.lastPong(id))
		if node == nil || fails > 0 || age > nodeDBNodeExpiration {
			//如果数据库没有这个节点。 或者错误数量大于0或者节点超时。
			log.Trace("Starting bonding ping/pong", "id", id, "known", node != nil, "failcount", fails, "age", age)
	
			tab.bondmu.Lock()
			w := tab.bonding[id]
			if w != nil {
				// Wait for an existing bonding process to complete.
				tab.bondmu.Unlock()
				<-w.done
			} else {
				// Register a new bonding process.
				w = &bondproc{done: make(chan struct{})}
				tab.bonding[id] = w
				tab.bondmu.Unlock()
				// Do the ping/pong. The result goes into w.
				tab.pingpong(w, pinged, id, addr, tcpPort)
				// Unregister the process after it's done.
				tab.bondmu.Lock()
				delete(tab.bonding, id)
				tab.bondmu.Unlock()
			}
			// Retrieve the bonding results
			result = w.err
			if result == nil {
				node = w.n
			}
		}
		if node != nil {
			// Add the node to the table even if the bonding ping/pong
			// fails. It will be relaced quickly if it continues to be
			// unresponsive.
			//这个方法比较重要。 如果对应的bucket有空间，会直接插入buckets。如果buckets满了。 会用ping操作来测试buckets中的节点试图腾出空间。
			tab.add(node)
			tab.db.updateFindFails(id, 0)
		}
		return node, result
	}

pingpong方法

	func (tab *Table) pingpong(w *bondproc, pinged bool, id NodeID, addr *net.UDPAddr, tcpPort uint16) {
		// Request a bonding slot to limit network usage
		<-tab.bondslots
		defer func() { tab.bondslots <- struct{}{} }()
	
		// Ping the remote side and wait for a pong.
		// Ping远程节点。并等待一个pong消息
		if w.err = tab.ping(id, addr); w.err != nil {
			close(w.done)
			return
		}
		//这个在udp收到一个ping消息的时候被设置为真。这个时候我们已经收到对方的ping消息了。
		//那么我们就不同等待ping消息了。 否则需要等待对方发送过来的ping消息(我们主动发起ping消息)。
		if !pinged {
			// Give the remote node a chance to ping us before we start
			// sending findnode requests. If they still remember us,
			// waitping will simply time out.
			tab.net.waitping(id)
		}
		// Bonding succeeded, update the node database.
		// 完成bond过程。 把节点插入数据库。 数据库操作在这里完成。 bucket的操作在tab.add里面完成。 buckets是内存的操作。 数据库是持久化的seeds节点。用来加速启动过程的。
		w.n = NewNode(id, addr.IP, uint16(addr.Port), tcpPort)
		tab.db.updateNode(w.n)
		close(w.done)
	}

tab.add方法

	// add attempts to add the given node its corresponding bucket. If the
	// bucket has space available, adding the node succeeds immediately.
	// Otherwise, the node is added if the least recently active node in
	// the bucket does not respond to a ping packet.
	// add试图把给定的节点插入对应的bucket。 如果bucket有空间，那么直接插入。 否则，如果bucket中最近活动的节点没有响应ping操作，那么我们就使用这个节点替换它。
	// The caller must not hold tab.mutex.
	func (tab *Table) add(new *Node) {
		b := tab.buckets[logdist(tab.self.sha, new.sha)]
		tab.mutex.Lock()
		defer tab.mutex.Unlock()
		if b.bump(new) { //如果节点存在。那么更新它的值。然后退出。
			return
		}
		var oldest *Node
		if len(b.entries) == bucketSize {
			oldest = b.entries[bucketSize-1]
			if oldest.contested {
				// The node is already being replaced, don't attempt
				// to replace it.
				// 如果别的goroutine正在对这个节点进行测试。 那么取消替换， 直接退出。
				// 因为ping的时间比较长。所以这段时间是没有加锁的。 用了contested这个状态来标识这种情况。 
				return
			}
			oldest.contested = true
			// Let go of the mutex so other goroutines can access
			// the table while we ping the least recently active node.
			tab.mutex.Unlock()
			err := tab.ping(oldest.ID, oldest.addr())
			tab.mutex.Lock()
			oldest.contested = false
			if err == nil {
				// The node responded, don't replace it.
				return
			}
		}
		added := b.replace(new, oldest)
		if added && tab.nodeAddedHook != nil {
			tab.nodeAddedHook(new)
		}
	}



stuff方法比较简单。  找到对应节点应该插入的bucket。 如果这个bucket没有满，那么就插入这个bucket。否则什么也不做。 需要说一下的是logdist()这个方法。这个方法对两个值进行按照位置异或，然后返回最高位的下标。  比如   logdist(101,010) = 3   logdist(100, 100) = 0 logdist(100,110) = 2

	// stuff adds nodes the table to the end of their corresponding bucket
	// if the bucket is not full. The caller must hold tab.mutex.
	func (tab *Table) stuff(nodes []*Node) {
	outer:
		for _, n := range nodes {
			if n.ID == tab.self.ID {
				continue // don't add self
			}
			bucket := tab.buckets[logdist(tab.self.sha, n.sha)]
			for i := range bucket.entries {
				if bucket.entries[i].ID == n.ID {
					continue outer // already in bucket
				}
			}
			if len(bucket.entries) < bucketSize {
				bucket.entries = append(bucket.entries, n)
				if tab.nodeAddedHook != nil {
					tab.nodeAddedHook(n)
				}
			}
		}
	}


在看看之前的Lookup函数。 这个函数用来查询一个指定节点的信息。  这个函数首先从本地拿到距离这个节点最近的所有16个节点。 然后给所有的节点发送findnode的请求。 然后对返回的界定进行bondall处理。 然后返回所有的节点。



	func (tab *Table) lookup(targetID NodeID, refreshIfEmpty bool) []*Node {
		var (
			target         = crypto.Keccak256Hash(targetID[:])
			asked          = make(map[NodeID]bool)
			seen           = make(map[NodeID]bool)
			reply          = make(chan []*Node, alpha)
			pendingQueries = 0
			result         *nodesByDistance
		)
		// don't query further if we hit ourself.
		// unlikely to happen often in practice.
		asked[tab.self.ID] = true
		不会询问我们自己
		for {
			tab.mutex.Lock()
			// generate initial result set
			result = tab.closest(target, bucketSize)
			//求取和target最近的16个节点
			tab.mutex.Unlock()
			if len(result.entries) > 0 || !refreshIfEmpty {
				break
			}
			// The result set is empty, all nodes were dropped, refresh.
			// We actually wait for the refresh to complete here. The very
			// first query will hit this case and run the bootstrapping
			// logic.
			<-tab.refresh()
			refreshIfEmpty = false
		}
	
		for {
			// ask the alpha closest nodes that we haven't asked yet
			// 这里会并发的查询，每次3个goroutine并发(通过pendingQueries参数进行控制)
			// 每次迭代会查询result中和target距离最近的三个节点。
			for i := 0; i < len(result.entries) && pendingQueries < alpha; i++ {
				n := result.entries[i]
				if !asked[n.ID] { //如果没有查询过 //因为这个result.entries会被重复循环很多次。 所以用这个变量控制那些已经处理过了。
					asked[n.ID] = true
					pendingQueries++
					go func() {
						// Find potential neighbors to bond with
						r, err := tab.net.findnode(n.ID, n.addr(), targetID)
						if err != nil {
							// Bump the failure counter to detect and evacuate non-bonded entries
							fails := tab.db.findFails(n.ID) + 1
							tab.db.updateFindFails(n.ID, fails)
							log.Trace("Bumping findnode failure counter", "id", n.ID, "failcount", fails)
	
							if fails >= maxFindnodeFailures {
								log.Trace("Too many findnode failures, dropping", "id", n.ID, "failcount", fails)
								tab.delete(n)
							}
						}
						reply <- tab.bondall(r)
					}()
				}
			}
			if pendingQueries == 0 {
				// we have asked all closest nodes, stop the search
				break
			}
			// wait for the next reply
			for _, n := range <-reply {
				if n != nil && !seen[n.ID] { //因为不同的远方节点可能返回相同的节点。所有用seen[]来做排重。
					seen[n.ID] = true
					//这个地方需要注意的是, 查找出来的结果又会加入result这个队列。也就是说这是一个循环查找的过程， 只要result里面不断加入新的节点。这个循环就不会终止。
					result.push(n, bucketSize)
				}
			}
			pendingQueries--
		}
		return result.entries
	}
	
	// closest returns the n nodes in the table that are closest to the
	// given id. The caller must hold tab.mutex.
	func (tab *Table) closest(target common.Hash, nresults int) *nodesByDistance {
		// This is a very wasteful way to find the closest nodes but
		// obviously correct. I believe that tree-based buckets would make
		// this easier to implement efficiently.
		close := &nodesByDistance{target: target}
		for _, b := range tab.buckets {
			for _, n := range b.entries {
				close.push(n, nresults)
			}
		}
		return close
	}

result.push方法，这个方法会根据 所有的节点对于target的距离进行排序。 按照从近到远的方式决定新节点的插入顺序。(队列中最大会包含16个元素)。 这样会导致队列里面的元素和target的距离越来越近。距离相对远的会被踢出队列。
	
	// nodesByDistance is a list of nodes, ordered by
	// distance to target.
	type nodesByDistance struct {
		entries []*Node
		target  common.Hash
	}
	
	// push adds the given node to the list, keeping the total size below maxElems.
	func (h *nodesByDistance) push(n *Node, maxElems int) {
		ix := sort.Search(len(h.entries), func(i int) bool {
			return distcmp(h.target, h.entries[i].sha, n.sha) > 0
		})
		if len(h.entries) < maxElems {
			h.entries = append(h.entries, n)
		}
		if ix == len(h.entries) {
			// farther away than all nodes we already have.
			// if there was room for it, the node is now the last element.
		} else {
			// slide existing entries down to make room
			// this will overwrite the entry we just appended.
			copy(h.entries[ix+1:], h.entries[ix:])
			h.entries[ix] = n
		}
	}


### table.go 导出的一些方法
Resolve方法和Lookup方法

	// Resolve searches for a specific node with the given ID.
	// It returns nil if the node could not be found.
	//Resolve方法用来获取一个指定ID的节点。 如果节点在本地。那么返回本地节点。 否则执行
	//Lookup在网络上查询一次。 如果查询到节点。那么返回。否则返回nil
	func (tab *Table) Resolve(targetID NodeID) *Node {
		// If the node is present in the local table, no
		// network interaction is required.
		hash := crypto.Keccak256Hash(targetID[:])
		tab.mutex.Lock()
		cl := tab.closest(hash, 1)
		tab.mutex.Unlock()
		if len(cl.entries) > 0 && cl.entries[0].ID == targetID {
			return cl.entries[0]
		}
		// Otherwise, do a network lookup.
		result := tab.Lookup(targetID)
		for _, n := range result {
			if n.ID == targetID {
				return n
			}
		}
		return nil
	}
	
	// Lookup performs a network search for nodes close
	// to the given target. It approaches the target by querying
	// nodes that are closer to it on each iteration.
	// The given target does not need to be an actual node
	// identifier.
	func (tab *Table) Lookup(targetID NodeID) []*Node {
		return tab.lookup(targetID, true)
	}

SetFallbackNodes方法，这个方法设置初始化的联系节点。 在table是空而且数据库里面也没有已知的节点，这些节点可以帮助连接上网络，

	// SetFallbackNodes sets the initial points of contact. These nodes
	// are used to connect to the network if the table is empty and there
	// are no known nodes in the database.
	func (tab *Table) SetFallbackNodes(nodes []*Node) error {
		for _, n := range nodes {
			if err := n.validateComplete(); err != nil {
				return fmt.Errorf("bad bootstrap/fallback node %q (%v)", n, err)
			}
		}
		tab.mutex.Lock()
		tab.nursery = make([]*Node, 0, len(nodes))
		for _, n := range nodes {
			cpy := *n
			// Recompute cpy.sha because the node might not have been
			// created by NewNode or ParseNode.
			cpy.sha = crypto.Keccak256Hash(n.ID[:])
			tab.nursery = append(tab.nursery, &cpy)
		}
		tab.mutex.Unlock()
		tab.refresh()
		return nil
	}


### 总结

这样， p2p网络的Kademlia协议就完结了。 基本上是按照论文进行实现。 udp进行网络通信。数据库存储链接过的节点。 table实现了Kademlia的核心。 根据异或距离来进行节点的查找。 节点的发现和更新等流程。