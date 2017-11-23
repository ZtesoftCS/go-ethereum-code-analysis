## nonceHeap
nonceHeap实现了一个heap.Interface的数据结构，用来实现了一个堆的数据结构。 在heap.Interface的文档介绍中，默认实现的是最小堆。

如果h是一个数组，只要数组中的数据满足下面的要求。那么就认为h是一个最小堆。

	!h.Less(j, i) for 0 <= i < h.Len() and 2*i+1 <= j <= 2*i+2 and j < h.Len()
	// 把数组看成是一颗满的二叉树，第一个元素是树根，第二和第三个元素是树根的两个树枝，
	// 这样依次推下去 那么如果树根是  i 那么它的两个树枝就是 2*i+2 和 2*i + 2。
	// 最小堆的定义是 任意的树根不能比它的两个树枝大。 也就是上面的代码描述的定义。
	heap.Interface的定义
	
	我们只需要定义满足下面接口的数据结构，就能够使用heap的一些方法来实现为堆结构。
	type Interface interface {
		sort.Interface
		Push(x interface{}) // add x as element Len() 把x增加到最后
		Pop() interface{}   //  remove and return element Len() - 1. 移除并返回最后的一个元素
	}

nonceHeap的代码分析。

	// nonceHeap is a heap.Interface implementation over 64bit unsigned integers for
	// retrieving sorted transactions from the possibly gapped future queue.
	type nonceHeap []uint64
	
	func (h nonceHeap) Len() int           { return len(h) }
	func (h nonceHeap) Less(i, j int) bool { return h[i] < h[j] }
	func (h nonceHeap) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
	
	func (h *nonceHeap) Push(x interface{}) {
		*h = append(*h, x.(uint64))
	}
	
	func (h *nonceHeap) Pop() interface{} {
		old := *h
		n := len(old)
		x := old[n-1]
		*h = old[0 : n-1]
		return x
	}


## txSortedMap

txSortedMap,存储的是同一个账号下面的所有的交易。

结构

	// txSortedMap is a nonce->transaction hash map with a heap based index to allow
	// iterating over the contents in a nonce-incrementing way.
	// txSortedMap是一个具有基于堆的索引的nonce->交易 的hashmap，
	// 允许以nonce递增的方式迭代内容。
	
	type Transactions []*Transaction 

	type txSortedMap struct {
		items map[uint64]*types.Transaction // Hash map storing the transaction data
		index *nonceHeap                    // Heap of nonces of all the stored transactions (non-strict mode)
		cache types.Transactions            // Cache of the transactions already sorted 用来缓存已经排好序的交易。
	}

Put 和 Get, Get用于获取指定nonce的交易， Put用来把交易插入到map中。
	
	// Get retrieves the current transactions associated with the given nonce.
	func (m *txSortedMap) Get(nonce uint64) *types.Transaction {
		return m.items[nonce]
	}
	
	// Put inserts a new transaction into the map, also updating the map's nonce
	// index. If a transaction already exists with the same nonce, it's overwritten.
	// 把一个新的事务插入到map中，同时更新map的nonce索引。 如果一个事务已经存在，就把它覆盖。 同时任何缓存的数据会被删除。
	func (m *txSortedMap) Put(tx *types.Transaction) {
		nonce := tx.Nonce()
		if m.items[nonce] == nil {
			heap.Push(m.index, nonce)
		}
		m.items[nonce], m.cache = tx, nil
	}

Forward用于删除所有nonce小于threshold的交易。 然后返回所有被移除的交易。
	
	// Forward removes all transactions from the map with a nonce lower than the
	// provided threshold. Every removed transaction is returned for any post-removal
	// maintenance.
	func (m *txSortedMap) Forward(threshold uint64) types.Transactions {
		var removed types.Transactions
	
		// Pop off heap items until the threshold is reached
		for m.index.Len() > 0 && (*m.index)[0] < threshold {
			nonce := heap.Pop(m.index).(uint64)
			removed = append(removed, m.items[nonce])
			delete(m.items, nonce)
		}
		// If we had a cached order, shift the front
		// cache是排好序的交易。 
		if m.cache != nil {
			m.cache = m.cache[len(removed):]
		}
		return removed
	}
	
