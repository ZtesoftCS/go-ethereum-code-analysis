queue给downloader提供了调度功能和限流的功能。 通过调用Schedule/ScheduleSkeleton来申请对任务进行调度，然后调用ReserveXXX方法来领取调度完成的任务，并在downloader里面的线程来执行，调用DeliverXXX方法把下载完的数据给queue。 最后通过WaitResults来获取已经完成的任务。中间还有一些对任务的额外控制，ExpireXXX用来控制任务是否超时， CancelXXX用来取消任务。



## Schedule方法
Schedule调用申请对一些区块头进行下载调度。可以看到做了一些合法性检查之后，把任务插入了blockTaskPool，receiptTaskPool，receiptTaskQueue，receiptTaskPool。
TaskPool是Map，用来记录header的hash是否存在。 TaskQueue是优先级队列，优先级是区块的高度的负数， 这样区块高度越小的优先级越高，就实现了首先调度小的任务的功能。
	
	// Schedule adds a set of headers for the download queue for scheduling, returning
	// the new headers encountered.
	// from表示headers里面第一个元素的区块高度。 返回值返回了所有被接收的header
	func (q *queue) Schedule(headers []*types.Header, from uint64) []*types.Header {
		q.lock.Lock()
		defer q.lock.Unlock()
	
		// Insert all the headers prioritised by the contained block number
		inserts := make([]*types.Header, 0, len(headers))
		for _, header := range headers {
			// Make sure chain order is honoured and preserved throughout
			hash := header.Hash()
			if header.Number == nil || header.Number.Uint64() != from {
				log.Warn("Header broke chain ordering", "number", header.Number, "hash", hash, "expected", from)
				break
			}
			//headerHead存储了最后一个插入的区块头， 检查当前区块是否正确的链接。
			if q.headerHead != (common.Hash{}) && q.headerHead != header.ParentHash {
				log.Warn("Header broke chain ancestry", "number", header.Number, "hash", hash)
				break
			}
			// Make sure no duplicate requests are executed
			// 检查重复，这里直接continue了，那不是from对不上了。
			if _, ok := q.blockTaskPool[hash]; ok {
				log.Warn("Header  already scheduled for block fetch", "number", header.Number, "hash", hash)
				continue
			}
			if _, ok := q.receiptTaskPool[hash]; ok {
				log.Warn("Header already scheduled for receipt fetch", "number", header.Number, "hash", hash)
				continue
			}
			// Queue the header for content retrieval
			q.blockTaskPool[hash] = header
			q.blockTaskQueue.Push(header, -float32(header.Number.Uint64()))
	
			if q.mode == FastSync && header.Number.Uint64() <= q.fastSyncPivot {
				// Fast phase of the fast sync, retrieve receipts too
				// 如果是快速同步模式，而且区块高度也小于pivot point. 那么还要获取receipt
				q.receiptTaskPool[hash] = header
				q.receiptTaskQueue.Push(header, -float32(header.Number.Uint64()))
			}
			inserts = append(inserts, header)
			q.headerHead = hash
			from++
		}
		return inserts
	}


## ReserveXXX
ReserveXXX方法用来从queue里面领取一些任务来执行。downloader里面的goroutine会调用这个方法来领取一些任务来执行。 这个方法直接调用了reserveHeaders方法。 所有的ReserveXXX方法都会调用reserveHeaders方法，除了传入的参数有一些区别。

	// ReserveBodies reserves a set of body fetches for the given peer, skipping any
	// previously failed downloads. Beside the next batch of needed fetches, it also
	// returns a flag whether empty blocks were queued requiring processing.
	func (q *queue) ReserveBodies(p *peerConnection, count int) (*fetchRequest, bool, error) {
		isNoop := func(header *types.Header) bool {
			return header.TxHash == types.EmptyRootHash && header.UncleHash == types.EmptyUncleHash
		}
		q.lock.Lock()
		defer q.lock.Unlock()
	
		return q.reserveHeaders(p, count, q.blockTaskPool, q.blockTaskQueue, q.blockPendPool, q.blockDonePool, isNoop)
	}

