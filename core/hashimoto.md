Hashimoto :I/O bound proof of work


Abstract: Using a cryptographic hash function not as a proofofwork by itself, but
rather as a generator of pointers to a shared data set, allows for an I/O bound
proof of work. This method of proof of work is difficult to optimize via ASIC
design, and difficult to outsource to nodes without the full data set. The name is
based on the three operations which comprise the algorithm: hash, shift, and
modulo.

摘要：使用密码散列函数本身并不作为工作的证明，
而是作为指向共享数据集的指针生成器，允许I / O绑定
工作证明。 这种工作证明方法很难通过ASIC设计来优化，并且在没有完整数据集的情况下很难外包给节点。 这个名字是基于构成算法的三个操作：散列，移位和
模。


The need for proofs which are difficult to outsource and optimize

工作量证明难以外包和优化的需求

A common challenge in cryptocurrency development is maintaining decentralization ofthe
network. The use ofproofofwork to achieve decentralized consensus has been most notably
demonstrated by Bitcoin, which uses partial collisions with zero ofsha256, similar to hashcash. As
Bitcoin’s popularity has grown, dedicated hardware (currently application specific integrated circuits, or
ASICs) has been produced to rapidly iterate the hash­based proofofwork function. Newer projects
similar to Bitcoin often use different algorithms for proofofwork, and often with the goal ofASIC
resistance. For algorithms such as Bitcoin’s, the improvement factor ofASICs means that commodity
computer hardware can no longer be effectively used, potentially limiting adoption.

加密货币发展的一项挑战就是如何维持去中心化的网络结构。 正如比特币采用sha256哈希谜题的工作量证明方式来达到去中心化的一致性。 随着比特币的流行，专用硬件(目前的专用集成电路，或者是ASICs)已经被用来快速的执行基于hash方式的工作量证明函数。类似比特币的新项目通常使用不同的工作量证明算法，而且通常都有抵抗ASICs的目标。对于诸如比特币之类的算法，ASIC的对于性能的提升意味着普通的商业计算机硬件不再有效使用，可能会被限制采用。

Proofofwork can also be “outsourced”, or performed by a dedicated machine (a “miner”)
without knowledge ofwhat is being verified. This is often the case in Bitcoin’s “mining pools”. It is also
beneficial for a proofofwork algorithm to be difficult to outsource, in order to promote decentralization
and encourage all nodes participating in the proofofwork process to also verify transactions. With these
goals in mind, we present Hashimoto, an I/O bound proofofwork algorithm we believe to be resistant to
both ASIC design and outsourcing.

工作量证明同样能够被外包出去，或者使用专用的机器(矿机)来执行工作量证明，而这些机器对于验证的内容并不清楚。比特币的“矿池”通常就是这种情况。如果工作量证明算法很难外包，以促进去中心化
并鼓励参与证明过程的所有节点也验证交易。为了达到这个目标，我们设计了hashimoti, 一个基于I/O 带宽的工作量证明算法，我们认为这个算法可以抵抗ASICs，同时也难以外包。

Initial attempts at "ASIC resistance" involved changing Bitcoin's sha256 algorithm for a different,
more memory intensive algorithm, Percival's "scrypt" password based key derivation function1. Many
implementations set the scrypt arguments to low memory requirements, defeating much ofthe purpose of
the key derivation algorithm. While changing to a new algorithm, coupled with the relative obscurity of the
various scrypt­based cryptocurrencies allowed for a delay, scrypt optimized ASICs are now available.
Similar attempts at variations or multiple heterogeneous hash functions can at best only delay ASIC
implementations.

“ASIC抗性”的初始尝试包括改变比特币的sha256算法，用不同的，更多的内存密集型算法，Percival's "scrypt" password based key derivation function。许多实现都将脚本参数设置为低内存要求，这大大破坏了密钥派生算法的目的。在改用新算法的同时，再加上各种以scrypt为基础的加密货币的相对朦胧可能导致延迟，而且scrypt优化的ASIC现在已经上市。类似的变化尝试或多个异构散列函数最多只能延迟ASIC实现。

Leveraging shared data sets to create I/O bound proofs

利用共享数据集创建I / O限制证明

	"A supercomputer is a device for turning compute-bound problems into I/O-bound  problems."
	-Ken Batcher


	“超级计算机是将计算受限问题转化为I / O约束问题的一种设备。”
	Ken Batcher