Filter, 删除所有令filter函数调用返回true的交易，并返回那些交易。
			
	// Filter iterates over the list of transactions and removes all of them for which
	// the specified function evaluates to true.
	func (m *txSortedMap) Filter(filter func(*types.Transaction) bool) types.Transactions {
		var removed types.Transactions
	
		// Collect all the transactions to filter out
		for nonce, tx := range m.items {
			if filter(tx) {
				removed = append(removed, tx)
				delete(m.items, nonce)
			}
		}
		// If transactions were removed, the heap and cache are ruined
		// 如果事务被删除，堆和缓存被毁坏
		if len(removed) > 0 {
			*m.index = make([]uint64, 0, len(m.items))
			for nonce := range m.items {
				*m.index = append(*m.index, nonce)
			}
			// 需要重建堆
			heap.Init(m.index)
			// 设置cache为nil
			m.cache = nil
		}
		return removed
	}

Cap 对items里面的数量有限制，返回超过限制的所有交易。
	
	// Cap places a hard limit on the number of items, returning all transactions
	// exceeding that limit.
	// Cap 对items里面的数量有限制，返回超过限制的所有交易。
	func (m *txSortedMap) Cap(threshold int) types.Transactions {
		// Short circuit if the number of items is under the limit
		if len(m.items) <= threshold {
			return nil
		}
		// Otherwise gather and drop the highest nonce'd transactions
		var drops types.Transactions
	
		sort.Sort(*m.index) //从小到大排序 从尾部删除。
		for size := len(m.items); size > threshold; size-- {
			drops = append(drops, m.items[(*m.index)[size-1]])
			delete(m.items, (*m.index)[size-1])
		}
		*m.index = (*m.index)[:threshold]
		// 重建堆
		heap.Init(m.index)
	
		// If we had a cache, shift the back
		if m.cache != nil {
			m.cache = m.cache[:len(m.cache)-len(drops)]
		}
		return drops
	}

Remove
	
	// Remove deletes a transaction from the maintained map, returning whether the
	// transaction was found.
	// 
	func (m *txSortedMap) Remove(nonce uint64) bool {
		// Short circuit if no transaction is present
		_, ok := m.items[nonce]
		if !ok {
			return false
		}
		// Otherwise delete the transaction and fix the heap index
		for i := 0; i < m.index.Len(); i++ {
			if (*m.index)[i] == nonce {
				heap.Remove(m.index, i)
				break
			}
		}
		delete(m.items, nonce)
		m.cache = nil
	
		return true
	}

Ready函数	
	
	// Ready retrieves a sequentially increasing list of transactions starting at the
	// provided nonce that is ready for processing. The returned transactions will be
	// removed from the list.
	// Ready 返回一个从指定nonce开始，连续的交易。 返回的交易会被删除。
	// Note, all transactions with nonces lower than start will also be returned to
	// prevent getting into and invalid state. This is not something that should ever
	// happen but better to be self correcting than failing!
	// 注意，请注意，所有具有低于start的nonce的交易也将被返回，以防止进入和无效状态。 
	// 这不是应该发生的事情，而是自我纠正而不是失败！
	func (m *txSortedMap) Ready(start uint64) types.Transactions {
		// Short circuit if no transactions are available
		if m.index.Len() == 0 || (*m.index)[0] > start {
			return nil
		}
		// Otherwise start accumulating incremental transactions
		var ready types.Transactions
		// 从最小的开始，一个一个的增加，
		for next := (*m.index)[0]; m.index.Len() > 0 && (*m.index)[0] == next; next++ {
			ready = append(ready, m.items[next])
			delete(m.items, next)
			heap.Pop(m.index)
		}
		m.cache = nil
	
		return ready
	}

