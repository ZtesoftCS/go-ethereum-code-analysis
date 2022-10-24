cosmos sdk 提供了一系列链开发的sdk，可以理解为java的spring boot 或者 php的laravel等框架， 在理解了区块链概念的前提下帮助开发者快速开发一条自定义区块链， 基于 cosmos sdk 构建的区块链可以理解为一个应用，就像使用各种第三方服务提供的各种 sdk(比如推送，图形，支付等)构建的app，只不过这个应用的本质是区块链，提供了自定义的区块链业务。

cosmos sdk 提供的服务

1.状态机

2.tendermint

3.abci

# cosmos 官方提供了一个app和module开发的脚手架

[https://github.com/cosmos/scaffold](https://github.com/cosmos/scaffold)

安装好之后使用scffold命令可以快速生成一个包含基础的链开发的目录

.

├── Makefile

├── app

│   ├── app.go

│   └── export.go

├── cmd

│   ├── appcli

│   │   └── main.go

│   └── appd

│       ├── genaccounts.go

│       └── main.go

├── go.mod

├── go.sum

└── x


app目录定义了newapp的相关代码，cmd目录用于存放 server端和client端相关的操作命令。

# cosmos 使用的地址：

cosmos 使用bech32格式化地址，一个cosmos账户里包含多个地址，hrp代表人类可阅读部分

| HRP   | Definition   | 
|:----|:----|
| cosmos   | Cosmos Account Address   | 
| cosmospub   | Cosmos Account Public Key   | 
| cosmosvalcons   | Cosmos Validator Consensus Address   | 
| cosmosvalconspub   | Cosmos Validator Consensus Public Key   | 
| cosmosvaloper   | Cosmos Validator Operator Address   | 
| cosmosvaloperpub   | Cosmos Validator Operator Public Key   | 



