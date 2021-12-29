---
title: "The Dao 攻击"
menuTitle: "TheDao"
date: 2019-07-31T23:45:06+08:00
weight: 600001
---

区块链本是去中心化架构，
在以太坊首次遭遇严重黑客攻击智能合约事件时，采用的解决方案却破坏了去中心化理念。

这里不讨论其是否违背区块链精神，本文重点介绍解决方案的技术实施细节。
方案中涉及网络隔离技术和矿工共识投票技术。
且只是从软件上处理，未破坏共识协议。
解决方案的成功实施，为区块链分叉提供了实操经验，值得公链开发者学习。


## 什么是 The DAO 攻击

简单地讲，在2016年4月30日开始，一个名为“The DAO”的初创团队，在以太坊上通过智能合约进行ICO众筹。
28天时间，筹得1.5亿美元，成为历史上最大的众筹项目。

THE DAO创始人之一Stephan TualTual在6月12日宣布，他们发现了软件中存在的“递归调用漏洞”问题。 不幸的是，在程序员修复这一漏洞及其他问题的期间，一个不知名的黑客开始利用这一途径收集THE DAO代币销售中所得的以太币。6月18日，黑客成功挖到超过360万个以太币，并投入到一个DAO子组织中，这个组织和THE DAO有着同样的结构。

THE DAO持有近15%的以太币总数，因此THE DAO这次的问题对以太坊网络及其加密币都产生了负面影响。 

6月17日，以太坊基金会的Vitalik Buterin更新一项重要报告，他表示，DAO正在遭到攻击，不过他已经研究出了解决方案：

现在提出了软件分叉解决方案，通过这种软件分叉，任何调用代码或委托调用的交易——借助代码hash0x7278d050619a624f84f51987149ddb439cdaadfba5966f7cfaea7ad44340a4ba（也就是DAO和子DAO）来减少账户余额——都会视为无效…… 

最终因为社交的不同意见，最终以太坊分裂出支持继续维持原状的以太经典 ETC，同意软件分叉解决方案的在以太坊当前网络实施。