Flatten,返回一个基于nonce排序的交易列表。并缓存到cache字段里面，以便在没有修改的情况下反复使用。
	
	// Len returns the length of the transaction map.
	func (m *txSortedMap) Len() int {
		return len(m.items)
	}
	
	// Flatten creates a nonce-sorted slice of transactions based on the loosely
	// sorted internal representation. The result of the sorting is cached in case
	// it's requested again before any modifications are made to the contents.
	func (m *txSortedMap) Flatten() types.Transactions {
		// If the sorting was not cached yet, create and cache it
		if m.cache == nil {
			m.cache = make(types.Transactions, 0, len(m.items))
			for _, tx := range m.items {
				m.cache = append(m.cache, tx)
			}
			sort.Sort(types.TxByNonce(m.cache))
		}
		// Copy the cache to prevent accidental modifications
		txs := make(types.Transactions, len(m.cache))
		copy(txs, m.cache)
		return txs
	}

## txList
txList 是属于同一个账号的交易列表， 按照nonce排序。可以用来存储连续的可执行的交易。对于非连续的交易,有一些小的不同的行为。

结构
	
	// txList is a "list" of transactions belonging to an account, sorted by account
	// nonce. The same type can be used both for storing contiguous transactions for
	// the executable/pending queue; and for storing gapped transactions for the non-
	// executable/future queue, with minor behavioral changes.
	type txList struct {
		strict bool         // Whether nonces are strictly continuous or not nonces是严格连续的还是非连续的
		txs    *txSortedMap // Heap indexed sorted hash map of the transactions 基于堆索引的交易的hashmap
	
		costcap *big.Int // Price of the highest costing transaction (reset only if exceeds balance)  所有交易里面，GasPrice * GasLimit最高的值
		gascap  *big.Int // Gas limit of the highest spending transaction (reset only if exceeds block limit) 所有交易里面， GasPrice最高的值
	}
Overlaps 返回给定的交易是否有具有相同nonce的交易存在。

	// Overlaps returns whether the transaction specified has the same nonce as one
	// already contained within the list.
	// 
	func (l *txList) Overlaps(tx *types.Transaction) bool {
		return l.txs.Get(tx.Nonce()) != nil
	}
Add 执行这样的操作，如果新的交易比老的交易的GasPrice值要高出一定的比值priceBump，那么会替换老的交易。
	
	// Add tries to insert a new transaction into the list, returning whether the
	// transaction was accepted, and if yes, any previous transaction it replaced.
	// Add 尝试插入一个新的交易，返回交易是否被接收，如果被接收，那么任意之前的交易会被替换。
	// If the new transaction is accepted into the list, the lists' cost and gas
	// thresholds are also potentially updated.
	// 如果新的交易被接收，那么总的cost和gas限制会被更新。
	func (l *txList) Add(tx *types.Transaction, priceBump uint64) (bool, *types.Transaction) {
		// If there's an older better transaction, abort
		// 如果存在老的交易。 而且新的交易的价格比老的高出一定的数量。那么替换。
		old := l.txs.Get(tx.Nonce())
		if old != nil {
			threshold := new(big.Int).Div(new(big.Int).Mul(old.GasPrice(), big.NewInt(100+int64(priceBump))), big.NewInt(100))
			if threshold.Cmp(tx.GasPrice()) >= 0 {
				return false, nil
			}
		}
		// Otherwise overwrite the old transaction with the current one
		l.txs.Put(tx)
		if cost := tx.Cost(); l.costcap.Cmp(cost) < 0 {
			l.costcap = cost
		}
		if gas := tx.Gas(); l.gascap.Cmp(gas) < 0 {
			l.gascap = gas
		}
		return true, old
	}
