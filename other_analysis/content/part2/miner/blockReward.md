---
title: "挖矿奖励"
menuTitle: "挖矿奖励"
date: 2019-09-05T22:58:46+08:00
draft: false
weight: 20305
mathjax: true
---

矿工的收益来自于挖矿奖励。这样才能激励矿工积极参与挖矿，维护网络安全。那么，以太坊是如何奖励矿工的呢？我通过两个问题：“奖励是如何计算”和“何时何地奖励”，来协助你理解机制。

## 一、奖励是如何计算的

奖励分成三部分：新块奖励、叔块奖励和矿工费。

$\text{总奖励} =  新块奖励 + 叔块奖励 + 矿工费$


### 第一部分：**新块奖励**

它是奖励矿工消耗电能，完成工作量证明所给予的奖励。该奖励已进行两次调整，起初每个区块有 5 个以太币的奖励，在2017年10月16日（区块高度 4370000）  执行拜占庭硬分叉，将奖励下降到 3 个以太币；在2019年2月28日（区块高度 7280000）执行君士坦丁堡硬分叉，将奖励再次下降到 2 个以太币。

| 时间 |  事件    |  新块奖励  |
| ---- | ---- | ---- |
|      | 创世     |    5 ETH  |
|  2017年10月16日（4370000）    |  拜占庭硬分叉    |    3 ETH  |
| 在2019年2月28日（7280000）     |   君士坦丁堡硬分叉   |   2 ETH   |

以太坊在2015年7月正式发布以太坊主网后，其团队便规划发展阶段，分为前沿、家园、大都会和宁静四个阶段。拜占庭（Byzantium）和君士坦丁堡（Constantinople）是大都会的两个阶段。

新块奖励是矿工的主要收入来源，下降到 2 个 以太币的新块奖励。对矿机厂商和矿工，甚至以太坊挖矿生态都会产生比较大的影响和调整。因为挖矿收益减少，机会成本增加，在以太坊上挖矿将会变得性价比低于其他币种，因此可能会降低矿工的积极性。这也是迫使以太坊向以太坊2.0升级的一种助燃剂，倒逼以太坊更新换代。

### 第二部分：叔块奖励

以太坊出块间隔平均为12秒，区块链软分叉是一种普遍现象，如果采取和比特币一样处理方式，只有最长链上的区块才有出块奖励，对于那些挖到区块而最终不在最长链上的矿工来说，就很不公平，而且这种“不公平”将是一个普遍情况。这会影响矿工们挖矿的积极性，甚至可能削弱以太坊网络的系统安全，也是对算力的一种浪费。因此，以太坊系统对不在最长链上的叔块，设置了**叔块奖励**。

叔块奖励也分成两部分：**奖励叔块的创建者**和 **奖励收集叔块的矿工**。

叔块创建者的奖励根据“近远”关系而不同，和当前区块隔得越远，奖励越少。
$$
\text{挖叔块奖励}=\frac{8-(当前区块高度-叔块高度)}{8} * \text{当前区块挖矿奖励}
$$

| 叔块   | 奖励 | 按挖矿奖励 2 ETH计算 |
| ------ | ---- | -------------------- |
| 第一代 | 7/8  | 1.75 ETH             |
| 第二代 | 6/8  | 1.5 ETH              |
| 第三代 | 5/8  | 1.25 ETH             |
| 第四代 | 4/8  | 1 ETH                |
| 第五代 | 3/8  | 0.75 ETH             |
| 第六代 | 2/8  | 0.5 ETH              |
| 第七代 | 1/8  | 0.25 ETH             |

注意叔块中所产生的交易费是不返给创建者的，毕竟叔块中的交易是不能作数的。



**收录叔块的矿工**

每收录一个叔块将到多得 1/32 的区块挖矿奖励。
$$
收集叔块奖励 = 数量数量 \times  \frac{新块奖励}{32}
$$


### 第三部分：矿工费

矿工处理交易，并校验和打包到区块中去。此时交易签名者需要支付矿工费给矿工。每笔交易收多少矿工费，取决于交易消耗了多少燃料，它等于用户所自主设置的燃料单价GasPrice 乘以交易所消耗的燃料。
$$
Fee = \text{tx.gasPrice} \times \text{tx.gasUsed}
$$


## 二、何时何地奖励

奖励是在挖矿打包好一个区块时，便已在其中完成了奖励的发放，相当于是实时结算。

矿工费的发放是在处理完一笔交易时，便根据交易所消耗的 Gas 直接存入到矿工账户中；区块奖励和叔块奖励，则是在处理完所有交易后，进行奖励实时计算。



## 三、代码展示

**实时结算交易矿工费**

```go
//core/state_transition.go
func (st *StateTransition) TransitionDb() (*ExecutionResult, error) {
	 //...
	var (
		ret   []byte
		vmerr error // vm errors do not effect consensus and are therefore not assigned to err
	)
	if contractCreation {
		ret, _, st.gas, vmerr = st.evm.Create(sender, st.data, st.gas, st.value)
	} else {
		// Increment the nonce for the next transaction
		st.state.SetNonce(msg.From(), st.state.GetNonce(sender.Address())+1)
		ret, st.gas, vmerr = st.evm.Call(sender, st.to(), st.data, st.gas, st.value)
	}
	st.refundGas()
	st.state.AddBalance(st.evm.Coinbase, new(big.Int).Mul(new(big.Int).SetUint64(st.gasUsed()), st.gasPrice))

	return &ExecutionResult{
		UsedGas:    st.gasUsed(),
		Err:        vmerr,
		ReturnData: ret,
	}, nil
}
```

**实时结算挖矿奖励和叔块奖励**

```go
//consensus/ethash/consensus.go:572
func (ethash *Ethash) Finalize(chain consensus.ChainReader, header *types.Header, state *state.StateDB, txs []*types.Transaction, uncles []*types.Header) {
	// Accumulate any block and uncle rewards and commit the final state root
	accumulateRewards(chain.Config(), state, header, uncles)
	header.Root = state.IntermediateRoot(chain.Config().IsEIP158(header.Number))
}
func accumulateRewards(config *params.ChainConfig, state *state.StateDB, header *types.Header, uncles []*types.Header) {
	// Select the correct block reward based on chain progression
	blockReward := FrontierBlockReward
	if config.IsByzantium(header.Number) {
		blockReward = ByzantiumBlockReward
	}
	if config.IsConstantinople(header.Number) {
		blockReward = ConstantinopleBlockReward
	}
	// Accumulate the rewards for the miner and any included uncles
	reward := new(big.Int).Set(blockReward)
	r := new(big.Int)
	for _, uncle := range uncles {
		r.Add(uncle.Number, big8)
		r.Sub(r, header.Number)
		r.Mul(r, blockReward)
		r.Div(r, big8)
		state.AddBalance(uncle.Coinbase, r)

		r.Div(blockReward, big32)
		reward.Add(reward, r)
	}
	state.AddBalance(header.Coinbase, reward)
}
```