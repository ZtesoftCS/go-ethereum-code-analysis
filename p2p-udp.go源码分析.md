p2p的网络发现协议使用了Kademlia protocol 来处理网络的节点发现。节点查找和节点更新。Kademlia protocol使用了UDP协议来进行网络通信。

阅读这部分的代码建议先看看references里面的Kademlia协议简介来看看什么是Kademlia协议。

首先看看数据结构。 网络传输了4种数据包(UDP协议是基于报文的协议。传输的是一个一个数据包)，分别是ping,pong,findnode和neighbors。 下面分别定义了4种报文的格式。 


	// RPC packet types
	const (
		pingPacket = iota + 1 // zero is 'reserved'
		pongPacket
		findnodePacket
		neighborsPacket
	)
	// RPC request structures
	type (
		ping struct {
			Version    uint             //协议版本
			From, To   rpcEndpoint		//源IP地址 目的IP地址
			Expiration uint64			//超时时间
			// Ignore additional fields (for forward compatibility).
			//可以忽略的字段。 为了向前兼容
			Rest []rlp.RawValue `rlp:"tail"`
		}
	
		// pong is the reply to ping.
		// ping包的回应
		pong struct {
			// This field should mirror the UDP envelope address
			// of the ping packet, which provides a way to discover the
			// the external address (after NAT).
			// 目的IP地址
			To rpcEndpoint
			// 说明这个pong包是回应那个ping包的。 包含了ping包的hash值
			ReplyTok   []byte // This contains the hash of the ping packet.
			//包超时的绝对时间。 如果收到包的时候超过了这个时间，那么包被认为是超时的。
			Expiration uint64 // Absolute timestamp at which the packet becomes invalid.
			// Ignore additional fields (for forward compatibility).
			Rest []rlp.RawValue `rlp:"tail"`
		}
		// findnode 是用来查询距离target比较近的节点
		// findnode is a query for nodes close to the given target.
		findnode struct {
			// 目的节点
			Target     NodeID // doesn't need to be an actual public key
			Expiration uint64
			// Ignore additional fields (for forward compatibility).
			Rest []rlp.RawValue `rlp:"tail"`
		}
	
		// reply to findnode
		// findnode的回应
		neighbors struct {
			//距离target比较近的节点值。
			Nodes      []rpcNode
			Expiration uint64
			// Ignore additional fields (for forward compatibility).
			Rest []rlp.RawValue `rlp:"tail"`
		}
	
		rpcNode struct {
			IP  net.IP // len 4 for IPv4 or 16 for IPv6
			UDP uint16 // for discovery protocol
			TCP uint16 // for RLPx protocol
			ID  NodeID
		}
	
		rpcEndpoint struct {
			IP  net.IP // len 4 for IPv4 or 16 for IPv6
			UDP uint16 // for discovery protocol
			TCP uint16 // for RLPx protocol
		}
	)


定义了两个接口类型，packet接口类型应该是给4种不同类型的包分派不同的handle方法。 conn接口定义了一个udp的连接的功能。


	type packet interface {
		handle(t *udp, from *net.UDPAddr, fromID NodeID, mac []byte) error
		name() string
	}
	
	type conn interface {
		ReadFromUDP(b []byte) (n int, addr *net.UDPAddr, err error)
		WriteToUDP(b []byte, addr *net.UDPAddr) (n int, err error)
		Close() error
		LocalAddr() net.Addr
	}


udp的结构， 需要注意的是最后一个字段*Table是go里面的匿名字段。  也就是说udp可以直接调用匿名字段Table的方法。


	// udp implements the RPC protocol.
	type udp struct {
		conn        conn					//网络连接
		netrestrict *netutil.Netlist
		priv        *ecdsa.PrivateKey		//私钥，自己的ID是通过这个来生成的。
		ourEndpoint rpcEndpoint
	
		addpending chan *pending			//用来申请一个pending
		gotreply   chan reply				//用来获取回应的队列
	
		closing chan struct{}				//用来关闭的队列
		nat     nat.Interface				
	
		*Table
	}



