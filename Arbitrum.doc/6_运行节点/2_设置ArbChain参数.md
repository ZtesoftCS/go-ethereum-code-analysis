# 2_设置ArbChain参数


ArbChain时可以设置一系列参数。该文档对这些参数进行了详细解读并阐述了设置方法。

注意：如果你直接通过`arb-validator or demo:deploy`而没有任何参数地运行节点，将会使用默认参数。

可自定义的参数有：
* stake requirement，质押需求：该参数指定验证者需要质押的最小数量。数额越大对作恶者的威慑程度越高，但也增加了验证者的资金成本。
* grace period，宽限期（挑战期）：断言在发布后的该时间内可以被挑战。数值越高，对系统攻击越困难，但也减慢交易的速度。
* speed limit，速度限制：该参数控制着链的运算能进行多块，调整该参数以确保每个验证者都能跟上进度。该数值应设置为你认为的最慢的验证者的速度。当设置为1.0时，为普通开发者笔记本电脑的速度。例如，如果只使用电脑一半的运算能力，你可以设置为0.5。
* max assertion size，最大断言尺寸：某个断言最大的运算量。如果链以100%全速运行，该值就是L2状态更新到L1的频率。

## 推荐参数
对模拟生产环境而言，我们推荐如下参数：
* stake requirement：1ETH，或2%链上的净值，取多者
* grace period：360 分钟
* speed limit：1.0
* max assertion size：50 秒

（提到模拟生产环境是因为，我们**强烈推荐**在主链上要进行真实的生产环境测试）。

对于dapp调试而言，更快的周转比安全更重要，我们建议使用如下参数：

* stake requirement: 0.1 Eth
* grace period: 10 分钟
* speed limit: 0.2
* max assertion size: 15 秒

链的部署会使用上述推荐参数。

关于选取参数的更多分析请见我们的Medium [optimizing challenge periods](https://medium.com/offchainlabs/optimizing-challenge-periods-in-rollup-b61378c87277) 。

←  [1_本地区块链](./6_运行节点/1_本地区块链.md)
→  [1_聚合器](./7_杂项/1_聚合器.md)