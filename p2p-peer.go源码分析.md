在p2p代码里面。 peer代表了一条创建好的网络链路。在一条链路上可能运行着多个协议。比如以太坊的协议(eth)。 Swarm的协议。 或者是Whisper的协议。

peer的结构

	type protoRW struct {
		Protocol
		in     chan Msg        // receices read messages
		closed <-chan struct{} // receives when peer is shutting down
		wstart <-chan struct{} // receives when write may start
		werr   chan<- error    // for write results
		offset uint64
		w      MsgWriter
	}

	// Protocol represents a P2P subprotocol implementation.
	type Protocol struct {
		// Name should contain the official protocol name,
		// often a three-letter word.
		Name string
	
		// Version should contain the version number of the protocol.
		Version uint
	
		// Length should contain the number of message codes used
		// by the protocol.
		Length uint64
	
		// Run is called in a new groutine when the protocol has been
		// negotiated with a peer. It should read and write messages from
		// rw. The Payload for each message must be fully consumed.
		//
		// The peer connection is closed when Start returns. It should return
		// any protocol-level error (such as an I/O error) that is
		// encountered.
		Run func(peer *Peer, rw MsgReadWriter) error
	
		// NodeInfo is an optional helper method to retrieve protocol specific metadata
		// about the host node.
		NodeInfo func() interface{}
	
		// PeerInfo is an optional helper method to retrieve protocol specific metadata
		// about a certain peer in the network. If an info retrieval function is set,
		// but returns nil, it is assumed that the protocol handshake is still running.
		PeerInfo func(id discover.NodeID) interface{}
	}

	// Peer represents a connected remote node.
	type Peer struct {
		rw      *conn
		running map[string]*protoRW   //运行的协议
		log     log.Logger
		created mclock.AbsTime
	
		wg       sync.WaitGroup
		protoErr chan error
		closed   chan struct{}
		disc     chan DiscReason
	
		// events receives message send / receive events if set
		events *event.Feed
	}

peer的创建，根据匹配找到当前Peer支持的protomap

	func newPeer(conn *conn, protocols []Protocol) *Peer {
		protomap := matchProtocols(protocols, conn.caps, conn)
		p := &Peer{
			rw:       conn,
			running:  protomap,
			created:  mclock.Now(),
			disc:     make(chan DiscReason),
			protoErr: make(chan error, len(protomap)+1), // protocols + pingLoop
			closed:   make(chan struct{}),
			log:      log.New("id", conn.id, "conn", conn.flags),
		}
		return p
	}

peer的启动， 启动了两个goroutine线程。 一个是读取。一个是执行ping操作。

	func (p *Peer) run() (remoteRequested bool, err error) {
		var (
			writeStart = make(chan struct{}, 1)  //用来控制什么时候可以写入的管道。
			writeErr   = make(chan error, 1)
			readErr    = make(chan error, 1)
			reason     DiscReason // sent to the peer
		)
		p.wg.Add(2)
		go p.readLoop(readErr)
		go p.pingLoop()
	
		// Start all protocol handlers.
		writeStart <- struct{}{}
		//启动所有的协议。
		p.startProtocols(writeStart, writeErr)
	
		// Wait for an error or disconnect.
	loop:
		for {
			select {
			case err = <-writeErr:
				// A write finished. Allow the next write to start if
				// there was no error.
				if err != nil {
					reason = DiscNetworkError
					break loop
				}
				writeStart <- struct{}{}
			case err = <-readErr:
				if r, ok := err.(DiscReason); ok {
					remoteRequested = true
					reason = r
				} else {
					reason = DiscNetworkError
				}
				break loop
			case err = <-p.protoErr:
				reason = discReasonForError(err)
				break loop
			case err = <-p.disc:
				break loop
			}
		}
	
		close(p.closed)
		p.rw.close(reason)
		p.wg.Wait()
		return remoteRequested, err
	}

