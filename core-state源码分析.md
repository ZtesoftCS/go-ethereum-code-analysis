core/state 包主要为以太坊的state trie提供了一层缓存层(cache)

state的结构主要如下图

![image](picture/state_1.png)

蓝色的矩形代表本模块， 灰色的矩形代表外部模块。

- database主要提供了trie树的抽象，提供trie树的缓存和合约代码长度的缓存。
- journal主要提供了操作日志，以及操作回滚的功能。 
- state_object是account对象的抽象，提供了账户的一些功能。 
- statedb主要是提供了state trie的部分功能。

## database.go
database.go 提供了一个数据库的抽象。

数据结构
	
	// Database wraps access to tries and contract code.
	type Database interface {
		// Accessing tries:
		// OpenTrie opens the main account trie.
		// OpenStorageTrie opens the storage trie of an account.
		// OpenTrie 打开了主账号的trie树
		// OpenStorageTrie 打开了一个账号的storage trie
		OpenTrie(root common.Hash) (Trie, error)
		OpenStorageTrie(addrHash, root common.Hash) (Trie, error)
		// Accessing contract code:
		// 访问合约代码
		ContractCode(addrHash, codeHash common.Hash) ([]byte, error)
		// 访问合约的大小。 这个方法可能经常被调用。因为有缓存。
		ContractCodeSize(addrHash, codeHash common.Hash) (int, error)
		// CopyTrie returns an independent copy of the given trie.
		// CopyTrie 返回了一个指定trie的独立的copy
		CopyTrie(Trie) Trie
	}
	
	// NewDatabase creates a backing store for state. The returned database is safe for
	// concurrent use and retains cached trie nodes in memory.
	func NewDatabase(db ethdb.Database) Database {
		csc, _ := lru.New(codeSizeCacheSize)
		return &cachingDB{db: db, codeSizeCache: csc}
	}
	
	type cachingDB struct {
		db            ethdb.Database
		mu            sync.Mutex
		pastTries     []*trie.SecureTrie  //trie树的缓存
		codeSizeCache *lru.Cache		  //合约代码大小的缓存
	}



OpenTrie，从缓存里面查找。如果找到了返回缓存的trie的copy， 否则重新构建一颗树返回。

	
	func (db *cachingDB) OpenTrie(root common.Hash) (Trie, error) {
		db.mu.Lock()
		defer db.mu.Unlock()
	
		for i := len(db.pastTries) - 1; i >= 0; i-- {
			if db.pastTries[i].Hash() == root {
				return cachedTrie{db.pastTries[i].Copy(), db}, nil
			}
		}
		tr, err := trie.NewSecure(root, db.db, MaxTrieCacheGen)
		if err != nil {
			return nil, err
		}
		return cachedTrie{tr, db}, nil
	}

	func (db *cachingDB) OpenStorageTrie(addrHash, root common.Hash) (Trie, error) {
		return trie.NewSecure(root, db.db, 0)
	}


ContractCode 和 ContractCodeSize, ContractCodeSize有缓存。

	
	func (db *cachingDB) ContractCode(addrHash, codeHash common.Hash) ([]byte, error) {
		code, err := db.db.Get(codeHash[:])
		if err == nil {
			db.codeSizeCache.Add(codeHash, len(code))
		}
		return code, err
	}
	
	func (db *cachingDB) ContractCodeSize(addrHash, codeHash common.Hash) (int, error) {
		if cached, ok := db.codeSizeCache.Get(codeHash); ok {
			return cached.(int), nil
		}
		code, err := db.ContractCode(addrHash, codeHash)
		if err == nil {
			db.codeSizeCache.Add(codeHash, len(code))
		}
		return len(code), err
	}

cachedTrie的结构和commit方法，commit的时候会调用pushTrie方法把之前的Trie树缓存起来。

	// cachedTrie inserts its trie into a cachingDB on commit.
	type cachedTrie struct {
		*trie.SecureTrie
		db *cachingDB
	}
	
	func (m cachedTrie) CommitTo(dbw trie.DatabaseWriter) (common.Hash, error) {
		root, err := m.SecureTrie.CommitTo(dbw)
		if err == nil {
			m.db.pushTrie(m.SecureTrie)
		}
		return root, err
	}
	func (db *cachingDB) pushTrie(t *trie.SecureTrie) {
		db.mu.Lock()
		defer db.mu.Unlock()
	
		if len(db.pastTries) >= maxPastTries {
			copy(db.pastTries, db.pastTries[1:])
			db.pastTries[len(db.pastTries)-1] = t
		} else {
			db.pastTries = append(db.pastTries, t)
		}
	}


