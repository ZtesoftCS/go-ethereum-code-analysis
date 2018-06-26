p2p包实现了通用的p2p网络协议。包括节点的查找，节点状态的维护，节点连接的建立等p2p的功能。p2p 包实现的是通用的p2p协议。 某一种具体的协议(比如eth协议。 whisper协议。 swarm协议)被封装成特定的接口注入p2p包。所以p2p内部不包含具体协议的实现。 只完成了p2p网络应该做的事情。


## discover / discv5 节点发现
目前使用的包是discover。 discv5是最近才开发的功能，还是属于实验性质，基本上是discover包的一些优化。 这里我们暂时只分析discover的代码。 对其完成的功能做一个基本的介绍。


### database.go
顾名思义，这个文件内部主要实现了节点的持久化，因为p2p网络节点的节点发现和维护都是比较花时间的，为了反复启动的时候，能够把之前的工作继承下来，避免每次都重新发现。 所以持久化的工作是必须的。

之前我们分析了ethdb的代码和trie的代码，trie的持久化工作使用了leveldb。 这里同样也使用了leveldb。 不过p2p的leveldb实例和主要的区块链的leveldb实例不是同一个。

newNodeDB,根据参数path来看打开基于内存的数据库，还是基于文件的数据库。

	// newNodeDB creates a new node database for storing and retrieving infos about
	// known peers in the network. If no path is given, an in-memory, temporary
	// database is constructed.
	func newNodeDB(path string, version int, self NodeID) (*nodeDB, error) {
		if path == "" {
			return newMemoryNodeDB(self)
		}
		return newPersistentNodeDB(path, version, self)
	}
	// newMemoryNodeDB creates a new in-memory node database without a persistent
	// backend.
	func newMemoryNodeDB(self NodeID) (*nodeDB, error) {
		db, err := leveldb.Open(storage.NewMemStorage(), nil)
		if err != nil {
			return nil, err
		}
		return &nodeDB{
			lvl:  db,
			self: self,
			quit: make(chan struct{}),
		}, nil
	}
	
	// newPersistentNodeDB creates/opens a leveldb backed persistent node database,
	// also flushing its contents in case of a version mismatch.
	func newPersistentNodeDB(path string, version int, self NodeID) (*nodeDB, error) {
		opts := &opt.Options{OpenFilesCacheCapacity: 5}
		db, err := leveldb.OpenFile(path, opts)
		if _, iscorrupted := err.(*errors.ErrCorrupted); iscorrupted {
			db, err = leveldb.RecoverFile(path, nil)
		}
		if err != nil {
			return nil, err
		}
		// The nodes contained in the cache correspond to a certain protocol version.
		// Flush all nodes if the version doesn't match.
		currentVer := make([]byte, binary.MaxVarintLen64)
		currentVer = currentVer[:binary.PutVarint(currentVer, int64(version))]
		blob, err := db.Get(nodeDBVersionKey, nil)
		switch err {
		case leveldb.ErrNotFound:
			// Version not found (i.e. empty cache), insert it
			if err := db.Put(nodeDBVersionKey, currentVer, nil); err != nil {
				db.Close()
				return nil, err
			}
		case nil:
			// Version present, flush if different
			//版本不同，先删除所有的数据库文件，重新创建一个。
			if !bytes.Equal(blob, currentVer) {
				db.Close()
				if err = os.RemoveAll(path); err != nil {
					return nil, err
				}
				return newPersistentNodeDB(path, version, self)
			}
		}
		return &nodeDB{
			lvl:  db,
			self: self,
			quit: make(chan struct{}),
		}, nil
	}


Node的存储，查询和删除	

	// node retrieves a node with a given id from the database.
	func (db *nodeDB) node(id NodeID) *Node {
		blob, err := db.lvl.Get(makeKey(id, nodeDBDiscoverRoot), nil)
		if err != nil {
			return nil
		}
		node := new(Node)
		if err := rlp.DecodeBytes(blob, node); err != nil {
			log.Error("Failed to decode node RLP", "err", err)
			return nil
		}
		node.sha = crypto.Keccak256Hash(node.ID[:])
		return node
	}
	
	// updateNode inserts - potentially overwriting - a node into the peer database.
	func (db *nodeDB) updateNode(node *Node) error {
		blob, err := rlp.EncodeToBytes(node)
		if err != nil {
			return err
		}
		return db.lvl.Put(makeKey(node.ID, nodeDBDiscoverRoot), blob, nil)
	}
	
	// deleteNode deletes all information/keys associated with a node.
	func (db *nodeDB) deleteNode(id NodeID) error {
		deleter := db.lvl.NewIterator(util.BytesPrefix(makeKey(id, "")), nil)
		for deleter.Next() {
			if err := db.lvl.Delete(deleter.Key(), nil); err != nil {
				return err
			}
		}
		return nil
	}

Node的结构

	type Node struct {
		IP       net.IP // len 4 for IPv4 or 16 for IPv6
		UDP, TCP uint16 // port numbers
		ID       NodeID // the node's public key
		// This is a cached copy of sha3(ID) which is used for node
		// distance calculations. This is part of Node in order to make it
		// possible to write tests that need a node at a certain distance.
		// In those tests, the content of sha will not actually correspond
		// with ID.
		sha common.Hash
		// whether this node is currently being pinged in order to replace
		// it in a bucket
		contested bool
	}