startProtocols方法，这个方法遍历所有的协议。

	func (p *Peer) startProtocols(writeStart <-chan struct{}, writeErr chan<- error) {
		p.wg.Add(len(p.running))
		for _, proto := range p.running {
			proto := proto
			proto.closed = p.closed
			proto.wstart = writeStart
			proto.werr = writeErr
			var rw MsgReadWriter = proto
			if p.events != nil {
				rw = newMsgEventer(rw, p.events, p.ID(), proto.Name)
			}
			p.log.Trace(fmt.Sprintf("Starting protocol %s/%d", proto.Name, proto.Version))
			// 等于这里为每一个协议都开启了一个goroutine。 调用其Run方法。
			go func() {
				// proto.Run(p, rw)这个方法应该是一个死循环。 如果返回就说明遇到了错误。
				err := proto.Run(p, rw)
				if err == nil {
					p.log.Trace(fmt.Sprintf("Protocol %s/%d returned", proto.Name, proto.Version))
					err = errProtocolReturned
				} else if err != io.EOF {
					p.log.Trace(fmt.Sprintf("Protocol %s/%d failed", proto.Name, proto.Version), "err", err)
				}
				p.protoErr <- err
				p.wg.Done()
			}()
		}
	}


回过头来再看看readLoop方法。 这个方法也是一个死循环。 调用p.rw来读取一个Msg(这个rw实际是之前提到的frameRLPx的对象，也就是分帧之后的对象。然后根据Msg的类型进行对应的处理，如果Msg的类型是内部运行的协议的类型。那么发送到对应协议的proto.in队列上面。

	
	func (p *Peer) readLoop(errc chan<- error) {
		defer p.wg.Done()
		for {
			msg, err := p.rw.ReadMsg()
			if err != nil {
				errc <- err
				return
			}
			msg.ReceivedAt = time.Now()
			if err = p.handle(msg); err != nil {
				errc <- err
				return
			}
		}
	}
	func (p *Peer) handle(msg Msg) error {
		switch {
		case msg.Code == pingMsg:
			msg.Discard()
			go SendItems(p.rw, pongMsg)
		case msg.Code == discMsg:
			var reason [1]DiscReason
			// This is the last message. We don't need to discard or
			// check errors because, the connection will be closed after it.
			rlp.Decode(msg.Payload, &reason)
			return reason[0]
		case msg.Code < baseProtocolLength:
			// ignore other base protocol messages
			return msg.Discard()
		default:
			// it's a subprotocol message
			proto, err := p.getProto(msg.Code)
			if err != nil {
				return fmt.Errorf("msg code out of range: %v", msg.Code)
			}
			select {
			case proto.in <- msg:
				return nil
			case <-p.closed:
				return io.EOF
			}
		}
		return nil
	}

在看看pingLoop。这个方法很简单。就是定时的发送pingMsg消息到对端。
	
	func (p *Peer) pingLoop() {
		ping := time.NewTimer(pingInterval)
		defer p.wg.Done()
		defer ping.Stop()
		for {
			select {
			case <-ping.C:
				if err := SendItems(p.rw, pingMsg); err != nil {
					p.protoErr <- err
					return
				}
				ping.Reset(pingInterval)
			case <-p.closed:
				return
			}
		}
	}

最后再看看protoRW的read和write方法。 可以看到读取和写入都是阻塞式的。
	
	func (rw *protoRW) WriteMsg(msg Msg) (err error) {
		if msg.Code >= rw.Length {
			return newPeerError(errInvalidMsgCode, "not handled")
		}
		msg.Code += rw.offset
		select {
		case <-rw.wstart:  //等到可以写入的受在执行写入。 这难道是为了多线程控制么。
			err = rw.w.WriteMsg(msg)
			// Report write status back to Peer.run. It will initiate
			// shutdown if the error is non-nil and unblock the next write
			// otherwise. The calling protocol code should exit for errors
			// as well but we don't want to rely on that.
			rw.werr <- err
		case <-rw.closed:
			err = fmt.Errorf("shutting down")
		}
		return err
	}
	
	func (rw *protoRW) ReadMsg() (Msg, error) {
		select {
		case msg := <-rw.in:
			msg.Code -= rw.offset
			return msg, nil
		case <-rw.closed:
			return Msg{}, io.EOF
		}
	}
