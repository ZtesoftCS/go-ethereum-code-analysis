### cmd包概述


* geth

 主要Ethereum CLI客户端。它是Ethereum网络（以太坊主网，测试网络或私有网）的入口点，使用此命令可以使节点作为full node（默认），或者archive node（保留所有历史状态）或light node（检索数据实时）运行。 其他进程可以通过暴露在HTTP，WebSocket和/或IPC传输之上的JSON RPC端点作为通向Ethereum网络的网关使用。 geth --help或者CLI Wiki page查看更多信息。

* abigen

一个源代码生成器，它将Ethereum智能合约定义(代码) 转换 为易于使用的，编译时类型安全的Go package。 如果合约字节码也available的话，它可以在普通的Ethereum智能合约ABI上扩展功能。 然而，它也能编译Solidity源文件，使开发更加精简。 有关详细信息可以请参阅Native DApps wiki页面。

* bootnode

此Ethereum客户端实现的剥离版本只参与 网络节点发现 协议，但不运行任何更高级别的应用协议。 它可以用作轻量级引导节点，以帮助在私有网络中查找peers。

* disasm

字节码反汇编器将EVM（Ethereum Virtual Machine）字节码转换成更加用户友好的汇编式操作码（例如“echo”6001“。

* evm

能够在可配置环境和执行模式下运行字节码片段的Developer utility版本的的EVM（Ethereum Virtual Machine）。 其目的是允许对EVM操作码进行封装，细粒度的调试（例如evm-code 60ff60ff -debug）。

* gethrpctest

开发者通用工具，用来支持ethereum/rpc-test的测试套件，这个测试套件是用来验证与Ethereum JSON RPC规范的基准一致性，可以查阅test suite's readme中的细节。

* rlpdump

开发者通用工具，用来把二进制RLP (Recursive Length Prefix) (Ethereum 协议中用于网络及一致性的数据编码) 转换成用户友好的分层表示。

* swarm

swarm守护进程和工具，这是swarm网络的进入点，swarm --help可以查看命令行选项及子命令，在https://swarm-guide.readthedocs.io查看swarm文档
