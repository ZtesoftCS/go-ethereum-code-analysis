# 1_Arbitrum开发者快速入门


[Arbitrum Developer Quickstart · Offchain Labs Dev Center](https://developer.offchainlabs.com/docs/developer_quickstart)



Arbitrum是一套高TPS，低使用成本且无需信任的以太坊扩容方案。Arbitrum有三种模式：AnyTrust通道，AnyTurst侧链，Arbitrum Rollup。该文档描述的是如何使用Arbitrum Rollup，该方案目前已在测试网上线。不论你是想在Arbitrum进行开发的开发者，还是希望深入了解Arbitrum的工作原理，本文档都是你的最佳选择。

### Arbitrum是如何工作的？

如果你想要了解Arbitrum的运行机制，最好从[5_Rollup基础](./5_Rollup基础.md)章节起步，可以让你在宏观上有一个基础认知，该章节中还包含了对系统各个组件的更详细的解释。

### 如何开始在Arbitrum上开发？

若想在无繁琐配置的情况下开始使用Arbitrum，参阅在Kovan测试网上运行的[3_公开测试网](./3_公开测试网.md)。

### 如何在本地搭建开发环境？

首先需要先[4_安装](./4_安装.md)Arbitrum及其依赖。下一步，在L1区块链上部署Arbitrum链。你可以在[1_本地区块链](../6_运行节点/1_本地区块链.md)中查看如何部署。

请注意，Arbitrum链是支持动态部署合约的，所以并不需要为每一个应用单独部署一条Arbitrum链，而且你也可以在测试网上部署尚未部署的合约。在一条Arbitrum Rollup链上运行多个应用的好处是，正如在以太网上直接部署合约一样，它们之间可以同步互动。

一旦Arbitrum部署完毕，你可以开始[Hello, Arbitrum](#Hello-Arbitrum)，或[2_合约部署](../3_dapp基础/2_合约部署.md)。

更多详情请见我们的[开源代码](https://github.com/offchainlabs/arbitrum)，并加入我们的[Discord](https://discord.gg/ZpZuw7p)。

### 配置本地Geth和Rollup区块链

请见[1_本地区块链](../6_运行节点/1_本地区块链.md)。

### Hello, Arbitrum

现在你可以在Arbitrum上部署和运行demo dApp了。该demo dApp是Truffle教程中的一个非常简单的宠物商店dApp。

首先先Clone该宠物商店demo并安装其依赖：
```
git clone https://github.com/OffchainLabs/demo-dapp-pet-shop
cd demo-dapp-pet-shop
yarn
```

*部署*

将合约部署到Arbitrum：
`truffle migrate --network arbitrum`

*使用dApp*

1. 安装[Metamask](https://metamask.io)
Metamask安装完毕后，点击`Import Account`并填入下列有预设资金的任意私钥
> 0x979f020f6f6f71577c09db93ba944c89945f10fade64cfc7eb26137d5816fb76  
> 0xd26a199ae5b6bed1992439d1840f7cb400d0a55a0c9f796fa67d7c571fbb180e  
> 0xaf5c2984cb1e2f668ae3fd5bbfe0471f68417efd012493538dcd42692299155b  
> 0x9af1e691e3db692cc9cad4e87b6490e099eb291e3b434a0d3f014dfd2bb747cc  
> 0x27e926925fb5903ee038c894d9880f74d3dd6518e23ab5e5651de93327c7dffa  
> 0xe4b33c0bb790b88f2463facaf86ae7c17cbdab41187e69ddde8cc1c1fda7c9ab  
 
2. 在Metamask中设置本地Arbitrum网络
* 返回Metamask或点击扩展图标
* 点击右上方的`以太坊主网`菜单
* 选择`自定义RPC`
* 在网络名称中输入`Local Arbitrum`
* RPC url中输入`http://127.0.0.1:8547`
* 点击保存
* Metamask现在应该能够浏览在本地Arbitrum网络上有资金的账户了

3. 启动前端
`yarn start`

浏览器会打开[localhost:8080](http://localhost:8080)

在弹出窗口中，点击`Connect`

4. 领养一些宠物

宠物商店dApp现在应该已经跑在浏览器中了。选择几个宠物并点击领养按钮。

### 总结

如果你想尝试另一个demo dApp，请部署该solidity合约并启动前端。

```
git clone https://github.com/OffchainLabs/demo-dapp-election
cd demo-dapp-election
yarn
truffle migrate --network arbitrum
yarn start
```





→ [2_Arbitrum用户快速入门](2_Arbitrum用户快速入门.md)