## journal.go
journal代表了操作日志， 并针对各种操作的日志提供了对应的回滚功能。 可以基于这个日志来做一些事务类型的操作。

类型定义，定义了journalEntry这个接口，提供了undo的功能。 journal 就是journalEntry的列表。

	type journalEntry interface {
		undo(*StateDB)
	}
	
	type journal []journalEntry
	

各种不同的日志类型以及undo方法。

	createObjectChange struct {  //创建对象的日志。 undo方法就是从StateDB中删除创建的对象。
		account *common.Address
	}
	func (ch createObjectChange) undo(s *StateDB) {
		delete(s.stateObjects, *ch.account)
		delete(s.stateObjectsDirty, *ch.account)
	}
	// 对于stateObject的修改， undo方法就是把值改为原来的对象。
	resetObjectChange struct {
		prev *stateObject
	}
	func (ch resetObjectChange) undo(s *StateDB) {
		s.setStateObject(ch.prev)
	}
	// 自杀的更改。自杀应该是删除账号，但是如果没有commit的化，对象还没有从stateDB删除。
	suicideChange struct {
		account     *common.Address
		prev        bool // whether account had already suicided
		prevbalance *big.Int
	}
	func (ch suicideChange) undo(s *StateDB) {
		obj := s.getStateObject(*ch.account)
		if obj != nil {
			obj.suicided = ch.prev
			obj.setBalance(ch.prevbalance)
		}
	}

	// Changes to individual accounts.
	balanceChange struct {
		account *common.Address
		prev    *big.Int
	}
	nonceChange struct {
		account *common.Address
		prev    uint64
	}
	storageChange struct {
		account       *common.Address
		key, prevalue common.Hash
	}
	codeChange struct {
		account            *common.Address
		prevcode, prevhash []byte
	}
	
	func (ch balanceChange) undo(s *StateDB) {
		s.getStateObject(*ch.account).setBalance(ch.prev)
	}
	func (ch nonceChange) undo(s *StateDB) {
		s.getStateObject(*ch.account).setNonce(ch.prev)
	}
	func (ch codeChange) undo(s *StateDB) {
		s.getStateObject(*ch.account).setCode(common.BytesToHash(ch.prevhash), ch.prevcode)
	}
	func (ch storageChange) undo(s *StateDB) {
		s.getStateObject(*ch.account).setState(ch.key, ch.prevalue)
	}

	// 我理解是DAO事件的退款处理
	refundChange struct {
		prev *big.Int
	}
	func (ch refundChange) undo(s *StateDB) {
		s.refund = ch.prev
	}
	// 增加了日志的修改
	addLogChange struct {
		txhash common.Hash
	}
	func (ch addLogChange) undo(s *StateDB) {
		logs := s.logs[ch.txhash]
		if len(logs) == 1 {
			delete(s.logs, ch.txhash)
		} else {
			s.logs[ch.txhash] = logs[:len(logs)-1]
		}
		s.logSize--
	}
	// 这个是增加 VM看到的 SHA3的 原始byte[], 增加SHA3 hash -> byte[] 的对应关系
	addPreimageChange struct {
		hash common.Hash
	}
	func (ch addPreimageChange) undo(s *StateDB) {
		delete(s.preimages, ch.hash)
	}

	touchChange struct {
		account   *common.Address
		prev      bool
		prevDirty bool
	}
	var ripemd = common.HexToAddress("0000000000000000000000000000000000000003")
	func (ch touchChange) undo(s *StateDB) {
		if !ch.prev && *ch.account != ripemd {
			s.getStateObject(*ch.account).touched = ch.prev
			if !ch.prevDirty {
				delete(s.stateObjectsDirty, *ch.account)
			}
		}
	}



## state_object.go
stateObject表示正在修改的以太坊帐户。

