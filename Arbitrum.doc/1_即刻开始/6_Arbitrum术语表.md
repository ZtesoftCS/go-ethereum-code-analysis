# 6_Arbitrum术语表


* ArbOS：L2『操作系统』，能够无需信任地处理系统级操作
* ArbGas：Arbitrum上计量燃气价格的单位，以以太币计价，是Arbitrum的原生货币。ArbGas有点像L1以太坊上的Gas，不过在计算时有一些因子的差别。（详见[1_洞悉Arbitrum/ArbGas和费用](../2_深入理解协议/1_洞悉Arbitrum.md#ArbGas和费用)。）
* Arbitrum Full Node：Arbitrum全节点。记录并追踪Arbitrum链的状态并接受来自用户RPC调用的网络节点。类似于L1以太坊上的非挖矿节点。
* Aggregator：聚合器。一种Arbitrum全节点，也会接收用户的交易并批量提交。
* Assertion：断言。一种由验证者做出的关于链上合约之后行为的声明。在断言未确认之前都认为是待定状态。
* Arbitrum链：一条基于Arbitrum运行的链，包含了一些合约。同时可以存在很多Arbitrum链。
* AVM：Arbitrum虚拟机
* Token Bridge：代币桥。在以太坊和Arbitrum上的一系列合约，可以无需信任地在L1和L2间转移各种代币。
* Chain Factory：链工厂。运行于以太坊上的合约，当调用时会创建新的Arbitrum链
* Chain state：链状态。一条Arbitrum链在特定历史时间上的状态。链状态对应着一系列已发布的断言，以及哪些断言被仲裁最终接受。
* Challenge：挑战。当两名质押者不认同某断言，他们就会进入挑战。挑战的仲裁者是EthBridge。最终一名质押者会赢得比赛，输家的质押资金会被没收，其中一半奖励给赢家，另一半被销毁。
* Client：客户端。一个运行于用户电脑上的程序，通常在浏览器中。它与Arbitrum链上的合约进行交互并提供用户界面。
* Confirmation：确认。Arbitrum链最终决定选择某一结点作为其链的历史。当一个结点确认后，任何从L2撤回到L1上的资金都会被放行。
* EthBridge：一组运行在以太坊上的合约，起着Arbitrum链记录者和执法者的角色。
* Inbox：收件箱。保管着一系列由客户端发送至Arbitrum链上的各种合约的信息。每个收件箱都由以太坊上的EthBridge管理。
* Outbox：发件箱。一个L1合约，负责追踪外流的（从Arbitrum到以太坊）信息。其中包括提现，在确认后用户可领取资金。
* Outbox Entry：发件箱入口。一定时间段内外流信息的梅克尔树根，储存于发件箱中。
* Staker：质押者。为Arbitrum链的某一结点进行担保的人，质押物为以太币。为错误的结点质押会导致质押资金被没收。在质押结果确认后诚实的质押者可以拿回自己的资金。
* Sequencer：序列器。一个有权在收件箱中对一定时间内的交易进行重排序的节点，由此可以为客户提供亚区块时间的软性确认。
* Validator：验证者。质押资金并参与可争议断言的人。既可以主动发起断言更新状态，也可以监控其他验证者的断言并对错误断言进行挑战。
* 虚拟机：一个运行在Arbitrum链上的程序，追踪L2链上所有合约的状态以及以太币和代币的充值。


← [5_Rollup基础](5_Rollup基础.md)

→ [洞悉Arbitrum](../2_深入理解协议/1_洞悉Arbitrum.md)