reserveHeaders


	// reserveHeaders reserves a set of data download operations for a given peer,
	// skipping any previously failed ones. This method is a generic version used
	// by the individual special reservation functions.
	// reserveHeaders为指定的peer保留一些下载操作，跳过之前的任意错误。 这个方法单独被指定的保留方法调用。
	// Note, this method expects the queue lock to be already held for writing. The
	// reason the lock is not obtained in here is because the parameters already need
	// to access the queue, so they already need a lock anyway.
	// 这个方法调用的时候，假设已经获取到锁，这个方法里面没有锁的原因是参数已经传入到函数里面了，所以调用的时候就需要获取锁。
	func (q *queue) reserveHeaders(p *peerConnection, count int, taskPool map[common.Hash]*types.Header, taskQueue *prque.Prque,
		pendPool map[string]*fetchRequest, donePool map[common.Hash]struct{}, isNoop func(*types.Header) bool) (*fetchRequest, bool, error) {
		// Short circuit if the pool has been depleted, or if the peer's already
		// downloading something (sanity check not to corrupt state)
		if taskQueue.Empty() {
			return nil, false, nil
		}
		// 如果这个peer还有下载任务没有完成。
		if _, ok := pendPool[p.id]; ok {
			return nil, false, nil
		}
		// Calculate an upper limit on the items we might fetch (i.e. throttling)
		// 计算我们需要获取的上限。
		space := len(q.resultCache) - len(donePool)
		// 还需要减去正在下载的数量。
		for _, request := range pendPool {
			space -= len(request.Headers)
		}
		// Retrieve a batch of tasks, skipping previously failed ones
		send := make([]*types.Header, 0, count)
		skip := make([]*types.Header, 0)
	
		progress := false
		for proc := 0; proc < space && len(send) < count && !taskQueue.Empty(); proc++ {
			header := taskQueue.PopItem().(*types.Header)
	
			// If we're the first to request this task, initialise the result container
			index := int(header.Number.Int64() - int64(q.resultOffset))
			// index 是结果应该存储在resultCache的哪一部分。
			if index >= len(q.resultCache) || index < 0 {
				common.Report("index allocation went beyond available resultCache space")
				return nil, false, errInvalidChain
			}
			if q.resultCache[index] == nil { // 第一次调度 有可能多次调度。 那这里可能就是非空的。
				components := 1
				if q.mode == FastSync && header.Number.Uint64() <= q.fastSyncPivot {
					// 如果是快速同步，那么需要下载的组件还有 收据receipt
					components = 2
				}
				q.resultCache[index] = &fetchResult{
					Pending: components,
					Header:  header,
				}
			}
			// If this fetch task is a noop, skip this fetch operation
			if isNoop(header) {
				// 如果header的区块中没有包含交易，那么不需要获取区块头
				donePool[header.Hash()] = struct{}{}
				delete(taskPool, header.Hash())
	
				space, proc = space-1, proc-1
				q.resultCache[index].Pending--
				progress = true
				continue
			}
			// Otherwise unless the peer is known not to have the data, add to the retrieve list
			// Lacks代表节点之前明确表示过没有这个hash的数据。
			if p.Lacks(header.Hash()) {
				skip = append(skip, header)
			} else {
				send = append(send, header)
			}
		}
		// Merge all the skipped headers back
		for _, header := range skip {
			taskQueue.Push(header, -float32(header.Number.Uint64()))
		}
		if progress {
			// Wake WaitResults, resultCache was modified
			// 通知WaitResults， resultCache有改变
			q.active.Signal()
		}
		// Assemble and return the block download request
		if len(send) == 0 {
			return nil, progress, nil
		}
		request := &fetchRequest{
			Peer:    p,
			Headers: send,
			Time:    time.Now(),
		}
		pendPool[p.id] = request
	
		return request, progress, nil
	}

