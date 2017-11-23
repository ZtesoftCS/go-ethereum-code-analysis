genesis 是创世区块的意思. 一个区块链就是从同一个创世区块开始,通过规则形成的.不同的网络有不同的创世区块, 主网络和测试网路的创世区块是不同的.

这个模块根据传入的genesis的初始值和database，来设置genesis的状态，如果不存在创世区块，那么在database里面创建它。

数据结构
	
	// Genesis specifies the header fields, state of a genesis block. It also defines hard
	// fork switch-over blocks through the chain configuration.
	// Genesis指定header的字段，起始块的状态。 它还通过配置来定义硬叉切换块。
	type Genesis struct {
		Config     *params.ChainConfig `json:"config"`
		Nonce      uint64              `json:"nonce"`
		Timestamp  uint64              `json:"timestamp"`
		ExtraData  []byte              `json:"extraData"`
		GasLimit   uint64              `json:"gasLimit"   gencodec:"required"`
		Difficulty *big.Int            `json:"difficulty" gencodec:"required"`
		Mixhash    common.Hash         `json:"mixHash"`
		Coinbase   common.Address      `json:"coinbase"`
		Alloc      GenesisAlloc        `json:"alloc"      gencodec:"required"`
	
		// These fields are used for consensus tests. Please don't use them
		// in actual genesis blocks.
		Number     uint64      `json:"number"`
		GasUsed    uint64      `json:"gasUsed"`
		ParentHash common.Hash `json:"parentHash"`
	}
	
	// GenesisAlloc specifies the initial state that is part of the genesis block.
	// GenesisAlloc 指定了最开始的区块的初始状态.
	type GenesisAlloc map[common.Address]GenesisAccount


SetupGenesisBlock,
	
	// SetupGenesisBlock writes or updates the genesis block in db.
	// 
	// The block that will be used is:
	//
	//                          genesis == nil       genesis != nil
	//                       +------------------------------------------
	//     db has no genesis |  main-net default  |  genesis
	//     db has genesis    |  from DB           |  genesis (if compatible)
	//
	// The stored chain configuration will be updated if it is compatible (i.e. does not
	// specify a fork block below the local head block). In case of a conflict, the
	// error is a *params.ConfigCompatError and the new, unwritten config is returned.
	// 如果存储的区块链配置不兼容那么会被更新(). 为了避免发生冲突,会返回一个错误,并且新的配置和原来的配置会返回.
	// The returned chain configuration is never nil.

	// genesis 如果是 testnet dev 或者是 rinkeby 模式， 那么不为nil。如果是mainnet或者是私有链接。那么为空
	func SetupGenesisBlock(db ethdb.Database, genesis *Genesis) (*params.ChainConfig, common.Hash, error) {
		if genesis != nil && genesis.Config == nil {
			return params.AllProtocolChanges, common.Hash{}, errGenesisNoConfig
		}
	
		// Just commit the new block if there is no stored genesis block.
		stored := GetCanonicalHash(db, 0) //获取genesis对应的区块
		if (stored == common.Hash{}) { //如果没有区块 最开始启动geth会进入这里。
			if genesis == nil { 
				//如果genesis是nil 而且stored也是nil 那么使用主网络
				// 如果是test  dev  rinkeby 那么genesis不为空 会设置为各自的genesis
				log.Info("Writing default main-net genesis block")
				genesis = DefaultGenesisBlock()
			} else { // 否则使用配置的区块
				log.Info("Writing custom genesis block")
			}
			// 写入数据库
			block, err := genesis.Commit(db)
			return genesis.Config, block.Hash(), err
		}
	
		// Check whether the genesis block is already written.
		if genesis != nil { //如果genesis存在而且区块也存在 那么对比这两个区块是否相同
			block, _ := genesis.ToBlock()
			hash := block.Hash()
			if hash != stored {
				return genesis.Config, block.Hash(), &GenesisMismatchError{stored, hash}
			}
		}
	
		// Get the existing chain configuration.
		// 获取当前存在的区块链的genesis配置
		newcfg := genesis.configOrDefault(stored)
		// 获取当前的区块链的配置
		storedcfg, err := GetChainConfig(db, stored)
		if err != nil {
			if err == ErrChainConfigNotFound {
				// This case happens if a genesis write was interrupted.
				log.Warn("Found genesis block without chain config")
				err = WriteChainConfig(db, stored, newcfg)
			}
			return newcfg, stored, err
		}
		// Special case: don't change the existing config of a non-mainnet chain if no new
		// config is supplied. These chains would get AllProtocolChanges (and a compat error)
		// if we just continued here.
		// 特殊情况：如果没有提供新的配置，请不要更改非主网链的现有配置。 
		// 如果我们继续这里，这些链会得到AllProtocolChanges（和compat错误）。
		if genesis == nil && stored != params.MainnetGenesisHash {
			return storedcfg, stored, nil   // 如果是私有链接会从这里退出。
		}
	
		// Check config compatibility and write the config. Compatibility errors
		// are returned to the caller unless we're already at block zero.
		// 检查配置的兼容性,除非我们在区块0,否则返回兼容性错误.
		height := GetBlockNumber(db, GetHeadHeaderHash(db))
		if height == missingNumber {
			return newcfg, stored, fmt.Errorf("missing block number for head header hash")
		}
		compatErr := storedcfg.CheckCompatible(newcfg, height)
		// 如果区块已经写入数据了,那么就不能更改genesis配置了
		if compatErr != nil && height != 0 && compatErr.RewindTo != 0 {
			return newcfg, stored, compatErr
		}
		// 如果是主网络会从这里退出。
		return newcfg, stored, WriteChainConfig(db, stored, newcfg)
	}


