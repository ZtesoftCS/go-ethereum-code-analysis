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