ReserveReceipts 可以看到和ReserveBodys差不多。不过是队列换了而已。

	// ReserveReceipts reserves a set of receipt fetches for the given peer, skipping
	// any previously failed downloads. Beside the next batch of needed fetches, it
	// also returns a flag whether empty receipts were queued requiring importing.
	func (q *queue) ReserveReceipts(p *peerConnection, count int) (*fetchRequest, bool, error) {
		isNoop := func(header *types.Header) bool {
			return header.ReceiptHash == types.EmptyRootHash
		}
		q.lock.Lock()
		defer q.lock.Unlock()
	
		return q.reserveHeaders(p, count, q.receiptTaskPool, q.receiptTaskQueue, q.receiptPendPool, q.receiptDonePool, isNoop)
	}



## DeliverXXX
Deliver方法在数据下载完之后会被调用。

	// DeliverBodies injects a block body retrieval response into the results queue.
	// The method returns the number of blocks bodies accepted from the delivery and
	// also wakes any threads waiting for data delivery.
	// DeliverBodies把一个 请求区块体的返回值插入到results队列
	// 这个方法返回被delivery的区块体数量，同时会唤醒等待数据的线程
	func (q *queue) DeliverBodies(id string, txLists [][]*types.Transaction, uncleLists [][]*types.Header) (int, error) {
		q.lock.Lock()
		defer q.lock.Unlock()
	
		reconstruct := func(header *types.Header, index int, result *fetchResult) error {
			if types.DeriveSha(types.Transactions(txLists[index])) != header.TxHash || types.CalcUncleHash(uncleLists[index]) != header.UncleHash {
				return errInvalidBody
			}
			result.Transactions = txLists[index]
			result.Uncles = uncleLists[index]
			return nil
		}
		return q.deliver(id, q.blockTaskPool, q.blockTaskQueue, q.blockPendPool, q.blockDonePool, bodyReqTimer, len(txLists), reconstruct)
	}

deliver方法
	
	func (q *queue) deliver(id string, taskPool map[common.Hash]*types.Header, taskQueue *prque.Prque,
		pendPool map[string]*fetchRequest, donePool map[common.Hash]struct{}, reqTimer metrics.Timer,
		results int, reconstruct func(header *types.Header, index int, result *fetchResult) error) (int, error) {
	
		// Short circuit if the data was never requested
		// 检查 数据是否从来没有请求过。
		request := pendPool[id]
		if request == nil {
			return 0, errNoFetchesPending
		}
		reqTimer.UpdateSince(request.Time)
		delete(pendPool, id)
	
		// If no data items were retrieved, mark them as unavailable for the origin peer
		if results == 0 {
			//如果结果为空。 那么标识这个peer没有这些数据。
			for _, header := range request.Headers {
				request.Peer.MarkLacking(header.Hash())
			}
		}
		// Assemble each of the results with their headers and retrieved data parts
		var (
			accepted int
			failure  error
			useful   bool
		)
		for i, header := range request.Headers {
			// Short circuit assembly if no more fetch results are found
			if i >= results {
				break
			}
			// Reconstruct the next result if contents match up
			index := int(header.Number.Int64() - int64(q.resultOffset))
			if index >= len(q.resultCache) || index < 0 || q.resultCache[index] == nil {
				failure = errInvalidChain
				break
			}
			// 调用传入的函数对数据进行构建
			if err := reconstruct(header, i, q.resultCache[index]); err != nil {
				failure = err
				break
			}
			donePool[header.Hash()] = struct{}{}
			q.resultCache[index].Pending--
			useful = true
			accepted++
	
			// Clean up a successful fetch
			// 从taskPool删除。加入donePool
			request.Headers[i] = nil
			delete(taskPool, header.Hash())
		}
		// Return all failed or missing fetches to the queue
		// 所有没有成功的请求加入taskQueue
		for _, header := range request.Headers {
			if header != nil {
				taskQueue.Push(header, -float32(header.Number.Uint64()))
			}
		}
		// Wake up WaitResults
		// 如果结果有变更，通知WaitResults线程启动。
		if accepted > 0 {
			q.active.Signal()
		}
		// If none of the data was good, it's a stale delivery
		switch {
		case failure == nil || failure == errInvalidChain:
			return accepted, failure
		case useful:
			return accepted, fmt.Errorf("partial failure: %v", failure)
		default:
			return accepted, errStaleDelivery
		}
	}