数据结构


	type Storage map[common.Hash]common.Hash
	
	// stateObject represents an Ethereum account which is being modified.
	// stateObject表示正在修改的以太坊帐户。
	// The usage pattern is as follows:
	// First you need to obtain a state object.
	// Account values can be accessed and modified through the object.
	// Finally, call CommitTrie to write the modified storage trie into a database.

	使用模式如下：
	首先你需要获得一个state_object。
	帐户值可以通过对象访问和修改。
	最后，调用CommitTrie将修改后的存储trie写入数据库。

	type stateObject struct {
		address  common.Address
		addrHash common.Hash // hash of ethereum address of the account 以太坊账号地址的hash值
		data     Account  // 这个是实际的以太坊账号的信息
		db       *StateDB //状态数据库
	
		// DB error.
		// State objects are used by the consensus core and VM which are
		// unable to deal with database-level errors. Any error that occurs
		// during a database read is memoized here and will eventually be returned
		// by StateDB.Commit.
		// 
		数据库错误。
		stateObject会被共识算法的核心和VM使用，在这些代码内部无法处理数据库级别的错误。 
		在数据库读取期间发生的任何错误都会在这里被存储，最终将由StateDB.Commit返回。
		dbErr error
	
		// Write caches.  写缓存
		trie Trie // storage trie, which becomes non-nil on first access 用户的存储trie ，在第一次访问的时候变得非空
		code Code // contract bytecode, which gets set when code is loaded 合约代码，当代码被加载的时候被设置
	
		cachedStorage Storage // Storage entry cache to avoid duplicate reads 用户存储对象的缓存，用来避免重复读
		dirtyStorage  Storage // Storage entries that need to be flushed to disk 需要刷入磁盘的用户存储对象
	
		// Cache flags.  Cache 标志
		// When an object is marked suicided it will be delete from the trie
		// during the "update" phase of the state transition.
		// 当一个对象被标记为自杀时，它将在状态转换的“更新”阶段期间从树中删除。
		dirtyCode bool // true if the code was updated 如果代码被更新，会设置为true
		suicided  bool
		touched   bool
		deleted   bool
		onDirty   func(addr common.Address) // Callback method to mark a state object newly dirty  第一次被设置为drity的时候会被调用。
	}

	// Account is the Ethereum consensus representation of accounts.
	// These objects are stored in the main account trie.
	// 帐户是以太坊共识表示的帐户。 这些对象存储在main account trie。
	type Account struct {
		Nonce    uint64
		Balance  *big.Int
		Root     common.Hash // merkle root of the storage trie
		CodeHash []byte
	}

构造函数

	// newObject creates a state object.
	func newObject(db *StateDB, address common.Address, data Account, onDirty func(addr common.Address)) *stateObject {
		if data.Balance == nil {
			data.Balance = new(big.Int)
		}
		if data.CodeHash == nil {
			data.CodeHash = emptyCodeHash
		}
		return &stateObject{
			db:            db,
			address:       address,
			addrHash:      crypto.Keccak256Hash(address[:]),
			data:          data,
			cachedStorage: make(Storage),
			dirtyStorage:  make(Storage),
			onDirty:       onDirty,
		}
	}


RLP的编码方式，只会编码 Account对象。

	// EncodeRLP implements rlp.Encoder.
	func (c *stateObject) EncodeRLP(w io.Writer) error {
		return rlp.Encode(w, c.data)
	}

一些状态改变的函数。
	
	func (self *stateObject) markSuicided() {
		self.suicided = true
		if self.onDirty != nil {
			self.onDirty(self.Address())
			self.onDirty = nil
		}
	}

	func (c *stateObject) touch() {
		c.db.journal = append(c.db.journal, touchChange{
			account:   &c.address,
			prev:      c.touched,
			prevDirty: c.onDirty == nil,
		})
		if c.onDirty != nil {
			c.onDirty(c.Address())
			c.onDirty = nil
		}
		c.touched = true
	}
	