节点超时处理


	// ensureExpirer is a small helper method ensuring that the data expiration
	// mechanism is running. If the expiration goroutine is already running, this
	// method simply returns.
	// ensureExpirer方法用来确保expirer方法在运行。 如果expirer已经运行，那么这个方法就直接返回。
	// 这个方法设置的目的是为了在网络成功启动后在开始进行数据超时丢弃的工作(以防一些潜在的有用的种子节点被丢弃)。
	// The goal is to start the data evacuation only after the network successfully
	// bootstrapped itself (to prevent dumping potentially useful seed nodes). Since
	// it would require significant overhead to exactly trace the first successful
	// convergence, it's simpler to "ensure" the correct state when an appropriate
	// condition occurs (i.e. a successful bonding), and discard further events.
	func (db *nodeDB) ensureExpirer() {
		db.runner.Do(func() { go db.expirer() })
	}
	
	// expirer should be started in a go routine, and is responsible for looping ad
	// infinitum and dropping stale data from the database.
	func (db *nodeDB) expirer() {
		tick := time.Tick(nodeDBCleanupCycle)
		for {
			select {
			case <-tick:
				if err := db.expireNodes(); err != nil {
					log.Error("Failed to expire nodedb items", "err", err)
				}
	
			case <-db.quit:
				return
			}
		}
	}
	
	// expireNodes iterates over the database and deletes all nodes that have not
	// been seen (i.e. received a pong from) for some allotted time.
	//这个方法遍历所有的节点，如果某个节点最后接收消息超过指定值，那么就删除这个节点。
	func (db *nodeDB) expireNodes() error {
		threshold := time.Now().Add(-nodeDBNodeExpiration)
	
		// Find discovered nodes that are older than the allowance
		it := db.lvl.NewIterator(nil, nil)
		defer it.Release()
	
		for it.Next() {
			// Skip the item if not a discovery node
			id, field := splitKey(it.Key())
			if field != nodeDBDiscoverRoot {
				continue
			}
			// Skip the node if not expired yet (and not self)
			if !bytes.Equal(id[:], db.self[:]) {
				if seen := db.lastPong(id); seen.After(threshold) {
					continue
				}
			}
			// Otherwise delete all associated information
			db.deleteNode(id)
		}
		return nil
	}


一些状态更新函数

	// lastPing retrieves the time of the last ping packet send to a remote node,
	// requesting binding.
	func (db *nodeDB) lastPing(id NodeID) time.Time {
		return time.Unix(db.fetchInt64(makeKey(id, nodeDBDiscoverPing)), 0)
	}
	
	// updateLastPing updates the last time we tried contacting a remote node.
	func (db *nodeDB) updateLastPing(id NodeID, instance time.Time) error {
		return db.storeInt64(makeKey(id, nodeDBDiscoverPing), instance.Unix())
	}
	
	// lastPong retrieves the time of the last successful contact from remote node.
	func (db *nodeDB) lastPong(id NodeID) time.Time {
		return time.Unix(db.fetchInt64(makeKey(id, nodeDBDiscoverPong)), 0)
	}
	
	// updateLastPong updates the last time a remote node successfully contacted.
	func (db *nodeDB) updateLastPong(id NodeID, instance time.Time) error {
		return db.storeInt64(makeKey(id, nodeDBDiscoverPong), instance.Unix())
	}
	
	// findFails retrieves the number of findnode failures since bonding.
	func (db *nodeDB) findFails(id NodeID) int {
		return int(db.fetchInt64(makeKey(id, nodeDBDiscoverFindFails)))
	}
	
	// updateFindFails updates the number of findnode failures since bonding.
	func (db *nodeDB) updateFindFails(id NodeID, fails int) error {
		return db.storeInt64(makeKey(id, nodeDBDiscoverFindFails), int64(fails))
	}


从数据库里面随机挑选合适种子节点


	// querySeeds retrieves random nodes to be used as potential seed nodes
	// for bootstrapping.
	func (db *nodeDB) querySeeds(n int, maxAge time.Duration) []*Node {
		var (
			now   = time.Now()
			nodes = make([]*Node, 0, n)
			it    = db.lvl.NewIterator(nil, nil)
			id    NodeID
		)
		defer it.Release()
	
	seek:
		for seeks := 0; len(nodes) < n && seeks < n*5; seeks++ {
			// Seek to a random entry. The first byte is incremented by a
			// random amount each time in order to increase the likelihood
			// of hitting all existing nodes in very small databases.
			ctr := id[0]
			rand.Read(id[:])
			id[0] = ctr + id[0]%16
			it.Seek(makeKey(id, nodeDBDiscoverRoot))
	
			n := nextNode(it)
			if n == nil {
				id[0] = 0
				continue seek // iterator exhausted
			}
			if n.ID == db.self {
				continue seek
			}
			if now.Sub(db.lastPong(n.ID)) > maxAge {
				continue seek
			}
			for i := range nodes {
				if nodes[i].ID == n.ID {
					continue seek // duplicate
				}
			}
			nodes = append(nodes, n)
		}
		return nodes
	}
	
	// reads the next node record from the iterator, skipping over other
	// database entries.
	func nextNode(it iterator.Iterator) *Node {
		for end := false; !end; end = !it.Next() {
			id, field := splitKey(it.Key())
			if field != nodeDBDiscoverRoot {
				continue
			}
			var n Node
			if err := rlp.DecodeBytes(it.Value(), &n); err != nil {
				log.Warn("Failed to decode node RLP", "id", id, "err", err)
				continue
			}
			return &n
		}
		return nil
	}