## ExpireXXX and CancelXXX
### ExpireXXX
ExpireBodies函数获取了锁，然后直接调用了expire函数。 

	// ExpireBodies checks for in flight block body requests that exceeded a timeout
	// allowance, canceling them and returning the responsible peers for penalisation.
	func (q *queue) ExpireBodies(timeout time.Duration) map[string]int {
		q.lock.Lock()
		defer q.lock.Unlock()
	
		return q.expire(timeout, q.blockPendPool, q.blockTaskQueue, bodyTimeoutMeter)
	}

expire函数，

	// expire is the generic check that move expired tasks from a pending pool back
	// into a task pool, returning all entities caught with expired tasks.
	// expire是通用检查，将过期任务从待处理池移回任务池，返回所有捕获已到期任务的实体。

	func (q *queue) expire(timeout time.Duration, pendPool map[string]*fetchRequest, taskQueue *prque.Prque, timeoutMeter metrics.Meter) map[string]int {
		// Iterate over the expired requests and return each to the queue
		expiries := make(map[string]int)
		for id, request := range pendPool {
			if time.Since(request.Time) > timeout {
				// Update the metrics with the timeout
				timeoutMeter.Mark(1)
	
				// Return any non satisfied requests to the pool
				if request.From > 0 {
					taskQueue.Push(request.From, -float32(request.From))
				}
				for hash, index := range request.Hashes {
					taskQueue.Push(hash, float32(index))
				}
				for _, header := range request.Headers {
					taskQueue.Push(header, -float32(header.Number.Uint64()))
				}
				// Add the peer to the expiry report along the the number of failed requests
				expirations := len(request.Hashes)
				if expirations < len(request.Headers) {
					expirations = len(request.Headers)
				}
				expiries[id] = expirations
			}
		}
		// Remove the expired requests from the pending pool
		for id := range expiries {
			delete(pendPool, id)
		}
		return expiries
	}


### CancelXXX
Cancle函数取消已经分配的任务， 把任务重新加入到任务池。

	// CancelBodies aborts a body fetch request, returning all pending headers to the
	// task queue.
	func (q *queue) CancelBodies(request *fetchRequest) {
		q.cancel(request, q.blockTaskQueue, q.blockPendPool)
	}

	// Cancel aborts a fetch request, returning all pending hashes to the task queue.
	func (q *queue) cancel(request *fetchRequest, taskQueue *prque.Prque, pendPool map[string]*fetchRequest) {
		q.lock.Lock()
		defer q.lock.Unlock()
	
		if request.From > 0 {
			taskQueue.Push(request.From, -float32(request.From))
		}
		for hash, index := range request.Hashes {
			taskQueue.Push(hash, float32(index))
		}
		for _, header := range request.Headers {
			taskQueue.Push(header, -float32(header.Number.Uint64()))
		}
		delete(pendPool, request.Peer.id)
	}

