翻译内容来自 ( [https://github.com/ethereum/go-ethereum/pull/1889](https://github.com/ethereum/go-ethereum/pull/1889) )

This PR aggregates a lot of small modifications to core, trie, eth and other packages to collectively implement the eth/63 fast synchronization algorithm. In short, geth --fast.

这个提交请求包含了对core，trie,eth和其他一些package的微小的修改，来共同实现eth/63的快速同步算法。 简单来说， geth --fast.

## Algorithm 算法

The goal of the the fast sync algorithm is to exchange processing power for bandwidth usage. Instead of processing the entire block-chain one link at a time, and replay all transactions that ever happened in history, fast syncing downloads the transaction receipts along the blocks, and pulls an entire recent state database. This allows a fast synced node to still retain its status an an archive node containing all historical data for user queries (and thus not influence the network's health in general), but at the same time to reassemble a recent network state at a fraction of the time it would take full block processing.

快速同步算法的目标是用带宽换计算。 快速同步不是通过一个链接处理整个区块链，而是重放历史上发生的所有事务，快速同步会沿着这些块下载事务处理单据，然后拉取整个最近的状态数据库。 这允许快速同步的节点仍然保持其包含用于用户查询的所有历史数据的存档节点的状态（并且因此不会一般地影响网络的健康状况），对于最新的区块状态更改，会使用全量的区块处理方式。

An outline of the fast sync algorithm would be:

- Similarly to classical sync, download the block headers and bodies that make up the blockchain
- Similarly to classical sync, verify the header chain's consistency (POW, total difficulty, etc)
- Instead of processing the blocks, download the transaction receipts as defined by the header
- Store the downloaded blockchain, along with the receipt chain, enabling all historical queries
- When the chain reaches a recent enough state (head - 1024 blocks), pause for state sync:
	- Retrieve the entire Merkel Patricia state trie defined by the root hash of the pivot point
	- For every account found in the trie, retrieve it's contract code and internal storage state trie
- Upon successful trie download, mark the pivot point (head - 1024 blocks) as the current head
- Import all remaining blocks (1024) by fully processing them as in the classical sync

快速同步算法的概要：

- 与原有的同步类似，下载组成区块链的区块头和区块body
- 类似于原有的同步，验证区块头的一致性（POW，总难度等）
- 下载由区块头定义的交易收据,而不是处理区块。
- 存储下载的区块链和收据链，启用所有历史查询
- 当链条达到最近的状态（头部 - 1024个块）时，暂停状态同步：
	- 获取由 pivot point定义的区块的完整的Merkel Patricia Trie状态
	- 对于Merkel Patricia Trie里面的每个账户，获取他的合约代码和中间存储的Trie
- 当Merkel Patricia Trie下载成功后，将pivot point定义的区块作为当前的区块头
- 通过像原有的同步一样对其进行完全处理，导入所有剩余的块（1024）

## 分析 Analysis
By downloading and verifying the entire header chain, we can guarantee with all the security of the classical sync, that the hashes (receipts, state tries, etc) contained within the headers are valid. Based on those hashes, we can confidently download transaction receipts and the entire state trie afterwards. Additionally, by placing the pivoting point (where fast sync switches to block processing) a bit below the current head (1024 blocks), we can ensure that even larger chain reorganizations can be handled without the need of a new sync (as we have all the state going that many blocks back).

通过下载和验证整个头部链，我们可以保证传统同步的所有安全性，头部中包含的哈希（收据，状态尝试等）是有效的。 基于这些哈希，我们可以自信地下载交易收据和整个状态树。 另外，通过将pivoting point（快速同步切换到区块处理）放置在当前区块头（1024块）的下方一点，我们可以确保甚至可以处理更大的区块链重组，而不需要新的同步（因为我们有所有的状态 TODO）。

## 注意事项 Caveats
The historical block-processing based synchronization mechanism has two (approximately similarly costing) bottlenecks: transaction processing and PoW verification. The baseline fast sync algorithm successfully circumvents the transaction processing, skipping the need to iterate over every single state the system ever was in. However, verifying the proof of work associated with each header is still a notably CPU intensive operation.

基于历史块处理的同步机制具有两个（近似相似成本）瓶颈：交易处理和PoW验证。 基线快速同步算法成功地绕开了事务处理，跳过了对系统曾经处于的每一个状态进行迭代的需要。但是，验证与每个头相关联的工作证明仍然是CPU密集型操作。

However, we can notice an interesting phenomenon during header verification. With a negligible probability of error, we can still guarantee the validity of the chain, only by verifying every K-th header, instead of each and every one. By selecting a single header at random out of every K headers to verify, we guarantee the validity of an N-length chain with the probability of (1/K)^(N/K) (i.e. we have 1/K chance to spot a forgery in K blocks, a verification that's repeated N/K times).

但是，我们可以在区块头验证期间注意到一个有趣的现象 由于错误概率可以忽略不计，我们仍然可以保证链的有效性，只需要验证每个第K个头，而不是每个头。 通过从每个K头中随机选择一个头来验证，我们保证N长度链的可能会被伪造的概率为（1 / K）^（N / K）（在K块中我们有1 / K的机会发现一个伪造，而验证经行了N/K次。）。

Let's define the negligible probability Pn as the probability of obtaining a 256 bit SHA3 collision (i.e. the hash Ethereum is built upon): 1/2^128. To honor the Ethereum security requirements, we need to choose the minimum chain length N (below which we veriy every header) and maximum K verification batch size such as (1/K)^(N/K) <= Pn holds. Calculating this for various {N, K} pairs is pretty straighforward, a simple and lenient solution being http://play.golang.org/p/B-8sX_6Dq0.

我们将可忽略概率Pn定义为获得256位SHA3冲突（以太坊的Hash算法）的概率：1/2 ^ 128。 为了遵守以太坊的安全要求，我们需要选择最小链长N（在我们每个块都验证之前），最大K验证批量大小如（1 / K）^（N / K）<= Pn。 对各种{N，K}对进行计算是非常直接的，一个简单和宽松的解决方案是http://play.golang.org/p/B-8sX_6Dq0。

|N	    |K		|N	    |K		    |N	    |K		    |N	    |K  |
| ------|-------|-------|-----------|-------|-----------|-------|---|
|1024	|43		|1792	|91		    |2560	|143		|3328	|198|
|1152	|51		|1920	|99		    |2688	|152		|3456	|207|
|1280	|58		|2048	|108		|2816	|161		|3584	|217|
|1408	|66		|2176	|116		|2944	|170		|3712	|226|
|1536	|74		|2304	|128		|3072	|179		|3840	|236|
|1664	|82		|2432	|134		|3200	|189		|3968	|246|


The above table should be interpreted in such a way, that if we verify every K-th header, after N headers the probability of a forgery is smaller than the probability of an attacker producing a SHA3 collision. It also means, that if a forgery is indeed detected, the last N headers should be discarded as not safe enough. Any {N, K} pair may be chosen from the above table, and to keep the numbers reasonably looking, we chose N=2048, K=100. This will be fine tuned later after being able to observe network bandwidth/latency effects and possibly behavior on more CPU limited devices.

上面的表格应该这样解释：如果我们每隔K个区块头验证一次区块头，在N个区块头之后，伪造的概率小于攻击者产生SHA3冲突的概率。 这也意味着，如果确实发现了伪造，那么最后的N个头部应该被丢弃，因为不够安全。 可以从上表中选择任何{N，K}对，为了选择一个看起来好看点的数字，我们选择N = 2048，K = 100。 后续可能会根据网络带宽/延迟影响以及可能在一些CPU性能比较受限的设备上运行的情况来进行调整。

Using this caveat however would mean, that the pivot point can be considered secure only after N headers have been imported after the pivot itself. To prove the pivot safe faster, we stop the "gapped verificatios" X headers before the pivot point, and verify every single header onward, including an additioanl X headers post-pivot before accepting the pivot's state. Given the above N and K numbers, we chose X=24 as a safe number.

然而，使用这个特性意味着，只有导入N个区块之后再导入pivot节点才被认为是安全的。 为了更快地证明pivot的安全性，我们在距离pivot节点X距离的地方停止隔块验证的行为,对随后出现的每一个块进行验证直到pivot。 鉴于上述N和K数字，我们选择X = 24作为安全数字。

With this caveat calculated, the fast sync should be modified so that up to the pivoting point - X, only every K=100-th header should be verified (at random), after which all headers up to pivot point + X should be fully verified before starting state database downloading. Note: if a sync fails due to header verification the last N headers must be discarded as they cannot be trusted enough.

通过计算caveat，快速同步需要修改为pivoting point - X,每隔100个区块头随机挑选其中的一个来进行验证，之后的每一个块都需要在状态数据库下载完成之后完全验证，如果因为区块头验证失败导致的同步失败，那么最后的N个区块头都需要被丢弃，应为他们达不到信任标准。


## 缺点 Weakness
Blockchain protocols in general (i.e. Bitcoin, Ethereum, and the others) are susceptible to Sybil attacks, where an attacker tries to completely isolate a node from the rest of the network, making it believe a false truth as to what the state of the real network is. This permits the attacker to spend certain funds in both the real network and this "fake bubble". However, the attacker can only maintain this state as long as it's feeding new valid blocks it itself is forging; and to successfully shadow the real network, it needs to do this with a chain height and difficulty close to the real network. In short, to pull off a successful Sybil attack, the attacker needs to match the network's hash rate, so it's a very expensive attack.

常见的区块链(比如比特币，以太坊以及其他)是比较容易受女巫攻击的影响，攻击者试图把被攻击者从主网络上完全隔离开，让被攻击者接收一个虚假的状态。这就允许攻击者在真实的网络同时这个虚假的网络上花费同一笔资金。然而这个需要攻击者提供真实的自己锻造的区块，而且需要成功的影响真实的网络，就需要在区块高度和难度上接近真实的网络。简单来说，为了成功的实施女巫攻击，攻击者需要接近主网络的hash rate，所以是一个非常昂贵的攻击。

Compared to the classical Sybil attack, fast sync provides such an attacker with an extra ability, that of feeding a node a view of the network that's not only different from the real network, but also that might go around the EVM mechanics. The Ethereum protocol only validates state root hashes by processing all the transactions against the previous state root. But by skipping the transaction processing, we cannot prove that the state root contained within the fast sync pivot point is valid or not, so as long as an attacker can maintain a fake blockchain that's on par with the real network, it could create an invalid view of the network's state.

与传统的女巫攻击相比，快速同步为攻击者提供了一种额外的能力，即为节点提供一个不仅与真实网络不同的网络视图，而且还可能绕过EVM机制。 以太坊协议只通过处理所有事务与以前的状态根来验证状态根散列。 但是通过跳过事务处理，我们无法证明快速同步pivot point中包含的state root是否有效，所以只要攻击者能够保持与真实网络相同的假区块链，就可以创造一个无效的网络状态视图。

To avoid opening up nodes to this extra attacker ability, fast sync (beside being solely opt-in) will only ever run during an initial sync (i.e. when the node's own blockchain is empty). After a node managed to successfully sync with the network, fast sync is forever disabled. This way anybody can quickly catch up with the network, but after the node caught up, the extra attack vector is plugged in. This feature permits users to safely use the fast sync flag (--fast), without having to worry about potential state root attacks happening to them in the future. As an additional safety feature, if a fast sync fails close to or after the random pivot point, fast sync is disabled as a safety precaution and the node reverts to full, block-processing based synchronization.

为了避免将节点开放给这个额外的攻击者能力，快速同步(特别指定)将只在初始同步期间运行(节点的本地区块链是空的)。 在一个节点成功与网络同步后，快速同步永远被禁用。 这样任何人都可以快速地赶上网络，但是在节点追上之后，额外的攻击矢量就被插入了。这个特性允许用户安全地使用快速同步标志（--fast），而不用担心潜在的状态 在未来发生的根攻击。 作为附加的安全功能，如果快速同步在随机 pivot point附近或之后失败，则作为安全预防措施禁用快速同步，并且节点恢复到基于块处理的完全同步。

## 性能 Performance
To benchmark the performance of the new algorithm, four separate tests were run: full syncing from scrath on Frontier and Olympic, using both the classical sync as well as the new sync mechanism. In all scenarios there were two nodes running on a single machine: a seed node featuring a fully synced database, and a leech node with only the genesis block pulling the data. In all test scenarios the seed node had a fast-synced database (smaller, less disk contention) and both nodes were given 1GB database cache (--cache=1024).

为了对新算法的性能进行基准测试，运行了四个单独的测试：使用经典同步以及新的同步机制，从Frontier和Olympic上的scrath完全同步。 在所有情况下，在一台机器上运行两个节点：具有完全同步的数据库的种子节点，以及只有起始块拉动数据的水蛭节点。 在所有测试场景中，种子节点都有一个快速同步的数据库（更小，更少的磁盘争用），两个节点都有1GB的数据库缓存（--cache = 1024）。

The machine running the tests was a Zenbook Pro, Core i7 4720HQ, 12GB RAM, 256GB m.2 SSD, Ubuntu 15.04.

运行测试的机器是Zenbook Pro，Core i7 4720HQ，12GB RAM，256GB m.2 SSD，Ubuntu 15.04。

| Dataset (blocks, states)	| Normal sync (time, db)	| Fast sync (time, db) |
| ------------------------- |:-------------------------:| ---------------------------:|
|Frontier, 357677 blocks, 42.4K states	| 12:21 mins, 1.6 GB	| 2:49 mins, 235.2 MB |
|Olympic, 837869 blocks, 10.2M states	| 4:07:55 hours, 21 GB	| 31:32 mins, 3.8 GB  |


The resulting databases contain the entire blockchain (all blocks, all uncles, all transactions), every transaction receipt and generated logs, and the entire state trie of the head 1024 blocks. This allows a fast synced node to act as a full archive node from all intents and purposes.

结果数据库包含整个区块链（所有区块，所有的区块，所有的交易），每个交易收据和生成的日志，以及头1024块的整个状态树。 这使得一个快速的同步节点可以充当所有意图和目的的完整归档节点。


## 结束语 Closing remarks
The fast sync algorithm requires the functionality defined by eth/63. Because of this, testing in the live network requires for at least a handful of discoverable peers to update their nodes to eth/63. On the same note, verifying that the implementation is truly correct will also entail waiting for the wider deployment of eth/63.

快速同步算法需要由eth / 63定义的功能。 正因为如此，现网中的测试至少需要少数几个可发现的对等节点将其节点更新到eth / 63。 同样的说明，验证这个实施是否真正正确还需要等待eth / 63的更广泛部署。