ToBlock, 这个方法使用genesis的数据，使用基于内存的数据库，然后创建了一个block并返回。
	
	
	// ToBlock creates the block and state of a genesis specification.
	func (g *Genesis) ToBlock() (*types.Block, *state.StateDB) {
		db, _ := ethdb.NewMemDatabase()
		statedb, _ := state.New(common.Hash{}, state.NewDatabase(db))
		for addr, account := range g.Alloc {
			statedb.AddBalance(addr, account.Balance)
			statedb.SetCode(addr, account.Code)
			statedb.SetNonce(addr, account.Nonce)
			for key, value := range account.Storage {
				statedb.SetState(addr, key, value)
			}
		}
		root := statedb.IntermediateRoot(false)
		head := &types.Header{
			Number:     new(big.Int).SetUint64(g.Number),
			Nonce:      types.EncodeNonce(g.Nonce),
			Time:       new(big.Int).SetUint64(g.Timestamp),
			ParentHash: g.ParentHash,
			Extra:      g.ExtraData,
			GasLimit:   new(big.Int).SetUint64(g.GasLimit),
			GasUsed:    new(big.Int).SetUint64(g.GasUsed),
			Difficulty: g.Difficulty,
			MixDigest:  g.Mixhash,
			Coinbase:   g.Coinbase,
			Root:       root,
		}
		if g.GasLimit == 0 {
			head.GasLimit = params.GenesisGasLimit
		}
		if g.Difficulty == nil {
			head.Difficulty = params.GenesisDifficulty
		}
		return types.NewBlock(head, nil, nil, nil), statedb
	}

Commit方法和MustCommit方法, Commit方法把给定的genesis的block和state写入数据库， 这个block被认为是规范的区块链头。
	
	// Commit writes the block and state of a genesis specification to the database.
	// The block is committed as the canonical head block.
	func (g *Genesis) Commit(db ethdb.Database) (*types.Block, error) {
		block, statedb := g.ToBlock()
		if block.Number().Sign() != 0 {
			return nil, fmt.Errorf("can't commit genesis block with number > 0")
		}
		if _, err := statedb.CommitTo(db, false); err != nil {
			return nil, fmt.Errorf("cannot write state: %v", err)
		}
		// 写入总难度
		if err := WriteTd(db, block.Hash(), block.NumberU64(), g.Difficulty); err != nil {
			return nil, err
		}
		// 写入区块
		if err := WriteBlock(db, block); err != nil {
			return nil, err
		}
		// 写入区块收据
		if err := WriteBlockReceipts(db, block.Hash(), block.NumberU64(), nil); err != nil {
			return nil, err
		}
		// 写入   headerPrefix + num (uint64 big endian) + numSuffix -> hash
		if err := WriteCanonicalHash(db, block.Hash(), block.NumberU64()); err != nil {
			return nil, err
		}
		// 写入  "LastBlock" -> hash
		if err := WriteHeadBlockHash(db, block.Hash()); err != nil {
			return nil, err
		}
		// 写入 "LastHeader" -> hash
		if err := WriteHeadHeaderHash(db, block.Hash()); err != nil {
			return nil, err
		}
		config := g.Config
		if config == nil {
			config = params.AllProtocolChanges
		}
		// 写入 ethereum-config-hash -> config
		return block, WriteChainConfig(db, block.Hash(), config)
	}
	
	// MustCommit writes the genesis block and state to db, panicking on error.
	// The block is committed as the canonical head block.
	func (g *Genesis) MustCommit(db ethdb.Database) *types.Block {
		block, err := g.Commit(db)
		if err != nil {
			panic(err)
		}
		return block
	}

返回各种模式的默认Genesis
	
	// DefaultGenesisBlock returns the Ethereum main net genesis block.
	func DefaultGenesisBlock() *Genesis {
		return &Genesis{
			Config:     params.MainnetChainConfig,
			Nonce:      66,
			ExtraData:  hexutil.MustDecode("0x11bbe8db4e347b4e8c937c1c8370e4b5ed33adb3db69cbdb7a38e1e50b1b82fa"),
			GasLimit:   5000,
			Difficulty: big.NewInt(17179869184),
			Alloc:      decodePrealloc(mainnetAllocData),
		}
	}
	
	// DefaultTestnetGenesisBlock returns the Ropsten network genesis block.
	func DefaultTestnetGenesisBlock() *Genesis {
		return &Genesis{
			Config:     params.TestnetChainConfig,
			Nonce:      66,
			ExtraData:  hexutil.MustDecode("0x3535353535353535353535353535353535353535353535353535353535353535"),
			GasLimit:   16777216,
			Difficulty: big.NewInt(1048576),
			Alloc:      decodePrealloc(testnetAllocData),
		}
	}
	
	// DefaultRinkebyGenesisBlock returns the Rinkeby network genesis block.
	func DefaultRinkebyGenesisBlock() *Genesis {
		return &Genesis{
			Config:     params.RinkebyChainConfig,
			Timestamp:  1492009146,
			ExtraData:  hexutil.MustDecode("0x52657370656374206d7920617574686f7269746168207e452e436172746d616e42eb768f2244c8811c63729a21a3569731535f067ffc57839b00206d1ad20c69a1981b489f772031b279182d99e65703f0076e4812653aab85fca0f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
			GasLimit:   4700000,
			Difficulty: big.NewInt(1),
			Alloc:      decodePrealloc(rinkebyAllocData),
		}
	}
	
	// DevGenesisBlock returns the 'geth --dev' genesis block.
	func DevGenesisBlock() *Genesis {
		return &Genesis{
			Config:     params.AllProtocolChanges,
			Nonce:      42,
			GasLimit:   4712388,
			Difficulty: big.NewInt(131072),
			Alloc:      decodePrealloc(devAllocData),
		}
	}