Forward 删除nonce小于某个值的所有交易。

	// Forward removes all transactions from the list with a nonce lower than the
	// provided threshold. Every removed transaction is returned for any post-removal
	// maintenance.
	func (l *txList) Forward(threshold uint64) types.Transactions {
		return l.txs.Forward(threshold)
	}

Filter,
	
	// Filter removes all transactions from the list with a cost or gas limit higher
	// than the provided thresholds. Every removed transaction is returned for any
	// post-removal maintenance. Strict-mode invalidated transactions are also
	// returned.
	// Filter 移除所有比提供的cost或者gasLimit的值更高的交易。 被移除的交易会返回以便进一步处理。 在严格模式下，所有无效的交易同样被返回。
	// 
	// This method uses the cached costcap and gascap to quickly decide if there's even
	// a point in calculating all the costs or if the balance covers all. If the threshold
	// is lower than the costgas cap, the caps will be reset to a new high after removing
	// the newly invalidated transactions.
	// 这个方法会使用缓存的costcap和gascap以便快速的决定是否需要遍历所有的交易。如果限制小于缓存的costcap和gascap，那么在移除不合法的交易之后会更新costcap和gascap的值。

	func (l *txList) Filter(costLimit, gasLimit *big.Int) (types.Transactions, types.Transactions) {
		// If all transactions are below the threshold, short circuit
		// 如果所有的交易都小于限制，那么直接返回。
		if l.costcap.Cmp(costLimit) <= 0 && l.gascap.Cmp(gasLimit) <= 0 {
			return nil, nil
		}
		l.costcap = new(big.Int).Set(costLimit) // Lower the caps to the thresholds
		l.gascap = new(big.Int).Set(gasLimit)
	
		// Filter out all the transactions above the account's funds
		removed := l.txs.Filter(func(tx *types.Transaction) bool { return tx.Cost().Cmp(costLimit) > 0 || tx.Gas().Cmp(gasLimit) > 0 })
	
		// If the list was strict, filter anything above the lowest nonce
		var invalids types.Transactions
	
		if l.strict && len(removed) > 0 {
			// 所有的nonce大于 最小的被移除的nonce的交易都被任务是无效的。
			// 在严格模式下，这种交易也被移除。
			lowest := uint64(math.MaxUint64)
			for _, tx := range removed {
				if nonce := tx.Nonce(); lowest > nonce {
					lowest = nonce
				}
			}
			invalids = l.txs.Filter(func(tx *types.Transaction) bool { return tx.Nonce() > lowest })
		}
		return removed, invalids
	}

Cap函数用来返回超过数量的交易。 如果交易的数量超过threshold,那么把之后的交易移除并返回。
	
	// Cap places a hard limit on the number of items, returning all transactions
	// exceeding that limit.
	func (l *txList) Cap(threshold int) types.Transactions {
		return l.txs.Cap(threshold)
	}

Remove,删除给定Nonce的交易，如果在严格模式下，还删除所有nonce大于给定Nonce的交易，并返回。
	
	// Remove deletes a transaction from the maintained list, returning whether the
	// transaction was found, and also returning any transaction invalidated due to
	// the deletion (strict mode only).
	func (l *txList) Remove(tx *types.Transaction) (bool, types.Transactions) {
		// Remove the transaction from the set
		nonce := tx.Nonce()
		if removed := l.txs.Remove(nonce); !removed {
			return false, nil
		}
		// In strict mode, filter out non-executable transactions
		if l.strict {
			return true, l.txs.Filter(func(tx *types.Transaction) bool { return tx.Nonce() > nonce })
		}
		return true, nil
	}

