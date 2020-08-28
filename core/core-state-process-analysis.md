#以太坊交易执行分析
**说明：**  在go-ethereum-code-analysis目录下已有一些分析，基本涵盖了交易的执行过程。见 [core-state-process源码分析.md](../go-ethereum-code-analysis/core-state-process源码分析.md)  
[core-state源码分析.md](../go-ethereum-code-analysis/core-state源码分析.md)  

在这里，将其整体串起来，从state_processor.Process函数开始，归纳一下其所作的处理。

##1 Process
Process 根据以太坊规则运行交易信息来对statedb进行状态改变，以及奖励挖矿者或者是其他的叔父节点。  
Process返回执行过程中累计的收据和日志，并返回过程中使用的Gas。 如果由于Gas不足而导致任何交易执行失败，将返回错误。  
**处理逻辑：**
~~~
1. 定义及初始化收据、耗费的gas、区块头、日志、gas池等变量；
2. 如果是DAO事件硬分叉相关的处理，则调用misc.ApplyDAOHardFork(statedb)执行处理；
3. 对区块中的每一个交易，进行迭代处理；处理逻辑：
    a. 对当前交易做预处理，设置交易的hash、索引、区块hash，供EVM发布新的状态日志使用；  
    b. 执行ApplyTransaction，获取收据；  
    c. 若上一步出错，中断整个Process，返回错误；
    d. 若正常，累积记录收据及日志。循环进入下一个交易的处理。
4. 调用共识模块做Finalize处理；
5. 返回所有的收据、日志、总共使用的gas。
~~~

##2 ApplyTransaction(1.3.b )
ApplyTransaction尝试将交易应用于给定的状态数据库，并使用输入参数作为其环境。  
它返回交易的收据，使用的Gas和错误，如果交易失败，表明块是无效的。  
**处理逻辑：**  
~~~
1. 将types.Transaction结构变量转为core.Message对象；这过程中会对发送者做签名验证，并获得发送者的地址缓存起来；
2. 创建新的上下文（Context），此上下文将在EVM 环境（EVM environment）中使用；上下文中包含msg，区块头、区块指针、作者（挖矿者、获益者）；  
3. 创建新的EVM environment，其中包括了交易相关的所有信息以及调用机制；  
4. ApplyMessage， 将交易应用于当前的状态中，也就是执行状态转换，新的状态包含在环境对象中；得到执行结果以及花费的gas；
5. 判断是否分叉情况（ `config.IsByzantium(header.Number)` ），如果不是，获取当前的statedb的状态树根哈希；  
6. 创建一个收据, 用来存储中间状态的root, 以及交易使用的gas；  
7. 如果是创建合约的交易，那么我们把创建地址存储到收据里面；  
8. 拿到所有的日志并创建日志的布隆过滤器；返回。
~~~  

##3 ApplyMessage（2.4）
ApplyMessage将交易应用于当前的状态中，代码里就是创建了一个StateTransition然后调用其TransitionDb()方法。
ApplyMessage返回由任何EVM执行（如果发生）返回的字节（但这个返回值在ApplyTransaction中被忽略了），
使用的Gas（包括Gas退款），如果失败则返回错误。 一个错误总是表示一个核心错误，
意味着这个消息对于这个特定的状态将总是失败，并且永远不会在一个块中被接受。

##4 StateTransition.TransitionDb()
~~~
1. 预检查，出错则函数返回；
    a. 检查交易的Nonce值是否合规；
    b. buyGas：根据发送者定的gaslimit和GasPrice，从发送者余额中扣除以太币；从区块gas池中减掉本次gas；并对运行环境做好更新；  
2. 支付固定费用 intrinsic gas；
3. 如果是合约创建， 那么调用evm的Create方法创建新的合约，使用交易的data作为新合约的部署代码；  
4. 否则不是合约创建，增加发送者的Nonce值，然后调用evm.Call执行交易；  
5. 计算并执行退款，将退回的gas对应的以太币退回给交易发送者。
~~~

###4.3 evm.Create创建新的合约
~~~
1. 检查执行深度，若超过params.CallCreateDepth（即1024）就出错返回；刚开始的执行深度为0，肯定继续往下执行；  
2. 检查是否可执行转账，即检查账户余额是否≥要转账的数额；
3. 发送者Nonce加1；
4. 创建合约地址并获取hash，若该合约地址已存在，或不合法（空），则出错返回；
5. 保存statedb快照，然后根据合约地址创建账户；
6. 执行转账evm.Transfer（在statedb中，将value所代表的以太币从发送者账户转到新合约账户）； 
7. 根据发送者、前面创建的合约账户，转账的钱，已用的gas创建并初始化合约；将交易的data作为合约的代码；  
8. 运行前一步创建的合约
9. 判断运行结果是否有错误。如果合约成功运行并且没有错误返回，则计算存储返回数据所需的GAS。 如果由于没有足够的GAS而导致返回值不能被存储则设置错误，并通过下面的错误检查条件来处理。
10. 若EVM返回错误或上述存储返回值出现错误，则回滚到快照的状态，并且消耗完剩下的所有gas。
~~~

###4.4 evm.Call执行交易
Call方法, 无论我们转账或者是执行合约代码都会调用到这里， 同时合约里面的call指令也会执行到这里。  
Call方法和evm.Create的逻辑类似，但少了一些步骤。
~~~
1. 检查是否允许递归执行以及执行深度，若深度超过params.CallCreateDepth（即1024）就出错返回；
2. 检查是否可执行转账，即检查账户余额是否≥要转账的数额；
3. 保存statedb快照，创建接收者账户；
4. 如果接收者在statedb中尚不存在，则执行precompiles预编译，与编译结果为nil时出错返回；无错误则在statedb中创建接收者账户；  
5. 执行转账；
6. 根据发送者、接收者，转账的钱，已用的gas创建并初始化合约；将交易的data作为合约的代码；  
7. 运行前一步创建的合约
8. 若EVM返回错误，则回滚到快照的状态，并且消耗完剩下的所有gas。
~~~

虚拟机中合约的执行另行分析。
