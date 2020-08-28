##### eth的共识算法pow调用栈详解


###### 核心的逻辑需要从/eth/handler.go/NewProtocolManager方法下开始,关键代码:
```
manager.downloader = downloader.New(mode, chaindb, manager.eventMux, blockchain, nil, manager.removePeer)

	validator := func(header *types.Header) error {
		return engine.VerifyHeader(blockchain, header, true)
	}
	heighter := func() uint64 {
		return blockchain.CurrentBlock().NumberU64()
	}
	inserter := func(blocks types.Blocks) (int, error) {
		// If fast sync is running, deny importing weird blocks
		if atomic.LoadUint32(&manager.fastSync) == 1 {
			log.Warn("Discarded bad propagated block", "number", blocks[0].Number(), "hash", blocks[0].Hash())
			return 0, nil
		}
		atomic.StoreUint32(&manager.acceptTxs, 1) // Mark initial sync done on any fetcher import
		return manager.blockchain.InsertChain(blocks)
	}
	manager.fetcher = fetcher.New(blockchain.GetBlockByHash, validator, manager.BroadcastBlock, heighter, inserter, manager.removePeer)

	return manager, nil
```

###### 该方法中生成了一个校验区块头部的对象`validator`
###### 让我们继续跟进`engine.VerifyHeader(blockchain, header, true)`方法:

```
// VerifyHeader checks whether a header conforms to the consensus rules of the
// stock Ethereum ethash engine.
func (ethash *Ethash) VerifyHeader(chain consensus.ChainReader, header *types.Header, seal bool) error {
	// If we're running a full engine faking, accept any input as valid
	if ethash.fakeFull {
		return nil
	}
	// Short circuit if the header is known, or it's parent not
	number := header.Number.Uint64()
	if chain.GetHeader(header.Hash(), number) != nil {
		return nil
	}
	parent := chain.GetHeader(header.ParentHash, number-1)
	if parent == nil {
		return consensus.ErrUnknownAncestor
	}
	// Sanity checks passed, do a proper verification
	return ethash.verifyHeader(chain, header, parent, false, seal)
}

```

###### 首先看第一个if,它的逻辑判断是如果为true,那么就关闭所有的共识规则校验,紧跟着两个if判断是只要该block的header的hash和number或者上一个header的hash和number存在链上,那么它header的共识规则校验就通过,如果都不通过,那么该区块校验失败跑出错误.如果走到最后一个return,那么就需要做一些其他额外验证

```
// verifyHeader checks whether a header conforms to the consensus rules of the
// stock Ethereum ethash engine.
// See YP section 4.3.4. "Block Header Validity"
func (ethash *Ethash) verifyHeader(chain consensus.ChainReader, header, parent *types.Header, uncle bool, seal bool) error {
	// Ensure that the header's extra-data section is of a reasonable size
	if uint64(len(header.Extra)) > params.MaximumExtraDataSize {
		return fmt.Errorf("extra-data too long: %d > %d", len(header.Extra), params.MaximumExtraDataSize)
	}
	// Verify the header's timestamp
	if uncle {
		if header.Time.Cmp(math.MaxBig256) > 0 {
			return errLargeBlockTime
		}
	} else {
		if header.Time.Cmp(big.NewInt(time.Now().Unix())) > 0 {
			return consensus.ErrFutureBlock
		}
	}
	if header.Time.Cmp(parent.Time) <= 0 {
		return errZeroBlockTime
	}
	// Verify the block's difficulty based in it's timestamp and parent's difficulty
	expected := CalcDifficulty(chain.Config(), header.Time.Uint64(), parent)
	if expected.Cmp(header.Difficulty) != 0 {
		return fmt.Errorf("invalid difficulty: have %v, want %v", header.Difficulty, expected)
	}
	// Verify that the gas limit is <= 2^63-1
	if header.GasLimit.Cmp(math.MaxBig63) > 0 {
		return fmt.Errorf("invalid gasLimit: have %v, max %v", header.GasLimit, math.MaxBig63)
	}
	// Verify that the gasUsed is <= gasLimit
	if header.GasUsed.Cmp(header.GasLimit) > 0 {
		return fmt.Errorf("invalid gasUsed: have %v, gasLimit %v", header.GasUsed, header.GasLimit)
	}

	// Verify that the gas limit remains within allowed bounds
	diff := new(big.Int).Set(parent.GasLimit)
	diff = diff.Sub(diff, header.GasLimit)
	diff.Abs(diff)

	limit := new(big.Int).Set(parent.GasLimit)
	limit = limit.Div(limit, params.GasLimitBoundDivisor)

	if diff.Cmp(limit) >= 0 || header.GasLimit.Cmp(params.MinGasLimit) < 0 {
		return fmt.Errorf("invalid gas limit: have %v, want %v += %v", header.GasLimit, parent.GasLimit, limit)
	}
	// Verify that the block number is parent's +1
	if diff := new(big.Int).Sub(header.Number, parent.Number); diff.Cmp(big.NewInt(1)) != 0 {
		return consensus.ErrInvalidNumber
	}
	// Verify the engine specific seal securing the block
	if seal {
		if err := ethash.VerifySeal(chain, header); err != nil {
			return err
		}
	}
	// If all checks passed, validate any special fields for hard forks
	if err := misc.VerifyDAOHeaderExtraData(chain.Config(), header); err != nil {
		return err
	}
	if err := misc.VerifyForkHashes(chain.Config(), header, uncle); err != nil {
		return err
	}
	return nil
}

```
###### 该方法会去校验该区块头中的extra数据是不是比约定的参数最大值还大,如果超过,则返回错误,其次会去判断该区块是不是一个uncle区块,如果header的时间戳不符合规则则返回错误,然后根据链的配置,header的时间戳以及上一个区块计算中本次区块期待的难度,如果header的难度和期待的不一致,或header的gasLimit比最大数字还大,或已用的gas超过gasLimit,则返回错误.如果gasLimit超过预定的最大值或最小值,或header的number减去上一个block的header的number不为1,则返回错误.`seal`为true,则会去校验该区块是否符合pow的工作量证明的要求(`verifySeal`方法),因为私有链一般是不需要pow.最后两个if是去判断区块是否具有正确的hash,防止用户在不同的链上,以及校验块头的额外数据字段是否符合DAO硬叉规则