pending 和reply 结构。 这两个结构用户内部的go routine之间进行通信的结构体。


	// pending represents a pending reply.
	// some implementations of the protocol wish to send more than one
	// reply packet to findnode. in general, any neighbors packet cannot
	// be matched up with a specific findnode packet.
	// our implementation handles this by storing a callback function for
	// each pending reply. incoming packets from a node are dispatched
	// to all the callback functions for that node.
	// pending结构 代表正在等待一个reply
	// 我们通过为每一个pending reply 存储一个callback来实现这个功能。从一个节点来的所有数据包都会分配到这个节点对应的callback上面。
	type pending struct {
		// these fields must match in the reply.
		from  NodeID
		ptype byte
	
		// time when the request must complete
		deadline time.Time
	
		// callback is called when a matching reply arrives. if it returns
		// true, the callback is removed from the pending reply queue.
		// if it returns false, the reply is considered incomplete and
		// the callback will be invoked again for the next matching reply.
		//如果返回值是true。那么callback会从队列里面移除。 如果返回false,那么认为reply还没有完成，会继续等待下一次reply.
		callback func(resp interface{}) (done bool)
	
		// errc receives nil when the callback indicates completion or an
		// error if no further reply is received within the timeout.
		errc chan<- error
	}
	
	type reply struct {
		from  NodeID
		ptype byte
		data  interface{}
		// loop indicates whether there was
		// a matching request by sending on this channel.
		//通过往这个channel上面发送消息来表示匹配到一个请求。
		matched chan<- bool
	}


UDP的创建

	// ListenUDP returns a new table that listens for UDP packets on laddr.
	func ListenUDP(priv *ecdsa.PrivateKey, laddr string, natm nat.Interface, nodeDBPath string, netrestrict *netutil.Netlist) (*Table, error) {
		addr, err := net.ResolveUDPAddr("udp", laddr)
		if err != nil {
			return nil, err
		}
		conn, err := net.ListenUDP("udp", addr)
		if err != nil {
			return nil, err
		}
		tab, _, err := newUDP(priv, conn, natm, nodeDBPath, netrestrict)
		if err != nil {
			return nil, err
		}
		log.Info("UDP listener up", "self", tab.self)
		return tab, nil
	}
	
	func newUDP(priv *ecdsa.PrivateKey, c conn, natm nat.Interface, nodeDBPath string, netrestrict *netutil.Netlist) (*Table, *udp, error) {
		udp := &udp{
			conn:        c,
			priv:        priv,
			netrestrict: netrestrict,
			closing:     make(chan struct{}),
			gotreply:    make(chan reply),
			addpending:  make(chan *pending),
		}
		realaddr := c.LocalAddr().(*net.UDPAddr)
		if natm != nil {   //natm nat mapping 用来获取外网地址
			if !realaddr.IP.IsLoopback() {  //如果地址是本地环回地址
				go nat.Map(natm, udp.closing, "udp", realaddr.Port, realaddr.Port, "ethereum discovery")
			}
			// TODO: react to external IP changes over time.
			if ext, err := natm.ExternalIP(); err == nil {
				realaddr = &net.UDPAddr{IP: ext, Port: realaddr.Port}
			}
		}
		// TODO: separate TCP port
		udp.ourEndpoint = makeEndpoint(realaddr, uint16(realaddr.Port))
		//创建一个table 后续会介绍。 Kademlia的主要逻辑在这个类里面实现。
		tab, err := newTable(udp, PubkeyID(&priv.PublicKey), realaddr, nodeDBPath)
		if err != nil {
			return nil, nil, err
		}
		udp.Table = tab   //匿名字段的赋值
		
		go udp.loop()		//go routine 
		go udp.readLoop()	//用来网络数据读取。
		return udp.Table, udp, nil
	}

ping方法与pending的处理，之前谈到了pending是等待一个reply。 这里通过代码来分析是如何实现等待reply的。

pending方法把pending结构体发送给addpending. 然后等待消息的处理和接收。

	// ping sends a ping message to the given node and waits for a reply.
	func (t *udp) ping(toid NodeID, toaddr *net.UDPAddr) error {
		// TODO: maybe check for ReplyTo field in callback to measure RTT
		errc := t.pending(toid, pongPacket, func(interface{}) bool { return true })
		t.send(toaddr, pingPacket, &ping{
			Version:    Version,
			From:       t.ourEndpoint,
			To:         makeEndpoint(toaddr, 0), // TODO: maybe use known TCP port from DB
			Expiration: uint64(time.Now().Add(expiration).Unix()),
		})
		return <-errc
	}
	// pending adds a reply callback to the pending reply queue.
	// see the documentation of type pending for a detailed explanation.
	func (t *udp) pending(id NodeID, ptype byte, callback func(interface{}) bool) <-chan error {
		ch := make(chan error, 1)
		p := &pending{from: id, ptype: ptype, callback: callback, errc: ch}
		select {
		case t.addpending <- p:
			// loop will handle it
		case <-t.closing:
			ch <- errClosed
		}
		return ch
	}

