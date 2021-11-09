### eth目前的共识算法pow的整理

##### 涉及的代码子包主要有consensus,miner,core,geth

```
/consensus 共识算法
　　  consensus.go
         1. Prepare方法
         2. CalcDifficulty方法：计算工作量
         3. AccumulateRewards方法：计算每个块的出块奖励
         4. VerifySeal方法：校验pow的工作量难度是否符合要求，返回nil则通过
         5. verifyHeader方法：校验区块头是否符合共识规则
```



/miner 挖矿
   work.go
        commitNewWork():提交新的块，新的交易,从交易池中获取未打包的交易，然后提交交易,进行打包
        __核心代码__:
```
         // Create the current work task and check any fork transitions needed
        	work := self.current
        	if self.config.DAOForkSupport && self.config.DAOForkBlock != nil && self.config.DAOForkBlock.Cmp(header.Number) == 0 {
        		misc.ApplyDAOHardFork(work.state)
        	}
        	pending, err := self.eth.TxPool().Pending()
        	if err != nil {
        		log.Error("Failed to fetch pending transactions", "err", err)
        		return
        	}
        	txs := types.NewTransactionsByPriceAndNonce(self.current.signer, pending)
        	work.commitTransactions(self.mux, txs, self.chain, self.coinbase)

```



```
eth/handler.go
	NewProtocolManager --> verifyHeader -->  VerifySeal

```

__整条链的运行,打包交易,出块的流程__
```
/cmd/geth/main.go/main
	makeFullNode-->RegisterEthService-->eth.New-->NewProtocolManager --> verifyHeader -->  VerifySeal

```







　