###### uncle block:
__eth允许旷工在挖到一个块的同时包含一组uncle block列表,主要有两个作用:__
     1. 由于网络传播的延迟原因,通过奖励那些由于不是链组成区块部分而产生陈旧或孤立区块的旷工,从而减少集权激励
     2. 通过增加在主链上的工作量来增加链条的安全性(在工作中,少浪费工作在陈旧的块上)

eth的pow核心代码:

```
// CalcDifficulty is the difficulty adjustment algorithm. It returns
// the difficulty that a new block should have when created at time
// given the parent block's time and difficulty.
// TODO (karalabe): Move the chain maker into this package and make this private!
func CalcDifficulty(config *params.ChainConfig, time uint64, parent *types.Header) *big.Int {
	next := new(big.Int).Add(parent.Number, big1)
	switch {
	case config.IsByzantium(next):
		return calcDifficultyByzantium(time, parent)
	case config.IsHomestead(next):
		return calcDifficultyHomestead(time, parent)
	default:
		return calcDifficultyFrontier(time, parent)
	}
}
```
###### 该方法的第一个`case`是根据拜占庭规则去计算新块应该具有的难度,第二个`case`是根据宅基地规则去计算新块应该具有的难度,第三个`case`是根据边界规则去计算难度


#### pow计算生成新块代码解析
 __/consensus/seal.go/seal__

 ```
 // Seal implements consensus.Engine, attempting to find a nonce that satisfies
 // the block's difficulty requirements.
 func (ethash *Ethash) Seal(chain consensus.ChainReader, block *types.Block, stop <-chan struct{}) (*types.Block, error) {
 	// If we're running a fake PoW, simply return a 0 nonce immediately
 	if ethash.fakeMode {
 		header := block.Header()
 		header.Nonce, header.MixDigest = types.BlockNonce{}, common.Hash{}
 		return block.WithSeal(header), nil
 	}
 	// If we're running a shared PoW, delegate sealing to it
 	if ethash.shared != nil {
 		return ethash.shared.Seal(chain, block, stop)
 	}
 	// Create a runner and the multiple search threads it directs
 	abort := make(chan struct{})
 	found := make(chan *types.Block)

 	ethash.lock.Lock()
 	threads := ethash.threads
 	if ethash.rand == nil {
 		seed, err := crand.Int(crand.Reader, big.NewInt(math.MaxInt64))
 		if err != nil {
 			ethash.lock.Unlock()
 			return nil, err
 		}
 		ethash.rand = rand.New(rand.NewSource(seed.Int64()))
 	}
 	ethash.lock.Unlock()
 	if threads == 0 {
 		threads = runtime.NumCPU()
 	}
 	if threads < 0 {
 		threads = 0 // Allows disabling local mining without extra logic around local/remote
 	}
 	var pend sync.WaitGroup
 	for i := 0; i < threads; i++ {
 		pend.Add(1)
 		go func(id int, nonce uint64) {
 			defer pend.Done()
 			ethash.mine(block, id, nonce, abort, found)
 		}(i, uint64(ethash.rand.Int63()))
 	}
 	// Wait until sealing is terminated or a nonce is found
 	var result *types.Block
 	select {
 	case <-stop:
 		// Outside abort, stop all miner threads
 		close(abort)
 	case result = <-found:
 		// One of the threads found a block, abort all others
 		close(abort)
 	case <-ethash.update:
 		// Thread count was changed on user request, restart
 		close(abort)
 		pend.Wait()
 		return ethash.Seal(chain, block, stop)
 	}
 	// Wait for all miners to terminate and return the block
 	pend.Wait()
 	return result, nil
 }

 ```

###### 该方法的foreach中并行挖新块,一旦停止或者找到新快,则废弃其他所有的,如果协程计算有变更,则重新调用方法