## ScheduleSkeleton
Schedule方法传入的是已经fetch好的header。Schedule(headers []*types.Header, from uint64)。而ScheduleSkeleton函数的参数是一个骨架， 然后请求对骨架进行填充。所谓的骨架是指我首先每隔192个区块请求一个区块头，然后把返回的header传入ScheduleSkeleton。 在Schedule函数中只需要queue调度区块体和回执的下载，而在ScheduleSkeleton函数中，还需要调度那些缺失的区块头的下载。

	// ScheduleSkeleton adds a batch of header retrieval tasks to the queue to fill
	// up an already retrieved header skeleton.
	func (q *queue) ScheduleSkeleton(from uint64, skeleton []*types.Header) {
		q.lock.Lock()
		defer q.lock.Unlock()
	
		// No skeleton retrieval can be in progress, fail hard if so (huge implementation bug)
		if q.headerResults != nil {
			panic("skeleton assembly already in progress")
		}
		// Shedule all the header retrieval tasks for the skeleton assembly
		// 因为这个方法在skeleton为false的时候不会调用。 所以一些初始化工作放在这里执行。
		q.headerTaskPool = make(map[uint64]*types.Header)
		q.headerTaskQueue = prque.New()
		q.headerPeerMiss = make(map[string]map[uint64]struct{}) // Reset availability to correct invalid chains
		q.headerResults = make([]*types.Header, len(skeleton)*MaxHeaderFetch)
		q.headerProced = 0
		q.headerOffset = from
		q.headerContCh = make(chan bool, 1)
	
		for i, header := range skeleton {
			index := from + uint64(i*MaxHeaderFetch)
			// 每隔MaxHeaderFetch这么远有一个header
			q.headerTaskPool[index] = header
			q.headerTaskQueue.Push(index, -float32(index))
		}
	}

### ReserveHeaders
这个方法只skeleton的模式下才会被调用。 用来给peer保留fetch 区块头的任务。
	
	// ReserveHeaders reserves a set of headers for the given peer, skipping any
	// previously failed batches.
	func (q *queue) ReserveHeaders(p *peerConnection, count int) *fetchRequest {
		q.lock.Lock()
		defer q.lock.Unlock()
	
		// Short circuit if the peer's already downloading something (sanity check to
		// not corrupt state)
		if _, ok := q.headerPendPool[p.id]; ok {
			return nil
		}
		// Retrieve a batch of hashes, skipping previously failed ones
		// 从队列中获取一个，跳过之前失败过的节点。
		send, skip := uint64(0), []uint64{}
		for send == 0 && !q.headerTaskQueue.Empty() {
			from, _ := q.headerTaskQueue.Pop()
			if q.headerPeerMiss[p.id] != nil {
				if _, ok := q.headerPeerMiss[p.id][from.(uint64)]; ok {
					skip = append(skip, from.(uint64))
					continue
				}
			}
			send = from.(uint64)
		}
		// Merge all the skipped batches back
		for _, from := range skip {
			q.headerTaskQueue.Push(from, -float32(from))
		}
		// Assemble and return the block download request
		if send == 0 {
			return nil
		}
		request := &fetchRequest{
			Peer: p,
			From: send,
			Time: time.Now(),
		}
		q.headerPendPool[p.id] = request
		return request
	}


