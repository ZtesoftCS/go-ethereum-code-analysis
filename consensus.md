# Consensus

clique 主要涉及POA，用于测试网络； ethash主要涉及POW，用于主网络； misc是用于之前DAO分叉的文件。
下图是consensus文件中各组件的关系图：
![image](https://github.com/Billy1900/go-ethereum-code-analysis/blob/master/picture/Consensus-architecture.png)
Engine接口定义了共识引擎需要实现的所有函数，实际上按功能可以划分为2类：
- 区块验证类：以Verify开头，当收到新区块时，需要先验证区块的有效性
- 区块盖章类：包括Prepare/Finalize/Seal等，用于最终生成有效区块（比如添加工作量证明）
与区块验证相关联的还有2个外部接口：Processor用于执行交易，而Validator用于验证区块内容和状态。另外，由于需要访问以前的区块链数据，抽象出了一个ChainReader接口，BlockChain和HeaderChain都实现了该接口以完成对数据的访问。

## 区块验证流程
![image](https://github.com/Billy1900/go-ethereum-code-analysis/blob/master/picture/block-verification-process.png)
Downloader收到新区块后会调用BlockChain的InsertChain()函数插入新区块。在插入之前需要先要验证区块的有效性，基本分为4个步骤：
- 验证区块头：调用Ethash.VerifyHeaders()
- 验证区块内容：调用BlockValidator.VerifyBody()（内部还会调用Ethash.VerifyUncles()）
- 执行区块交易：调用BlockProcessor.Process()（基于其父块的世界状态）
- 验证状态转换：调用BlockValidator.ValidateState()</br>
如果验证成功，则往数据库中写入区块信息，然后广播ChainHeadEvent事件。

## 区块盖章流程
![image](https://github.com/Billy1900/go-ethereum-code-analysis/blob/master/picture/block-seal-process.png)
新产生的区块必须经过“盖章(seal)”才能成为有效区块，具体到Ethash来说，就是要执行POW计算以获得低于设定难度的nonce值。这个其实在之前的挖矿流程分析中已经接触过了，主要分为3个步骤：
- 准备工作：调用Ethash.Prepare()计算难度值
- 生成区块：调用Ethash.Finalize()打包新区块
- 盖章：调用Ethash.Seal()进行POW计算，填充nonce值

## 实现分析
### consensus.go
该文件主要是定义整个ｃｏｎｓｅｎｓｕｓ，ｃｈａｉｎＲｅａｄｅｒ是读取以前的区块数据，Ｅｎｇｉｎｅ是ｃｏｎｓｅｎｓｕｓ工作的核心模块，ＰＯＷ是目前的一种机制，可以看到他的核心模块是Ｅｎｇｉｎｅ
<pre><code>type PoW interface {
	Engine
	// Hashrate returns the current mining hashrate of a PoW consensus engine.
	Hashrate() float64
}</code></pre>
### ｅｔｈａｎ/consensus.go/VerifyHeaders()
VerifyHeaders和ＶｅｒｉｆｙＨｅａｄｅｒ实现原理都差不多，只不过ＶｅｒｉｆｙＨｅａｄｅｒｓ是处理一堆ｈｅａｄｅｒｓ
<pre><code>// Spawn as many workers as allowed threads
    workers := runtime.GOMAXPROCS(0)
    if len(headers) < workers {
        workers = len(headers)
    }</code></pre>
首先根据待验证区块的个数确定需要创建的线程数，最大不超过CPU个数。
 <pre><code>var (
        inputs = make(chan int)
        done   = make(chan int, workers)
        errors = make([]error, len(headers))
        abort  = make(chan struct{})
    )
    for i := 0; i < workers; i++ {
        go func() {
            for index := range inputs {
                errors[index] = ethash.verifyHeaderWorker(chain, headers, seals, index)
                done <- index
            }
        }()
    }</code></pre>
这一步就是创建线程了，每个线程会从inputs信道中获得待验证区块的索引号，然后调用verifyHeaderWorker()函数验证该区块，验证完后向done信道发送区块索引号。
<pre><code>errorsOut := make(chan error, len(headers))
    go func() {
        defer close(inputs)
        var (
            in, out = 0, 0
            checked = make([]bool, len(headers))
            inputs  = inputs
        )
        for {
            select {
            case inputs <- in:
                if in++; in == len(headers) {
                    // Reached end of headers. Stop sending to workers.
                    inputs = nil
                }
            case index := <-done:
                for checked[index] = true; checked[out]; out++ {
                    errorsOut <- errors[out]
                    if out == len(headers)-1 {
                        return
                    }
                }
            case <-abort:
                return
            }
        }
    }()
    return abort, errorsOut</code></pre>
这一步启动一个循环，首先往inputs信道中依次发送区块索引号，然后再从done信道中依次接收子线程处理完成的事件，最后返回验证结果。
接下来我们就分析一下ethash.verifyHeaderWorker()主要做了哪些工作：
<pre><code>func (ethash *Ethash) verifyHeaderWorker(chain consensus.ChainReader, headers []*types.Header, seals []bool, index int) error {
    var parent *types.Header
    if index == 0 {
        parent = chain.GetHeader(headers[0].ParentHash, headers[0].Number.Uint64()-1)
    } else if headers[index-1].Hash() == headers[index].ParentHash {
        parent = headers[index-1]
    }
    if parent == nil {
        return consensus.ErrUnknownAncestor
    }
    if chain.GetHeader(headers[index].Hash(), headers[index].Number.Uint64()) != nil {
        return nil // known block
    }
    return ethash.verifyHeader(chain, headers[index], parent, false, seals[index])
}</code></pre>
首先通过ChainReader拿到父块的header，然后调用ethash.verifyHeader()，这个函数就是真正去验证区块头了，这个函数比较长，大概列一下有哪些检查项：
- 时间戳超前当前时间不得大于15s
- 时间戳必须大于父块时间戳
- 通过父块计算出的难度值必须和区块头难度值相同
- 消耗的gas必须小于gas limit
- 当前gas limit和父块gas limit的差值必须在规定范围内
- 区块高度必须是父块高度+1
- 调用ethash.VerifySeal()检查工作量证明
- 验证硬分叉相关的数据
- ethash.VerifySeal()函数，这个函数主要是用来检查工作量证明,用于校验难度的有效性nonce是否小于目标值（解题成功)
> verifyHeader
>- 校验extra大小
>- 校验区块时间戳，跟当前时间比
>- 校验难度值
>- 校验gaslimit上线
>- 校验区块的总gasuserd小于 gaslimit
>- 校验区块的gaslimit 是在合理范围
>- 特殊的校验，比如dao分叉后的几个块extra里面写了特殊数据，来判断一下

### ethan/consensus.go/VerifyUncles()
这个函数是在BlockValidator.VerifyBody()内部调用的，主要是验证叔块的有效性。
<pre><code>    if len(block.Uncles()) > maxUncles {
        return errTooManyUncles
    }
以太坊规定每个区块打包的叔块不能超过2个。
    uncles, ancestors := set.New(), make(map[common.Hash]*types.Header)
    number, parent := block.NumberU64()-1, block.ParentHash()
    for i := 0; i < 7; i++ {
        ancestor := chain.GetBlock(parent, number)
        if ancestor == nil {
            break
        }
        ancestors[ancestor.Hash()] = ancestor.Header()
        for _, uncle := range ancestor.Uncles() {
            uncles.Add(uncle.Hash())
        }
        parent, number = ancestor.ParentHash(), number-1
    }
    ancestors[block.Hash()] = block.Header()
    uncles.Add(block.Hash())</code></pre>
这段代码收集了当前块前7层的祖先块和叔块，用于后面的验证。
<pre><code>    for _, uncle := range block.Uncles() {
        // Make sure every uncle is rewarded only once
        hash := uncle.Hash()
        if uncles.Has(hash) {
            return errDuplicateUncle
        }
        uncles.Add(hash)
        // Make sure the uncle has a valid ancestry
        if ancestors[hash] != nil {
            return errUncleIsAncestor
        }
        if ancestors[uncle.ParentHash] == nil || uncle.ParentHash == block.ParentHash() {
            return errDanglingUncle
        }
        if err := ethash.verifyHeader(chain, uncle, ancestors[uncle.ParentHash], true, true); err != nil {
            return err
        }
    }</code></pre>
 遍历当前块包含的叔块，做以下检查：
- 如果祖先块中已经包含过了该叔块，返回错误
- 如果发现该叔块其实是一个祖先块（即在主链上），返回错误
- 如果叔块的父块不在这7层祖先中，返回错误
- 如果叔块和当前块拥有共同的父块，返回错误（也就是说不能打包和当前块相同高度的叔块）
- 最后验证一下叔块头的有效性

### ethan/consensus.go/Prepare()
<pre><code>
func (ethash *Ethash) Prepare(chain consensus.ChainReader, header *types.Header) error {
    parent := chain.GetHeader(header.ParentHash, header.Number.Uint64()-1)
    if parent == nil {
        return consensus.ErrUnknownAncestor
    }
    header.Difficulty = ethash.CalcDifficulty(chain, header.Time.Uint64(), parent)
    return nil
}</code></pre>
可以看到，会调用CalcDifficulty()计算难度值，继续跟踪：
<pre><code>func (ethash *Ethash) CalcDifficulty(chain consensus.ChainReader, time uint64, parent *types.Header) *big.Int {
    return CalcDifficulty(chain.Config(), time, parent)
}

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
}</code></pre>
根据以太坊的Roadmap，会经历Frontier，Homestead，Metropolis，Serenity这几个大的版本，当前处于Metropolis阶段。Metropolis又分为2个小版本：Byzantium和Constantinople，目前的最新代码版本是Byzantium，因此会调用calcDifficultyByzantium()函数。</br>
计算难度的公式如下：</br>
diff = (parent_diff +(parent_diff / 2048 * max((2 if len(parent.uncles) else 1) - ((timestamp - parent.timestamp) // 9), -99))) + 2^(periodCount - 2)</br>
>- parent_diff ：上一个区块的难度
>- block_timestamp ：当前块的时间戳
>- parent_timestamp：上一个块的时间戳
>- periodCount ：区块num/100000
>- block_timestamp - parent_timestamp 差值小于10秒 变难</br>
  block_timestamp - parent_timestamp 差值10-20秒 不变</br>
  block_timestamp - parent_timestamp 差值大于20秒 变容易，并且大的越多，越容易，但是又上限
>- 总体上块的难度是递增的
>- seal 开始做挖矿的事情，“解题”直到成功或者退出.根据挖矿难度计算目标值,选取随机数nonce+区块头(不包含nonce)的hash，再做一次hash，结果小于目标值，则退出，否则循环重试.如果外部退出了(比如已经收到这个块了)，则立马放弃当前块的打包.Finalize() 做挖矿成功后最后善后的事情,计算矿工的奖励：区块奖励，叔块奖励，

前面一项是根据父块难度值继续难度调整，而后面一项就是传说中的“难度炸弹”。关于难度炸弹相关的具体细节可以参考下面这篇文章：
https://juejin.im/post/59ad6606f265da246f382b88</br>
由于PoS共识机制开发进度延迟，不得不减小难度炸弹从而延迟“冰川时代”的到来，具体做法就是把当前区块高度减小3000000，参见以下代码：
<pre><code>   // calculate a fake block number for the ice-age delay:
    //   https://github.com/ethereum/EIPs/pull/669
    //   fake_block_number = min(0, block.number - 3_000_000
    fakeBlockNumber := new(big.Int)
    if parent.Number.Cmp(big2999999) >= 0 {
        fakeBlockNumber = fakeBlockNumber.Sub(parent.Number, big2999999) // Note, parent is 1 less than the actual block number
    }</code></pre>
    
 ### ethash/consensus.go/FinalizeAndAssemble()
<pre><code>func (ethash *Ethash) Finalize(chain consensus.ChainReader, header *types.Header, state *state.StateDB, txs []*types.Transaction, uncles []*types.Header, receipts []*types.Receipt) (*types.Block, error) {
    // Accumulate any block and uncle rewards and commit the final state root
    accumulateRewards(chain.Config(), state, header, uncles)
    header.Root = state.IntermediateRoot(chain.Config().IsEIP158(header.Number))
    // Header seems complete, assemble into a block and return
    return types.NewBlock(header, txs, uncles, receipts), nil
}</code></pre>
这个挖矿流程是先计算收益，然后生成MPT的Merkle Root，最后创建新区块。

### ethash/consensus.go/sealer/seal()
这个函数就是真正执行POW计算的地方了，代码位于consensus/ethash/sealer.go。代码比较长，分段进行分析：
<pre><code>    abort := make(chan struct{})
    found := make(chan *types.Block)</code></pre>
首先创建了两个channel，用于退出和发现nonce时发送事件。
<pre><code>    ethash.lock.Lock()
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
    }</code></pre>
接着初始化随机数种子和线程数。
<pre><code>    var pend sync.WaitGroup
    for i := 0; i < threads; i++ {
        pend.Add(1)
        go func(id int, nonce uint64) {
            defer pend.Done()
            ethash.mine(block, id, nonce, abort, found)
        }(i, uint64(ethash.rand.Int63()))
    }</code></pre>
然后就是创建线程进行挖矿了，会调用ethash.mine()函数。
<pre><code>    // Wait until sealing is terminated or a nonce is found
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
    return result, nil</code></pre>
最后就是等待挖矿结果了，有可能找到nonce挖矿成功，也有可能别人先挖出了区块从而需要终止挖矿。
</br>ethash.mine()函数的实现，先看一些变量声明：
<pre><code>    var (
        header  = block.Header()
        hash    = header.HashNoNonce().Bytes()
        target  = new(big.Int).Div(maxUint256, header.Difficulty)
        number  = header.Number.Uint64()
        dataset = ethash.dataset(number)
    )
    // Start generating random nonces until we abort or find a good one
    var (
        attempts = int64(0)
        nonce    = seed
    )</code></pre>
其中hash指的是不带nonce的区块头hash值，nonce是一个随机数种子。target是目标值，等于2^256除以难度值，我们接下来要计算的hash值必须小于这个目标值才算挖矿成功。接下来就是不断修改nonce并计算hash值了：
<pre><code>            digest, result := hashimotoFull(dataset.dataset, hash, nonce)
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
                break search
            }
     nonce++</code></pre>
hashimotoFull()函数内部会把hash和nonce拼在一起，计算出一个摘要（digest）和一个hash值（result）。如果hash值满足难度要求，挖矿成功，填充区块头的Nonce和MixDigest字段，然后调用block.WithSeal()生成盖过章的区块：
<pre><code>func (b *Block) WithSeal(header *Header) *Block {
    cpy := *header
    return &Block{
        header:       &cpy,
        transactions: b.transactions,
        uncles:       b.uncles,
    }
}</code></pre>