###### 好了pow挖矿的核心方法已经出现,｀ethash.mine｀,如果挖取到新块,那么就写入到`found channel`

```
// mine is the actual proof-of-work miner that searches for a nonce starting from
// seed that results in correct final block difficulty.
func (ethash *Ethash) mine(block *types.Block, id int, seed uint64, abort chan struct{}, found chan *types.Block) {
	// Extract some data from the header
	var (
		header = block.Header()
		hash   = header.HashNoNonce().Bytes()
		target = new(big.Int).Div(maxUint256, header.Difficulty)

		number  = header.Number.Uint64()
		dataset = ethash.dataset(number)
	)
	// Start generating random nonces until we abort or find a good one
	var (
		attempts = int64(0)
		nonce    = seed
	)
	logger := log.New("miner", id)
	logger.Trace("Started ethash search for new nonces", "seed", seed)
	for {
		select {
		case <-abort:
			// Mining terminated, update stats and abort
			logger.Trace("Ethash nonce search aborted", "attempts", nonce-seed)
			ethash.hashrate.Mark(attempts)
			return

		default:
			// We don't have to update hash rate on every nonce, so update after after 2^X nonces
			attempts++
			if (attempts % (1 << 15)) == 0 {
				ethash.hashrate.Mark(attempts)
				attempts = 0
			}
			// Compute the PoW value of this nonce
			digest, result := hashimotoFull(dataset, hash, nonce)
			if new(big.Int).SetBytes(result).Cmp(target) <= 0 {
				// Correct nonce found, create a new header with it
				header = types.CopyHeader(header)
				header.Nonce = types.EncodeNonce(nonce)
				header.MixDigest = common.BytesToHash(digest)

				// Seal and return a block (if still needed)
				select {
				case found <- block.WithSeal(header):
					logger.Trace("Ethash nonce found and reported", "attempts", nonce-seed, "nonce", nonce)
				case <-abort:
					logger.Trace("Ethash nonce found but discarded", "attempts", nonce-seed, "nonce", nonce)
				}
				return
			}
			nonce++
		}
	}
}


```

###### `target`是目标新块的难度,`hashimotoFull`方法计算出一个hash值,如果产生的`hash`值小于等于`target`的值,则hash难度符合要求,将符合要求的`header`写入到`found channel`中,并返回,否则一直循环

```
// hashimotoFull aggregates data from the full dataset (using the full in-memory
// dataset) in order to produce our final value for a particular header hash and
// nonce.
func hashimotoFull(dataset []uint32, hash []byte, nonce uint64) ([]byte, []byte) {
	lookup := func(index uint32) []uint32 {
		offset := index * hashWords
		return dataset[offset : offset+hashWords]
	}
	return hashimoto(hash, nonce, uint64(len(dataset))*4, lookup)
}

```

```
// hashimoto aggregates data from the full dataset in order to produce our final
// value for a particular header hash and nonce.
func hashimoto(hash []byte, nonce uint64, size uint64, lookup func(index uint32) []uint32) ([]byte, []byte) {
	// Calculate the number of theoretical rows (we use one buffer nonetheless)
	rows := uint32(size / mixBytes)

	// Combine header+nonce into a 64 byte seed
	seed := make([]byte, 40)
	copy(seed, hash)
	binary.LittleEndian.PutUint64(seed[32:], nonce)

	seed = crypto.Keccak512(seed)
	seedHead := binary.LittleEndian.Uint32(seed)

	// Start the mix with replicated seed
	mix := make([]uint32, mixBytes/4)
	for i := 0; i < len(mix); i++ {
		mix[i] = binary.LittleEndian.Uint32(seed[i%16*4:])
	}
	// Mix in random dataset nodes
	temp := make([]uint32, len(mix))

	for i := 0; i < loopAccesses; i++ {
		parent := fnv(uint32(i)^seedHead, mix[i%len(mix)]) % rows
		for j := uint32(0); j < mixBytes/hashBytes; j++ {
			copy(temp[j*hashWords:], lookup(2*parent+j))
		}
		fnvHash(mix, temp)
	}
	// Compress mix
	for i := 0; i < len(mix); i += 4 {
		mix[i/4] = fnv(fnv(fnv(mix[i], mix[i+1]), mix[i+2]), mix[i+3])
	}
	mix = mix[:len(mix)/4]

	digest := make([]byte, common.HashLength)
	for i, val := range mix {
		binary.LittleEndian.PutUint32(digest[i*4:], val)
	}
	return digest, crypto.Keccak256(append(seed, digest...))
}

```

###### 可以看到,该方法是不断的进行sha256的hash运算,然后返回进行hash值难度的对比,如果hash的十六进制大小小于等于预定的难度,那么这个hash就是符合产块要求的


###### 参考资料

 * __[ethereum讨论聊天室](https://gitter.im/ethereum/go-ethereum)__
 * __[ethereum共识算法解析](http://blog.csdn.net/ddffr/article/details/79073967)__
 * __[ethereum文章分析](http://blog.csdn.net/teaspring/article/details/78050274)__