### DeliverHeaders

	
	// DeliverHeaders injects a header retrieval response into the header results
	// cache. This method either accepts all headers it received, or none of them
	// if they do not map correctly to the skeleton.
	// 这个方法对于所有的区块头，要么全部接收，要么全部拒绝(如果不能映射到一个skeleton上面)
	// If the headers are accepted, the method makes an attempt to deliver the set
	// of ready headers to the processor to keep the pipeline full. However it will
	// not block to prevent stalling other pending deliveries.
	// 如果区块头被接收，这个方法会试图把他们投递到headerProcCh管道上面。 不过这个方法不会阻塞式的投递。而是尝试投递，如果不能投递就返回。
	func (q *queue) DeliverHeaders(id string, headers []*types.Header, headerProcCh chan []*types.Header) (int, error) {
		q.lock.Lock()
		defer q.lock.Unlock()
	
		// Short circuit if the data was never requested
		request := q.headerPendPool[id]
		if request == nil {
			return 0, errNoFetchesPending
		}
		headerReqTimer.UpdateSince(request.Time)
		delete(q.headerPendPool, id)
	
		// Ensure headers can be mapped onto the skeleton chain
		target := q.headerTaskPool[request.From].Hash()
	
		accepted := len(headers) == MaxHeaderFetch
		if accepted { //首先长度需要匹配， 然后检查区块号和最后一块区块的Hash值是否能够对应上。
			if headers[0].Number.Uint64() != request.From {
				log.Trace("First header broke chain ordering", "peer", id, "number", headers[0].Number, "hash", headers[0].Hash(), request.From)
				accepted = false
			} else if headers[len(headers)-1].Hash() != target {
				log.Trace("Last header broke skeleton structure ", "peer", id, "number", headers[len(headers)-1].Number, "hash", headers[len(headers)-1].Hash(), "expected", target)
				accepted = false
			}
		}
		if accepted {// 依次检查每一块区块的区块号， 以及链接是否正确。
			for i, header := range headers[1:] {
				hash := header.Hash()
				if want := request.From + 1 + uint64(i); header.Number.Uint64() != want {
					log.Warn("Header broke chain ordering", "peer", id, "number", header.Number, "hash", hash, "expected", want)
					accepted = false
					break
				}
				if headers[i].Hash() != header.ParentHash {
					log.Warn("Header broke chain ancestry", "peer", id, "number", header.Number, "hash", hash)
					accepted = false
					break
				}
			}
		}
		// If the batch of headers wasn't accepted, mark as unavailable
		if !accepted { // 如果不被接收，那么标记这个peer在这个任务上的失败。下次请求就不会投递给这个peer
			log.Trace("Skeleton filling not accepted", "peer", id, "from", request.From)
	
			miss := q.headerPeerMiss[id]
			if miss == nil {
				q.headerPeerMiss[id] = make(map[uint64]struct{})
				miss = q.headerPeerMiss[id]
			}
			miss[request.From] = struct{}{}
	
			q.headerTaskQueue.Push(request.From, -float32(request.From))
			return 0, errors.New("delivery not accepted")
		}
		// Clean up a successful fetch and try to deliver any sub-results
		copy(q.headerResults[request.From-q.headerOffset:], headers)
		delete(q.headerTaskPool, request.From)
	
		ready := 0
		for q.headerProced+ready < len(q.headerResults) && q.headerResults[q.headerProced+ready] != nil {//计算这次到来的header可以让headerResults有多少数据可以投递了。
			ready += MaxHeaderFetch
		}
		if ready > 0 {
			// Headers are ready for delivery, gather them and push forward (non blocking)
			process := make([]*types.Header, ready)
			copy(process, q.headerResults[q.headerProced:q.headerProced+ready])
			// 尝试投递
			select {
			case headerProcCh <- process:
				log.Trace("Pre-scheduled new headers", "peer", id, "count", len(process), "from", process[0].Number)
				q.headerProced += len(process)
			default:
			}
		}
		// Check for termination and return
		if len(q.headerTaskPool) == 0 {
			// 这个通道比较重要， 如果这个通道接收到数据，说明所有的header任务已经完成。
			q.headerContCh <- false
		}
		return len(headers), nil
	}

RetrieveHeaders，ScheduleSkeleton函数在上次调度还没有做完的情况下是不会调用的。 所以上次调用完成之后，会使用这个方法来获取结果，重置状态。
	
	// RetrieveHeaders retrieves the header chain assemble based on the scheduled
	// skeleton.
	func (q *queue) RetrieveHeaders() ([]*types.Header, int) {
		q.lock.Lock()
		defer q.lock.Unlock()
	
		headers, proced := q.headerResults, q.headerProced
		q.headerResults, q.headerProced = nil, 0
	
		return headers, proced
	}