Storage的处理

	// getTrie返回账户的Storage Trie
	func (c *stateObject) getTrie(db Database) Trie {
		if c.trie == nil {
			var err error
			c.trie, err = db.OpenStorageTrie(c.addrHash, c.data.Root)
			if err != nil {
				c.trie, _ = db.OpenStorageTrie(c.addrHash, common.Hash{})
				c.setError(fmt.Errorf("can't create storage trie: %v", err))
			}
		}
		return c.trie
	}
	
	// GetState returns a value in account storage.
	// GetState 返回account storage 的一个值，这个值的类型是Hash类型。
	// 说明account storage里面只能存储hash值？
	// 如果缓存里面存在就从缓存里查找，否则从数据库里面查询。然后存储到缓存里面。
	func (self *stateObject) GetState(db Database, key common.Hash) common.Hash {
		value, exists := self.cachedStorage[key]
		if exists {
			return value
		}
		// Load from DB in case it is missing.
		enc, err := self.getTrie(db).TryGet(key[:])
		if err != nil {
			self.setError(err)
			return common.Hash{}
		}
		if len(enc) > 0 {
			_, content, _, err := rlp.Split(enc)
			if err != nil {
				self.setError(err)
			}
			value.SetBytes(content)
		}
		if (value != common.Hash{}) {
			self.cachedStorage[key] = value
		}
		return value
	}
	
	// SetState updates a value in account storage.
	// 往 account storeage 里面设置一个值 key value 的类型都是Hash类型。
	func (self *stateObject) SetState(db Database, key, value common.Hash) {
		self.db.journal = append(self.db.journal, storageChange{
			account:  &self.address,
			key:      key,
			prevalue: self.GetState(db, key),
		})
		self.setState(key, value)
	}
	
	func (self *stateObject) setState(key, value common.Hash) {
		self.cachedStorage[key] = value
		self.dirtyStorage[key] = value
	
		if self.onDirty != nil {
			self.onDirty(self.Address())
			self.onDirty = nil
		}
	}


提交 Commit

	// CommitTrie the storage trie of the object to dwb.
	// This updates the trie root.
	// 步骤，首先打开，然后修改，然后提交或者回滚
	func (self *stateObject) CommitTrie(db Database, dbw trie.DatabaseWriter) error {
		self.updateTrie(db) // updateTrie把修改过的缓存写入Trie树
		if self.dbErr != nil {
			return self.dbErr
		}
		root, err := self.trie.CommitTo(dbw)
		if err == nil {
			self.data.Root = root
		}
		return err
	}

	// updateTrie writes cached storage modifications into the object's storage trie.
	func (self *stateObject) updateTrie(db Database) Trie {
		tr := self.getTrie(db)
		for key, value := range self.dirtyStorage {
			delete(self.dirtyStorage, key)
			if (value == common.Hash{}) {
				self.setError(tr.TryDelete(key[:]))
				continue
			}
			// Encoding []byte cannot fail, ok to ignore the error.
			v, _ := rlp.EncodeToBytes(bytes.TrimLeft(value[:], "\x00"))
			self.setError(tr.TryUpdate(key[:], v))
		}
		return tr
	}
	
	// UpdateRoot sets the trie root to the current root hash of
	// 把账号的root设置为当前的trie树的跟。
	func (self *stateObject) updateRoot(db Database) {
		self.updateTrie(db)
		self.data.Root = self.trie.Hash()
	}
	

额外的一些功能 ，deepCopy提供了state_object的深拷贝。
	
	
	func (self *stateObject) deepCopy(db *StateDB, onDirty func(addr common.Address)) *stateObject {
		stateObject := newObject(db, self.address, self.data, onDirty)
		if self.trie != nil {
			stateObject.trie = db.db.CopyTrie(self.trie)
		}
		stateObject.code = self.code
		stateObject.dirtyStorage = self.dirtyStorage.Copy()
		stateObject.cachedStorage = self.dirtyStorage.Copy()
		stateObject.suicided = self.suicided
		stateObject.dirtyCode = self.dirtyCode
		stateObject.deleted = self.deleted
		return stateObject
	}


## statedb.go

stateDB用来存储以太坊中关于merkle trie的所有内容。 StateDB负责缓存和存储嵌套状态。 这是检索合约和账户的一般查询界面：