Ready， len, Empty, Flatten 直接调用了txSortedMap的对应方法。

	// Ready retrieves a sequentially increasing list of transactions starting at the
	// provided nonce that is ready for processing. The returned transactions will be
	// removed from the list.
	//
	// Note, all transactions with nonces lower than start will also be returned to
	// prevent getting into and invalid state. This is not something that should ever
	// happen but better to be self correcting than failing!
	func (l *txList) Ready(start uint64) types.Transactions {
		return l.txs.Ready(start)
	}

	// Len returns the length of the transaction list.
	func (l *txList) Len() int {
		return l.txs.Len()
	}

	// Empty returns whether the list of transactions is empty or not.
	func (l *txList) Empty() bool {
		return l.Len() == 0
	}

	// Flatten creates a nonce-sorted slice of transactions based on the loosely
	// sorted internal representation. The result of the sorting is cached in case
	// it's requested again before any modifications are made to the contents.
	func (l *txList) Flatten() types.Transactions {
		return l.txs.Flatten()
	}


## priceHeap
priceHeap是一个最小堆， 按照价格的大小来建堆。
	
	// priceHeap is a heap.Interface implementation over transactions for retrieving
	// price-sorted transactions to discard when the pool fills up.
	type priceHeap []*types.Transaction
	
	func (h priceHeap) Len() int           { return len(h) }
	func (h priceHeap) Less(i, j int) bool { return h[i].GasPrice().Cmp(h[j].GasPrice()) < 0 }
	func (h priceHeap) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
	
	func (h *priceHeap) Push(x interface{}) {
		*h = append(*h, x.(*types.Transaction))
	}
	
	func (h *priceHeap) Pop() interface{} {
		old := *h
		n := len(old)
		x := old[n-1]
		*h = old[0 : n-1]
		return x
	}


## txPricedList
数据结构和构建,txPricedList 是基于价格排序的堆，允许按照价格递增的方式处理交易。

	
	// txPricedList is a price-sorted heap to allow operating on transactions pool
	// contents in a price-incrementing way.
	type txPricedList struct {
		all    *map[common.Hash]*types.Transaction // Pointer to the map of all transactions 这是一个指针，指向了所有交易的map
		items  *priceHeap                          // Heap of prices of all the stored transactions
		stales int                                 // Number of stale price points to (re-heap trigger)
	}
	
	// newTxPricedList creates a new price-sorted transaction heap.
	func newTxPricedList(all *map[common.Hash]*types.Transaction) *txPricedList {
		return &txPricedList{
			all:   all,
			items: new(priceHeap),
		}
	}

Put

	// Put inserts a new transaction into the heap.
	func (l *txPricedList) Put(tx *types.Transaction) {
		heap.Push(l.items, tx)
	}

Removed

	// Removed notifies the prices transaction list that an old transaction dropped
	// from the pool. The list will just keep a counter of stale objects and update
	// the heap if a large enough ratio of transactions go stale.
	// Removed 用来通知txPricedList有一个老的交易被删除. txPricedList使用一个计数器来决定何时更新堆信息.
	func (l *txPricedList) Removed() {
		// Bump the stale counter, but exit if still too low (< 25%)
		l.stales++
		if l.stales <= len(*l.items)/4 {
			return
		}
		// Seems we've reached a critical number of stale transactions, reheap
		reheap := make(priceHeap, 0, len(*l.all))
	
		l.stales, l.items = 0, &reheap
		for _, tx := range *l.all {
			*l.items = append(*l.items, tx)
		}
		heap.Init(l.items)
	}