Instead, an algorithm will have little room to be sped up by new hardware if it acts in a way that commodity computer systems are already optimized for.

相反，如果一种算法以商品计算机系统已经优化的方式运行，那么算法将没有多少空间可以被新硬件加速。

Since I/O bounds are what decades ofcomputing research has gone towards solving, it's unlikely that the relatively small motivation ofmining a few coins would be able to advance the state ofthe art in cache hierarchies. In the case that advances are made, they will be likely to impact the entire industry of computer hardware.

由于I / O界限是几十年来计算研究已经解决的问题，挖掘一些加密货币的相对较小的动机将不可能提高缓存层次结构的艺术水平。 在取得进展的情况下，可能会影响整个计算机硬件产业。

Fortuitously, all nodes participating in current implementations ofcryptocurrency have a large set of mutually agreed upon data; indeed this “blockchain” is the foundation ofthe currency. Using this large data set can both limit the advantage ofspecialized hardware, and require working nodes to have the entire data set.

幸运的是，参与当前加密货币实施的所有节点都有大量相互同意的数据;实际上，“区块链”是货币的基础。 使用这个大数据集既可以限制专用硬件的优点，又可以让工作节点拥有整个数据集。

Hashimoto is based offBitcoin’s proofofwork2. In Bitcoin’s case, as in Hashimoto, a successful
proofsatisfies the following inequality:

Hashimoto是基于比特币的工作量证明。 在比特币的情况下，和Hashimoto一样，一个成功的证明满足以下不等式：

	hash_output < target

For bitcoin, the hash_output is determined by

在比特币中， hash_output是由下面决定的。

	hash_output = sha256(prev_hash, merkle_root, nonce)

where prev_hash is the previous block’s hash and cannot be changed. The merkle_root is based on the transactions included in the block, and will be different for each individual node. The nonce is rapidly incremented as hash_outputs are calculated and do not satisfy the inequality. Thus the bottleneck of the proofis the sha256 function, and increasing the speed ofsha256 or parallelizing it is something ASICs can do very effectively.

prev_hash是前一个区块的hash值，而且不能更改。merkle_root是基于区块中的交易生成的，并且对于每个单独的节点将是不同的。我们通过修改nonce的值来让上面的不等式成立。这样整个工作量证明的瓶颈在于sha256方法，而且通过ASIC可以极大增加sha256的计算速度，或者并行的运行它。

Hashimoto uses this hash output as a starting point, which is used to generated inputs for a second hash function. We call the original hash hash_output_A, and the final result of the prooffinal_output.

Hashimoto使用这个hash_output作为一个起点，用来生成第二个hash函数的输入。我们称原始的hash为hash_output_A, 最终的结果为 prooffinal_output.

Hash_output_A can be used to select many transactions from the shared blockchain, which are then used as inputs to the second hash. Instead of organizing transactions into blocks, for this purpose it is simpler to organize all transactions sequentially. For example, the 47th transaction of the 815th block might be termed transaction 141,918. We will use 64 transactions, though higher and lower numbers could work, with different access properties. We define the following functions:

hash_output_a可用于从共享区块链中选择多个事务，然后将其用作第二个散列的输入。 而不是组织交易成块，为此目的是顺序组织所有交易更简单。 例如，第815个区块的第47个交易可能被称为交易141,918。 我们将使用64个交易，尽管更高和更低的数字可以工作，具有不同的访问属性。 我们定义以下功能：

- nonce 64­bits. A new nonce is created for each attempt.
- get_txid(T) return the txid (a hash ofa transaction) of transaction number T from block B.
- block_height the current height ofthe block chain, which increases at each new block

- nonce 64­bits. 每次尝试会生成一个新的nonce值.
- get_txid(T) 从block B中通过交易序号来获取交易id
- block_height 当前的区块高度

Hashimoto chooses transactions by doing the following:

Hashimoto 通过下面的算法来挑选交易：

	hash_output_A = sha256(prev_hash, merkle_root, nonce)
	for i = 0 to 63 do
		shifted_A = hash_output_A >> i
		transaction = shifted_A mod total_transactions
		txid[i] = get_txid(transaction) << i
	end for
	txid_mix = txid[0] ⊕ txid[1] … ⊕ txid[63]
	final_output = txid_mix ⊕ (nonce << 192)

The target is then compared with final_output, and smaller values are accepted as proofs.

如果 final_output 比  target小，那么就会被接受。