数据结构

	type StateDB struct {
		db   Database  // 后端的数据库
		trie Trie	   // trie树 main account trie
	
		// This map holds 'live' objects, which will get modified while processing a state transition.
		// 下面的Map用来存储当前活动的对象，这些对象在状态转换的时候会被修改。
		// stateObjects 用来缓存对象
		// stateObjectsDirty用来缓存被修改过的对象。
		stateObjects      map[common.Address]*stateObject
		stateObjectsDirty map[common.Address]struct{}
	
		// DB error.
		// State objects are used by the consensus core and VM which are
		// unable to deal with database-level errors. Any error that occurs
		// during a database read is memoized here and will eventually be returned
		// by StateDB.Commit.
		dbErr error
	
		// The refund counter, also used by state transitioning.
		// refund计数器。 暂时还不清楚功能。
		refund *big.Int
	
		thash, bhash common.Hash  //当前的transaction hash 和block hash 
		txIndex      int		  // 当前的交易的index
		logs         map[common.Hash][]*types.Log // 日志 key是交易的hash值
		logSize      uint
	
		preimages map[common.Hash][]byte  // EVM计算的 SHA3->byte[]的映射关系
	
		// Journal of state modifications. This is the backbone of
		// Snapshot and RevertToSnapshot.
		// 状态修改日志。 这是Snapshot和RevertToSnapshot的支柱。
		journal        journal
		validRevisions []revision
		nextRevisionId int
	
		lock sync.Mutex
	}


构造函数

	// 一般的用法 statedb, _ := state.New(common.Hash{}, state.NewDatabase(db))
	
	// Create a new state from a given trie
	func New(root common.Hash, db Database) (*StateDB, error) {
		tr, err := db.OpenTrie(root)
		if err != nil {
			return nil, err
		}
		return &StateDB{
			db:                db,
			trie:              tr,
			stateObjects:      make(map[common.Address]*stateObject),
			stateObjectsDirty: make(map[common.Address]struct{}),
			refund:            new(big.Int),
			logs:              make(map[common.Hash][]*types.Log),
			preimages:         make(map[common.Hash][]byte),
		}, nil
	}

### 对于Log的处理
state提供了Log的处理，这比较意外，因为Log实际上是存储在区块链中的，并没有存储在state trie中, state提供Log的处理， 使用了基于下面的几个函数。  奇怪的是暂时没看到如何删除logs里面的信息，如果不删除的话，应该会越积累越多。 TODO logs 删除

Prepare函数，在交易执行开始被执行。

AddLog函数，在交易执行过程中被VM执行。添加日志。同时把日志和交易关联起来，添加部分交易的信息。

GetLogs函数，交易完成取走。


	// Prepare sets the current transaction hash and index and block hash which is
	// used when the EVM emits new state logs.
	func (self *StateDB) Prepare(thash, bhash common.Hash, ti int) {
		self.thash = thash
		self.bhash = bhash
		self.txIndex = ti
	}
	
	func (self *StateDB) AddLog(log *types.Log) {
		self.journal = append(self.journal, addLogChange{txhash: self.thash})
	
		log.TxHash = self.thash
		log.BlockHash = self.bhash
		log.TxIndex = uint(self.txIndex)
		log.Index = self.logSize
		self.logs[self.thash] = append(self.logs[self.thash], log)
		self.logSize++
	}
	func (self *StateDB) GetLogs(hash common.Hash) []*types.Log {
		return self.logs[hash]
	}
	
	func (self *StateDB) Logs() []*types.Log {
		var logs []*types.Log
		for _, lgs := range self.logs {
			logs = append(logs, lgs...)
		}
		return logs
	}


### stateObject处理
getStateObject,首先从缓存里面获取，如果没有就从trie树里面获取，并加载到缓存。
	
	// Retrieve a state object given my the address. Returns nil if not found.
	func (self *StateDB) getStateObject(addr common.Address) (stateObject *stateObject) {
		// Prefer 'live' objects.
		if obj := self.stateObjects[addr]; obj != nil {
			if obj.deleted {
				return nil
			}
			return obj
		}
	
		// Load the object from the database.
		enc, err := self.trie.TryGet(addr[:])
		if len(enc) == 0 {
			self.setError(err)
			return nil
		}
		var data Account
		if err := rlp.DecodeBytes(enc, &data); err != nil {
			log.Error("Failed to decode state object", "addr", addr, "err", err)
			return nil
		}
		// Insert into the live set.
		obj := newObject(self, addr, data, self.MarkStateObjectDirty)
		self.setStateObject(obj)
		return obj
	}

MarkStateObjectDirty， 设置一个stateObject为Dirty。 直接往stateObjectDirty对应的地址插入一个空结构体。

	// MarkStateObjectDirty adds the specified object to the dirty map to avoid costly
	// state object cache iteration to find a handful of modified ones.
	func (self *StateDB) MarkStateObjectDirty(addr common.Address) {
		self.stateObjectsDirty[addr] = struct{}{}
	}


