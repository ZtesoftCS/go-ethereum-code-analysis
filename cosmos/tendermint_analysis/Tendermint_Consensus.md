

## Consensus

### consensus logic flow

先来用一个tx的数据流转为列子讲一下共识算法流程，当一个Tx进来时, tendermint(tm)的mempool会通过mempool connection(一个socket连接，由abci-server提供，端口号为26658)调用App(也就是abci-app，我们自己用任何语言编写的APP逻辑)里的checkTx方法，App向mempool返回验证结果。mempool根据验证结果放行或者拒绝该Tx。

tm把tx暂存在内存池（mempool）里，并把这条tx通过P2P网络复制给其它tm节点。tm发起了对这条 tx 的拜占庭共识投票，所有4个 Tendermint 节点都参与了。投票过程分三轮，第一轮预投票（PreVote），超过 2/3 认可后进入第二轮预提交（PreCommit），超过 2/3 认可后进入最后一轮正式提交（Commit）

tm提交tx时依次通过Consensus Connection(一个socket连接，由abci-server提供，端口号为26658)向ABCI-APP发送指令BeginBlock-->多次DeliverTx-->EndBlock--> Commit，提交成功后会将StateRoot(application Merkle root hash)返回给tm, tm new出一个区块。

app在启动时会与tm建立3个连接abci-server的socket client连接，上面用到了内存池连接和共识连接。



![logic_flow.png](https://i.loli.net/2020/06/12/nYXGsxBDOjqhWrp.jpg)



### 共识引擎构成

Tendermint共识引擎主要功能：

1. 共识算法: 实用拜占庭容错算法
2. P2P协议: gossip算法
3. RPC服务: rpc server提供服务，提供URI over HTTP、JSONRPC over HTTP、JSONRPC over websockets3种访问方式
4. mempool, event

#### 共识算法

![consensus.png](https://i.loli.net/2020/06/23/MigRZmUTf8b7drt.png)



由图中可知支持拜占庭算法的最小节点数为3，少于3个验证者节点则无法支撑算法。

随机选出一些节点作为Validators(验证节点)，然后选择其中一个Validator作为proposer(提议)节点

蓝色线正常流程：

| 阶段                         |                             过程                             |                                   结果 |
| :--------------------------- | :----------------------------------------------------------: | -------------------------------------: |
| 提议阶段(height:H,round:R)   |                  指定的提议者提议一个block                   |       进入预投票阶段(height:H,round:R) |
| 预投票阶段(height:H,round:R) | 开始读取这个block里的所有交易，一一进行验证，如果没有问题，就发出一条 pre-vote 投票消息，表示同意这个block，投一个肯定票，如果发现block里有非法交易，则投一个反对票，这些投票消息会被广播到所有validator节点，所以每个validator节点既会发出一个投票消息，又会收集别人的投票消息，当发现收集到的同意投票数量超过 2/3时，就发出一个pre-commit 预提交投票信息 |       进入预提交阶段(height:H,round:R) |
| 预提交阶段(height:H,round:R) | 这时每个节点要广播自己的预提交选票并监听和收集pre-commit的投票消息，如果验证节点同意该区块，那么他将广播同意该区块的预提交信息。 | 进入下一轮提议阶段(height:H,round:R+1) |
| 提交阶段(height:H)           | 当一个validator节点收集到的 pre-commit 同意票数超过2/3时，说明这个block 是得到了大多数人统同意，可以确认把这个block写入本地的区块链，追加到末尾，即完成commit。同时区块高度加一，proposer提议人节点索引也增1， 开始提议新的区块 |                   提议阶段(height:H+1) |

在正常流程中共识算法包括 提议 ，投票，锁。 上面只分析了提议和投票，锁在拜占庭节点数少于节点总数的1/3的情况下Tmcore中的锁机制保证了不可能有两个验证者在同一高度提交(commit)了两个不同的(block)区块，锁机制确保了在当前高度验证者的下一轮预投票或者预提交依赖于这一轮的预投票或者预提交。

当有单节点故障的情况下，Tm网络中至少要4个验证者节点，每个验证者拥有一对非对称密钥，其中私钥用来进行数字签名，公钥用来标识自己的身份ID。验证者们从公共的初始状态开始，初始状态包含了一份验证者列表。所有的提议和投票都需要各自的私钥签名，便于其他验证者进行公钥验证。



#### P2P协议

Tendermint_P2P.md