> 以上内容整理自文章[The DAO 攻击](http://chainb.com/?P=Cont&id=1290)。

## 解决方案

因为投资者已经将以太币投入了 The DAO 合约或者其子合约中，在攻击后无法立刻撤回。
需要让投资者快速撤回投资，且能封锁黑客转移资产。

V神公布的解决方案是，在程序中植入转移合约以太币代码，让矿工选择是否支持分叉。
在分叉点到达时则将 The DAO 和其子合约中的以太币转移到一个新的安全的可取款合约中。
全部转移后，原投资者则可以直接从取款合约中快速的拿回以太币。

取款合约在讨论方案时，已经部署到主网。合约地址是 [0xbf4ed7b27f1d666546e30d74d50d173d20bca754][WithdrawDAO]。

取款合约代码如下：
```solidity
// Deployed on mainnet at 0xbf4ed7b27f1d666546e30d74d50d173d20bca754

contract DAO {
    function balanceOf(address addr) returns (uint);
    function transferFrom(address from, address to, uint balance) returns (bool);
    uint public totalSupply;
}

contract WithdrawDAO {
    DAO constant public mainDAO = DAO(0xbb9bc244d798123fde783fcc1c72d3bb8c189413);
    address public trustee = 0xda4a4626d3e16e094de3225a751aab7128e96526;

    function withdraw(){
        uint balance = mainDAO.balanceOf(msg.sender);

        if (!mainDAO.transferFrom(msg.sender, this, balance) || !msg.sender.send(balance))
            throw;
    }

    function trusteeWithdraw() {
        trustee.send((this.balance + mainDAO.balanceOf(this)) - mainDAO.totalSupply());
    }
}
```

同时，为照顾两个阵营，软件提供硬分叉开关，选择权则交给社区。
支持分叉的矿工会在X区块到X+9区块出块时，在区块`extradata`字段中写入`0x64616f2d686172642d666f726b`（“dao-hard-fork”的十六进制数）。

从分叉点开始，如果连续10个区块均有硬分叉投票，则表示硬分叉成功。
 
## 矿工投票与区块头校验

首先，选择权交给社区。
因此是否同意硬分叉，可通过参数进行选择。
但是在当前版本中，社区已完成硬分叉，所以已移除开关类代码。

当前，主网已默认配置支持DAO分叉，并设定了开始硬分叉高度 1920000，代码如下：
```go
// params/config.go:38
MainnetChainConfig = &ChainConfig{ 
		DAOForkBlock:        big.NewInt(1920000),
		DAOForkSupport:      true, 
	}
```
如果矿工支持分叉，则需要在从高度 192000 到 192009，
在区块头 `extradata` 写入指定信息 0x64616f2d686172642d666f726b ，以表示支持硬分叉。
```go
//params/dao.go:28
var DAOForkBlockExtra = common.FromHex("0x64616f2d686172642d666f726b")

// params/dao.go:32
var DAOForkExtraRange = big.NewInt(10)
```
支持硬分叉时矿工写入固定的投票信息：
```go
// miner/worker.go:857
if daoBlock := w.config.DAOForkBlock; daoBlock != nil { 
    // 检查是否区块是否仍然属于分叉处理期间：[DAOForkBlock,DAOForkBlock+10)
	limit := new(big.Int).Add(daoBlock, params.DAOForkExtraRange)
	if header.Number.Cmp(daoBlock) >= 0 && header.Number.Cmp(limit) < 0 { 
        // 如果支持分叉，则覆盖Extra，写入保留的投票信息
		if w.config.DAOForkSupport {
			header.Extra = common.CopyBytes(params.DAOForkBlockExtra)
		} else if bytes.Equal(header.Extra, params.DAOForkBlockExtra) {
            // 如果矿工反对，则不能让其使用保留信息，覆盖它。
			header.Extra = []byte{}  
		}
	}
}
```

需要连续10个区块的原因是为了防止矿工使用保留信息污染非分叉块和方便轻节点安全同步数据。
同时，所有节点在校验区块头时，必须安全地校验特殊字段信息，校验区块是否属于正确的分叉上。

```go
// consensus/ethash/consensus.go:294 
if err := misc.VerifyDAOHeaderExtraData(chain.Config(), header); err != nil { //❶
	return err
} 

// consensus/misc/dao.go:47 
func VerifyDAOHeaderExtraData(config *params.ChainConfig, header *types.Header) error { 
	if config.DAOForkBlock == nil {//❷
		return nil
	}
	limit := new(big.Int).Add(config.DAOForkBlock, params.DAOForkExtraRange) //❸
	if header.Number.Cmp(config.DAOForkBlock) < 0 || header.Number.Cmp(limit) >= 0 {
		return nil
	}
	if config.DAOForkSupport {
		if !bytes.Equal(header.Extra, params.DAOForkBlockExtra) { //❹
			return ErrBadProDAOExtra
		}
	} else {
		if bytes.Equal(header.Extra, params.DAOForkBlockExtra) {//❺
			return ErrBadNoDAOExtra
		}
	}
	// All ok, header has the same extra-data we expect
	return nil
}
```

+ ❶ 在校验区块头时增加 DAO 区块头识别校验。
+ ❷ 如果节点未设置分叉点，则不校验。
+ ❸ 确保只需在 DAO 分叉点的10个区块上校验。
+ ❹ 如果节点允许分叉，则要求区块头 Extra 必须符合要求。
+ ❺ 当然，如果节点不允许分叉，则也不能在区块头中加入非分叉链的 Extra 特殊信息。
 
这种 `config.DAOForkBlock` 开关，类似于互联网公司产品新功能灰度上线的功能开关。
在区块链上，可以先实现功能代码逻辑。至于何时启用，则可以在社区、开发者讨论后，确定最终的开启时间。
当然区块链上区块高度等价于时间戳，比如 DAO 分叉点 1920000 也是讨论后敲定。

### 如何分离网络？

如果分叉后不能快速地分离网络，会导致节点出现奇奇怪怪的问题。
长远来说，为针对以后可能出现的分叉，应设计一种通用解决方案，已降低代码噪音。
否则，你会发现代码中到处充斥着一些各种梗。
但时间又非常紧急，这次的 The DAO 分叉处理是通过特定代码拦截实现。

在我看来，区块链项目不同于其他传统软件，一旦发现严重BUG是非常致命的。
在上线后的代码修改，应保持尽可能少和充分测试。非常同意 the dao 的代码处理方式。
不必为以后可能的分叉，而做出觉得“很棒”的功能。
务实地解决问题才是正道。

不应该让节点同时成为两个阵营的中继点，应分离出两个网络，以让其互不干预。
The DAO 硬分叉的处理方式是:节点连接握手后，向对方请求分叉区块头信息。
在15秒必须响应，否则断开连接。

代码实现是在`eth/handler.go`文件中，在消息层进行拦截处理。

节点握手后，开始15秒倒计时，一旦倒计时结束，则断开连接。
```go
// eth/handler.go:300
	p.forkDrop = time.AfterFunc(daoChallengeTimeout, func() {
		p.Log().Debug("Timed out DAO fork-check, dropping")
		pm.removePeer(p.id)
	})
```
在倒计时前，需要向对方索要区块头信息，以进行分叉校验。
```go
// eth/handler.go:297
	if err := p.RequestHeadersByNumber(daoBlock.Uint64(), 1, 0, false); err != nil {
		return err
	}
``` 
此时，对方在接收到请求时，如果存在此区块头则返回，否则忽略。
```go
// eth/handler.go:348
	case msg.Code == GetBlockHeadersMsg:  
		var query getBlockHeadersData
		if err := msg.Decode(&query); err != nil {
			return errResp(ErrDecode, "%v: %v", msg, err)
		}
		hashMode := query.Origin.Hash != (common.Hash{})
		first := true
		maxNonCanonical := uint64(100) 
		var (
			bytes   common.StorageSize
			headers []*types.Header
			unknown bool
		)
		//省略一部分 ...
		return p.SendBlockHeaders(headers)
```
这样，有几种情况出现。根据不同情况分别处理：

1. 有返回区块头：

如果返回的区块头不一致，则校验不通过，等待倒计时结束。
如果区块头一致，则根据前面提到的校验分叉区块方式检查。
校验失败，此直接断开连接，说明已经属于不同分叉。
校验通过，则关闭倒计时，完成校验。
```go
// eth/handler.go:465
if p.forkDrop != nil && pm.chainconfig.DAOForkBlock.Cmp(headers[0].Number) == 0 { 
				p.forkDrop.Stop()
				p.forkDrop = nil
 
				if err := misc.VerifyDAOHeaderExtraData(pm.chainconfig, headers[0]); err != nil {
					p.Log().Debug("Verified to be on the other side of the DAO fork, dropping")
					return err
				}
				p.Log().Debug("Verified to be on the same side of the DAO fork")
				return nil
			}
```
2. 没有返回区块头：

如果自己也没有到达分叉高度，则不校验，假定双方在同一个网络。
但我自己已经到达分叉高度，则考虑对方的TD是否高于我的分叉块。
如果是，则包容，暂时认为属于同一网络。否则，则校验失败。
```go
// eth/handler.go:442 
if len(headers) == 0 && p.forkDrop != nil { 
	verifyDAO := true

	if daoHeader := pm.blockchain.GetHeaderByNumber(pm.chainconfig.DAOForkBlock.Uint64()); daoHeader != nil {
		if _, td := p.Head(); td.Cmp(pm.blockchain.GetTd(daoHeader.Hash(), daoHeader.Number.Uint64())) >= 0 {
			verifyDAO = false
		}
	} 
	if verifyDAO {
		p.Log().Debug("Seems to be on the same side of the DAO fork")
		p.forkDrop.Stop()
		p.forkDrop = nil
		return nil
	}
}
```

### 转移资产

上述所做的一切均为安全、稳定的硬分叉，隔离两个网络。
硬分叉的目的是，以人为介入的方式拦截攻击者资产。

一旦到达分叉点，则立即激活资产转移操作。
首先，矿工在挖到分叉点时，需执行转移操作：
```go
// miner/worker.go:877
func (w *worker) commitNewWork(interrupt *int32, noempty bool, timestamp int64) {
	// ...
// Create the current work task and check any fork transitions needed
	env := w.current
	if w.config.DAOForkSupport && w.config.DAOForkBlock != nil && w.config.DAOForkBlock.Cmp(header.Number) == 0 {
		misc.ApplyDAOHardFork(env.state)
	}
	// ...
}	
```
其次，任何节点在接收区块，进行本地处理校验时同样需要在分叉点执行：
```go
// core/state_processor.go:66
func (p *StateProcessor) Process(block *types.Block, statedb *state.StateDB, cfg vm.Config) (types.Receipts, []*types.Log, uint64, error) {
	//...
	// Mutate the block and state according to any hard-fork specs
	if p.config.DAOForkSupport && p.config.DAOForkBlock != nil && p.config.DAOForkBlock.Cmp(block.Number()) == 0 {
		misc.ApplyDAOHardFork(statedb)
	}
	//...
}	
```
转移资金也是通过取款合约处理。
将The DAO 合约包括子合约的资金，全部转移到新合约中。

```go
func ApplyDAOHardFork(statedb *state.StateDB) {
	// Retrieve the contract to refund balances into
	if !statedb.Exist(params.DAORefundContract) {
		statedb.CreateAccount(params.DAORefundContract)
	}

	// Move every DAO account and extra-balance account funds into the refund contract
	for _, addr := range params.DAODrainList() {
		statedb.AddBalance(params.DAORefundContract, statedb.GetBalance(addr))
		statedb.SetBalance(addr, new(big.Int))
	}
}
```
至此，合约资金已全部强制转移到新合约。 

## 参考资料
1. [EIP 779: Hardfork Meta: DAO Fork](http://eips.ethereum.org/EIPS/eip-779)
2. [Hard Fork Specification](https://blog.slock.it/hard-fork-specification-24b889e70703)
3. [PR#2814-finalize the DAO fork](https://github.com/ethereum/go-ethereum/pull/2814)

[WithdrawDAO]:https://etherscan.io/address/0xbf4ed7b27f1d666546e30d74d50d173d20bca754