addpending消息的处理。 之前创建udp的时候调用了newUDP方法。里面启动了两个goroutine。 其中的loop()就是用来处理pending消息的。


	// loop runs in its own goroutine. it keeps track of
	// the refresh timer and the pending reply queue.
	func (t *udp) loop() {
		var (
			plist        = list.New()
			timeout      = time.NewTimer(0)
			nextTimeout  *pending // head of plist when timeout was last reset
			contTimeouts = 0      // number of continuous timeouts to do NTP checks
			ntpWarnTime  = time.Unix(0, 0)
		)
		<-timeout.C // ignore first timeout
		defer timeout.Stop()
	
		resetTimeout := func() {  
			//这个方法的主要功能是查看队列里面是否有需要超时的pending消息。 如果有。那么
			//根据最先超时的时间设置超时醒来。 
			if plist.Front() == nil || nextTimeout == plist.Front().Value {
				return
			}
			// Start the timer so it fires when the next pending reply has expired.
			now := time.Now()
			for el := plist.Front(); el != nil; el = el.Next() {
				nextTimeout = el.Value.(*pending)
				if dist := nextTimeout.deadline.Sub(now); dist < 2*respTimeout {
					timeout.Reset(dist)
					return
				}
				// Remove pending replies whose deadline is too far in the
				// future. These can occur if the system clock jumped
				// backwards after the deadline was assigned.
				//如果有消息的deadline在很远的未来，那么直接设置超时，然后移除。
				//这种情况在修改系统时间的时候有可能发生，如果不处理可能导致堵塞太长时间。
				nextTimeout.errc <- errClockWarp
				plist.Remove(el)
			}
			nextTimeout = nil
			timeout.Stop()
		}
	
		for {
			resetTimeout()  //首先处理超时。
	
			select {
			case <-t.closing:  //收到关闭信息。 超时所有的堵塞的队列
				for el := plist.Front(); el != nil; el = el.Next() {
					el.Value.(*pending).errc <- errClosed
				}
				return
	
			case p := <-t.addpending:  //增加一个pending 设置deadline
				p.deadline = time.Now().Add(respTimeout)
				plist.PushBack(p)
	
			case r := <-t.gotreply:  //收到一个reply 寻找匹配的pending
				var matched bool
				for el := plist.Front(); el != nil; el = el.Next() {
					p := el.Value.(*pending)
					if p.from == r.from && p.ptype == r.ptype { //如果来自同一个人。 而且类型相同
						matched = true
						// Remove the matcher if its callback indicates
						// that all replies have been received. This is
						// required for packet types that expect multiple
						// reply packets.
						if p.callback(r.data) { //如果callback返回值是true 。说明pending已经完成。 给p.errc写入nil。 pending完成。
							p.errc <- nil
							plist.Remove(el)
						}
						// Reset the continuous timeout counter (time drift detection)
						contTimeouts = 0
					}
				}
				r.matched <- matched //写入reply的matched
	
			case now := <-timeout.C:   //处理超时信息
				nextTimeout = nil
	
				// Notify and remove callbacks whose deadline is in the past.
				for el := plist.Front(); el != nil; el = el.Next() {
					p := el.Value.(*pending)
					if now.After(p.deadline) || now.Equal(p.deadline) { //如果超时写入超时信息并移除
						p.errc <- errTimeout
						plist.Remove(el)
						contTimeouts++
					}
				}
				// If we've accumulated too many timeouts, do an NTP time sync check
				if contTimeouts > ntpFailureThreshold {
					//如果连续超时很多次。 那么查看是否是时间不同步。 和NTP服务器进行同步。
					if time.Since(ntpWarnTime) >= ntpWarningCooldown {
						ntpWarnTime = time.Now()
						go checkClockDrift()
					}
					contTimeouts = 0
				}
			}
		}
	}