### 快照和回滚功能
Snapshot可以创建一个快照， 然后通过	RevertToSnapshot可以回滚到哪个状态，这个功能是通过journal来做到的。 每一步的修改都会往journal里面添加一个undo日志。 如果需要回滚只需要执行undo日志就行了。
	
	// Snapshot returns an identifier for the current revision of the state.
	func (self *StateDB) Snapshot() int {
		id := self.nextRevisionId
		self.nextRevisionId++
		self.validRevisions = append(self.validRevisions, revision{id, len(self.journal)})
		return id
	}
	
	// RevertToSnapshot reverts all state changes made since the given revision.
	func (self *StateDB) RevertToSnapshot(revid int) {
		// Find the snapshot in the stack of valid snapshots.
		idx := sort.Search(len(self.validRevisions), func(i int) bool {
			return self.validRevisions[i].id >= revid
		})
		if idx == len(self.validRevisions) || self.validRevisions[idx].id != revid {
			panic(fmt.Errorf("revision id %v cannot be reverted", revid))
		}
		snapshot := self.validRevisions[idx].journalIndex
	
		// Replay the journal to undo changes.
		for i := len(self.journal) - 1; i >= snapshot; i-- {
			self.journal[i].undo(self)
		}
		self.journal = self.journal[:snapshot]
	
		// Remove invalidated snapshots from the stack.
		self.validRevisions = self.validRevisions[:idx]
	}

### 获取中间状态的 root hash值
IntermediateRoot 用来计算当前的state trie的root的hash值。这个方法会在交易执行的过程中被调用。会被存入 transaction receipt

Finalise方法会调用update方法把存放在cache层的修改写入到trie数据库里面。 但是这个时候还没有写入底层的数据库。 还没有调用commit，数据还在内存里面，还没有落地成文件。
	
	// Finalise finalises the state by removing the self destructed objects
	// and clears the journal as well as the refunds.
	func (s *StateDB) Finalise(deleteEmptyObjects bool) {
		for addr := range s.stateObjectsDirty {
			stateObject := s.stateObjects[addr]
			if stateObject.suicided || (deleteEmptyObjects && stateObject.empty()) {
				s.deleteStateObject(stateObject)
			} else {
				stateObject.updateRoot(s.db)
				s.updateStateObject(stateObject)
			}
		}
		// Invalidate journal because reverting across transactions is not allowed.
		s.clearJournalAndRefund()
	}
	
	// IntermediateRoot computes the current root hash of the state trie.
	// It is called in between transactions to get the root hash that
	// goes into transaction receipts.
	func (s *StateDB) IntermediateRoot(deleteEmptyObjects bool) common.Hash {
		s.Finalise(deleteEmptyObjects)
		return s.trie.Hash()
	}

### commit方法
CommitTo用来提交更改。
	
	// CommitTo writes the state to the given database.
	func (s *StateDB) CommitTo(dbw trie.DatabaseWriter, deleteEmptyObjects bool) (root common.Hash, err error) {
		defer s.clearJournalAndRefund()
	
		// Commit objects to the trie.
		for addr, stateObject := range s.stateObjects {
			_, isDirty := s.stateObjectsDirty[addr]
			switch {
			case stateObject.suicided || (isDirty && deleteEmptyObjects && stateObject.empty()):
				// If the object has been removed, don't bother syncing it
				// and just mark it for deletion in the trie.
				s.deleteStateObject(stateObject)
			case isDirty:
				// Write any contract code associated with the state object
				if stateObject.code != nil && stateObject.dirtyCode {
					if err := dbw.Put(stateObject.CodeHash(), stateObject.code); err != nil {
						return common.Hash{}, err
					}
					stateObject.dirtyCode = false
				}
				// Write any storage changes in the state object to its storage trie.
				if err := stateObject.CommitTrie(s.db, dbw); err != nil {
					return common.Hash{}, err
				}
				// Update the object in the main account trie.
				s.updateStateObject(stateObject)
			}
			delete(s.stateObjectsDirty, addr)
		}
		// Write trie changes.
		root, err = s.trie.CommitTo(dbw)
		log.Debug("Trie cache stats after commit", "misses", trie.CacheMisses(), "unloads", trie.CacheUnloads())
		return root, err
	}



### 总结
state包提供了用户和合约的状态管理的功能。 管理了状态和合约的各种状态转换。 cache， trie， 数据库。  日志和回滚功能。