Cap 用来找到所有低于给定价格阈值的交易. 把他们从priceList删除并返回.
	
	// Cap finds all the transactions below the given price threshold, drops them
	// from the priced list and returs them for further removal from the entire pool.
	func (l *txPricedList) Cap(threshold *big.Int, local *accountSet) types.Transactions {
		drop := make(types.Transactions, 0, 128) // Remote underpriced transactions to drop
		save := make(types.Transactions, 0, 64)  // Local underpriced transactions to keep
	
		for len(*l.items) > 0 {
			// Discard stale transactions if found during cleanup
			tx := heap.Pop(l.items).(*types.Transaction)
			if _, ok := (*l.all)[tx.Hash()]; !ok {
				// 如果发现一个已经删除的,那么更新states计数器
				l.stales--
				continue
			}
			// Stop the discards if we've reached the threshold
			if tx.GasPrice().Cmp(threshold) >= 0 {
				// 如果价格不小于阈值, 那么退出
				save = append(save, tx)
				break
			}
			// Non stale transaction found, discard unless local
			if local.containsTx(tx) {  //本地的交易不会删除
				save = append(save, tx)
			} else {
				drop = append(drop, tx)
			}
		}
		for _, tx := range save {
			heap.Push(l.items, tx)
		}
		return drop
	}


Underpriced, 检查 tx是否比 当前txPricedList里面最便宜的交易还要便宜或者是同样便宜.
	
	// Underpriced checks whether a transaction is cheaper than (or as cheap as) the
	// lowest priced transaction currently being tracked.
	func (l *txPricedList) Underpriced(tx *types.Transaction, local *accountSet) bool {
		// Local transactions cannot be underpriced
		if local.containsTx(tx) {
			return false
		}
		// Discard stale price points if found at the heap start
		for len(*l.items) > 0 {
			head := []*types.Transaction(*l.items)[0]
			if _, ok := (*l.all)[head.Hash()]; !ok {
				l.stales--
				heap.Pop(l.items)
				continue
			}
			break
		}
		// Check if the transaction is underpriced or not
		if len(*l.items) == 0 {
			log.Error("Pricing query for empty pool") // This cannot happen, print to catch programming errors
			return false
		}
		cheapest := []*types.Transaction(*l.items)[0]
		return cheapest.GasPrice().Cmp(tx.GasPrice()) >= 0
	}

Discard,查找一定数量的最便宜的交易,把他们从当前的列表删除并返回.
	
	// Discard finds a number of most underpriced transactions, removes them from the
	// priced list and returns them for further removal from the entire pool.
	func (l *txPricedList) Discard(count int, local *accountSet) types.Transactions {
		drop := make(types.Transactions, 0, count) // Remote underpriced transactions to drop
		save := make(types.Transactions, 0, 64)    // Local underpriced transactions to keep
	
		for len(*l.items) > 0 && count > 0 {
			// Discard stale transactions if found during cleanup
			tx := heap.Pop(l.items).(*types.Transaction)
			if _, ok := (*l.all)[tx.Hash()]; !ok {
				l.stales--
				continue
			}
			// Non stale transaction found, discard unless local
			if local.containsTx(tx) {
				save = append(save, tx)
			} else {
				drop = append(drop, tx)
				count--
			}
		}
		for _, tx := range save {
			heap.Push(l.items, tx)
		}
		return drop
	}


## accountSet
accountSet 就是一个账号的集合和一个处理签名的对象.
	
	// accountSet is simply a set of addresses to check for existence, and a signer
	// capable of deriving addresses from transactions.
	type accountSet struct {
		accounts map[common.Address]struct{}
		signer   types.Signer
	}
	
	// newAccountSet creates a new address set with an associated signer for sender
	// derivations.
	func newAccountSet(signer types.Signer) *accountSet {
		return &accountSet{
			accounts: make(map[common.Address]struct{}),
			signer:   signer,
		}
	}
	
	// contains checks if a given address is contained within the set.
	func (as *accountSet) contains(addr common.Address) bool {
		_, exist := as.accounts[addr]
		return exist
	}
	
	// containsTx checks if the sender of a given tx is within the set. If the sender
	// cannot be derived, this method returns false.
	// containsTx检查给定tx的发送者是否在集合内。 如果发件人无法被计算出，则此方法返回false。
	func (as *accountSet) containsTx(tx *types.Transaction) bool {
		if addr, err := types.Sender(as.signer, tx); err == nil {
			return as.contains(addr)
		}
		return false
	}
	
	// add inserts a new address into the set to track.
	func (as *accountSet) add(addr common.Address) {
		as.accounts[addr] = struct{}{}
	}