上面看到了pending的处理。 不过loop()方法种还有一个gotreply的处理。 这个实在readLoop()这个goroutine中产生的。

	// readLoop runs in its own goroutine. it handles incoming UDP packets.
	func (t *udp) readLoop() {
		defer t.conn.Close()
		// Discovery packets are defined to be no larger than 1280 bytes.
		// Packets larger than this size will be cut at the end and treated
		// as invalid because their hash won't match.
		buf := make([]byte, 1280)
		for {
			nbytes, from, err := t.conn.ReadFromUDP(buf)
			if netutil.IsTemporaryError(err) {
				// Ignore temporary read errors.
				log.Debug("Temporary UDP read error", "err", err)
				continue
			} else if err != nil {
				// Shut down the loop for permament errors.
				log.Debug("UDP read error", "err", err)
				return
			}
			t.handlePacket(from, buf[:nbytes])
		}
	}

	func (t *udp) handlePacket(from *net.UDPAddr, buf []byte) error {
		packet, fromID, hash, err := decodePacket(buf)
		if err != nil {
			log.Debug("Bad discv4 packet", "addr", from, "err", err)
			return err
		}
		err = packet.handle(t, from, fromID, hash)
		log.Trace("<< "+packet.name(), "addr", from, "err", err)
		return err
	}
	
	func (req *ping) handle(t *udp, from *net.UDPAddr, fromID NodeID, mac []byte) error {
		if expired(req.Expiration) {
			return errExpired
		}
		t.send(from, pongPacket, &pong{
			To:         makeEndpoint(from, req.From.TCP),
			ReplyTok:   mac,
			Expiration: uint64(time.Now().Add(expiration).Unix()),
		})
		if !t.handleReply(fromID, pingPacket, req) {
			// Note: we're ignoring the provided IP address right now
			go t.bond(true, fromID, from, req.From.TCP)
		}
		return nil
	}
	
	func (t *udp) handleReply(from NodeID, ptype byte, req packet) bool {
		matched := make(chan bool, 1)
		select {
		case t.gotreply <- reply{from, ptype, req, matched}:
			// loop will handle it
			return <-matched
		case <-t.closing:
			return false
		}
	}


上面介绍了udp的大致处理的流程。 下面介绍下udp的主要处理的业务。 udp主要发送两种请求，对应的也会接收别人发送的这两种请求， 对应这两种请求又会产生两种回应。

ping请求，可以看到ping请求希望得到一个pong回答。 然后返回。

	// ping sends a ping message to the given node and waits for a reply.
	func (t *udp) ping(toid NodeID, toaddr *net.UDPAddr) error {
		// TODO: maybe check for ReplyTo field in callback to measure RTT
		errc := t.pending(toid, pongPacket, func(interface{}) bool { return true })
		t.send(toaddr, pingPacket, &ping{
			Version:    Version,
			From:       t.ourEndpoint,
			To:         makeEndpoint(toaddr, 0), // TODO: maybe use known TCP port from DB
			Expiration: uint64(time.Now().Add(expiration).Unix()),
		})
		return <-errc
	}

pong回答,如果pong回答没有匹配到一个对应的ping请求。那么返回errUnsolicitedReply异常。

	func (req *pong) handle(t *udp, from *net.UDPAddr, fromID NodeID, mac []byte) error {
		if expired(req.Expiration) {
			return errExpired
		}
		if !t.handleReply(fromID, pongPacket, req) {
			return errUnsolicitedReply
		}
		return nil
	}

findnode请求, 发送findnode请求，然后等待node回应 k个邻居。

	// findnode sends a findnode request to the given node and waits until
	// the node has sent up to k neighbors.
	func (t *udp) findnode(toid NodeID, toaddr *net.UDPAddr, target NodeID) ([]*Node, error) {
		nodes := make([]*Node, 0, bucketSize)
		nreceived := 0
		errc := t.pending(toid, neighborsPacket, func(r interface{}) bool {
			reply := r.(*neighbors)
			for _, rn := range reply.Nodes {
				nreceived++
				n, err := t.nodeFromRPC(toaddr, rn)
				if err != nil {
					log.Trace("Invalid neighbor node received", "ip", rn.IP, "addr", toaddr, "err", err)
					continue
				}
				nodes = append(nodes, n)
			}
			return nreceived >= bucketSize
		})
		t.send(toaddr, findnodePacket, &findnode{
			Target:     target,
			Expiration: uint64(time.Now().Add(expiration).Unix()),
		})
		err := <-errc
		return nodes, err
	}

neighbors回应, 很简单。 把回应发送给gotreply队列。 如果没有找到匹配的findnode请求。返回errUnsolicitedReply错误

	func (req *neighbors) handle(t *udp, from *net.UDPAddr, fromID NodeID, mac []byte) error {
		if expired(req.Expiration) {
			return errExpired
		}
		if !t.handleReply(fromID, neighborsPacket, req) {
			return errUnsolicitedReply
		}
		return nil
	}