## txJournal

txJournal是交易的一个循环日志，其目的是存储本地创建的事务，以允许未执行的事务在节点重新启动后继续运行。
结构
	

	// txJournal is a rotating log of transactions with the aim of storing locally
	// created transactions to allow non-executed ones to survive node restarts.
	type txJournal struct {
		path   string         // Filesystem path to store the transactions at 用来存储交易的文件系统路径.
		writer io.WriteCloser // Output stream to write new transactions into 用来写入新交易的输出流.
	}

newTxJournal,用来创建新的交易日志.

	// newTxJournal creates a new transaction journal to
	func newTxJournal(path string) *txJournal {
		return &txJournal{
			path: path,
		}
	}

load方法从磁盘解析交易,然后调用add回调方法.	
	
	// load parses a transaction journal dump from disk, loading its contents into
	// the specified pool.
	func (journal *txJournal) load(add func(*types.Transaction) error) error {
		// Skip the parsing if the journal file doens't exist at all
		if _, err := os.Stat(journal.path); os.IsNotExist(err) {
			return nil
		}
		// Open the journal for loading any past transactions
		input, err := os.Open(journal.path)
		if err != nil {
			return err
		}
		defer input.Close()
	
		// Inject all transactions from the journal into the pool
		stream := rlp.NewStream(input, 0)
		total, dropped := 0, 0
	
		var failure error
		for {
			// Parse the next transaction and terminate on error
			tx := new(types.Transaction)
			if err = stream.Decode(tx); err != nil {
				if err != io.EOF {
					failure = err
				}
				break
			}
			// Import the transaction and bump the appropriate progress counters
			total++
			if err = add(tx); err != nil {
				log.Debug("Failed to add journaled transaction", "err", err)
				dropped++
				continue
			}
		}
		log.Info("Loaded local transaction journal", "transactions", total, "dropped", dropped)
	
		return failure
	}
insert方法,调用rlp.Encode写入writer
	
	// insert adds the specified transaction to the local disk journal.
	func (journal *txJournal) insert(tx *types.Transaction) error {
		if journal.writer == nil {
			return errNoActiveJournal
		}
		if err := rlp.Encode(journal.writer, tx); err != nil {
			return err
		}
		return nil
	}

rotate方法基于当前的交易池重新生成交易,

	// rotate regenerates the transaction journal based on the current contents of
	// the transaction pool.
	func (journal *txJournal) rotate(all map[common.Address]types.Transactions) error {
		// Close the current journal (if any is open)
		if journal.writer != nil {
			if err := journal.writer.Close(); err != nil {
				return err
			}
			journal.writer = nil
		}
		// Generate a new journal with the contents of the current pool
		replacement, err := os.OpenFile(journal.path+".new", os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0755)
		if err != nil {
			return err
		}
		journaled := 0
		for _, txs := range all {
			for _, tx := range txs {
				if err = rlp.Encode(replacement, tx); err != nil {
					replacement.Close()
					return err
				}
			}
			journaled += len(txs)
		}
		replacement.Close()
	
		// Replace the live journal with the newly generated one
		if err = os.Rename(journal.path+".new", journal.path); err != nil {
			return err
		}
		sink, err := os.OpenFile(journal.path, os.O_WRONLY|os.O_APPEND, 0755)
		if err != nil {
			return err
		}
		journal.writer = sink
		log.Info("Regenerated local transaction journal", "transactions", journaled, "accounts", len(all))
	
		return nil
	}

close

	// close flushes the transaction journal contents to disk and closes the file.
	func (journal *txJournal) close() error {
		var err error
	
		if journal.writer != nil {
			err = journal.writer.Close()
			journal.writer = nil
		}
		return err
	}