收到别的节点发送的ping请求，发送pong回答。 如果没有匹配上一个pending(说明不是自己方请求的结果)。 就调用bond方法把这个节点加入自己的bucket缓存。(这部分原理在table.go里面会详细介绍)

	func (req *ping) handle(t *udp, from *net.UDPAddr, fromID NodeID, mac []byte) error {
		if expired(req.Expiration) {
			return errExpired
		}
		t.send(from, pongPacket, &pong{
			To:         makeEndpoint(from, req.From.TCP),
			ReplyTok:   mac,
			Expiration: uint64(time.Now().Add(expiration).Unix()),
		})
		if !t.handleReply(fromID, pingPacket, req) {
			// Note: we're ignoring the provided IP address right now
			go t.bond(true, fromID, from, req.From.TCP)
		}
		return nil
	}

收到别人发送的findnode请求。这个请求希望把和target距离相近的k个节点发送回去。 算法的详细请参考references目录下面的pdf文档。

	
	func (req *findnode) handle(t *udp, from *net.UDPAddr, fromID NodeID, mac []byte) error {
		if expired(req.Expiration) {
			return errExpired
		}
		if t.db.node(fromID) == nil {
			// No bond exists, we don't process the packet. This prevents
			// an attack vector where the discovery protocol could be used
			// to amplify traffic in a DDOS attack. A malicious actor
			// would send a findnode request with the IP address and UDP
			// port of the target as the source address. The recipient of
			// the findnode packet would then send a neighbors packet
			// (which is a much bigger packet than findnode) to the victim.
			return errUnknownNode
		}
		target := crypto.Keccak256Hash(req.Target[:])
		t.mutex.Lock()
		//获取bucketSize个和target距离相近的节点。 这个方法在table.go内部实现。后续会详细介绍
		closest := t.closest(target, bucketSize).entries
		t.mutex.Unlock()
	
		p := neighbors{Expiration: uint64(time.Now().Add(expiration).Unix())}
		// Send neighbors in chunks with at most maxNeighbors per packet
		// to stay below the 1280 byte limit.
		for i, n := range closest {
			if netutil.CheckRelayIP(from.IP, n.IP) != nil {
				continue
			}
			p.Nodes = append(p.Nodes, nodeToRPC(n))
			if len(p.Nodes) == maxNeighbors || i == len(closest)-1 {
				t.send(from, neighborsPacket, &p)
				p.Nodes = p.Nodes[:0]
			}
		}
		return nil
	}


### udp信息加密和安全问题
discover协议因为没有承载什么敏感数据，所以数据是以明文传输，但是为了确保数据的完整性和不被篡改，所以在数据包的包头加上了数字签名。

	
	func encodePacket(priv *ecdsa.PrivateKey, ptype byte, req interface{}) ([]byte, error) {
		b := new(bytes.Buffer)
		b.Write(headSpace)
		b.WriteByte(ptype)
		if err := rlp.Encode(b, req); err != nil {
			log.Error("Can't encode discv4 packet", "err", err)
			return nil, err
		}
		packet := b.Bytes()
		sig, err := crypto.Sign(crypto.Keccak256(packet[headSize:]), priv)
		if err != nil {
			log.Error("Can't sign discv4 packet", "err", err)
			return nil, err
		}
		copy(packet[macSize:], sig)
		// add the hash to the front. Note: this doesn't protect the
		// packet in any way. Our public key will be part of this hash in
		// The future.
		copy(packet, crypto.Keccak256(packet[macSize:]))
		return packet, nil
	}

	func decodePacket(buf []byte) (packet, NodeID, []byte, error) {
		if len(buf) < headSize+1 {
			return nil, NodeID{}, nil, errPacketTooSmall
		}
		hash, sig, sigdata := buf[:macSize], buf[macSize:headSize], buf[headSize:]
		shouldhash := crypto.Keccak256(buf[macSize:])
		if !bytes.Equal(hash, shouldhash) {
			return nil, NodeID{}, nil, errBadHash
		}
		fromID, err := recoverNodeID(crypto.Keccak256(buf[headSize:]), sig)
		if err != nil {
			return nil, NodeID{}, hash, err
		}
		var req packet
		switch ptype := sigdata[0]; ptype {
		case pingPacket:
			req = new(ping)
		case pongPacket:
			req = new(pong)
		case findnodePacket:
			req = new(findnode)
		case neighborsPacket:
			req = new(neighbors)
		default:
			return nil, fromID, hash, fmt.Errorf("unknown type: %d", ptype)
		}
		s := rlp.NewStream(bytes.NewReader(sigdata[1:]), 0)
		err = s.Decode(req)
		return req, fromID, hash, err
	}