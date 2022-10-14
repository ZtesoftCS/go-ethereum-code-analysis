#EVM 分析

> EVM 不能被重用，非线程安全

BlockContext 结构体：为 EVM 提供辅助信息。一旦提供，不应更改。

```
// Context 为EVM提供辅助信息。一旦提供，不应更改。
type BlockContext struct {
	// CanTransfer 返回 账户是否拥有足够的以太币以执行转账	CanTransfer CanTransferFunc
	// Transfer 转账函数，将以太币从一个账户转到另一个账户
	Transfer TransferFunc
	// GetHash 返回n对应的哈希
	GetHash GetHashFunc

	// Message information
	Origin   common.Address // Provides information for ORIGIN
	GasPrice *big.Int       // Provides information for GASPRICE

	// Block information
	Coinbase    common.Address // Provides information for COINBASE
	GasLimit    uint64         // Provides information for GASLIMIT
	BlockNumber *big.Int       // Provides information for NUMBER
	Time        *big.Int       // Provides information for TIME
	Difficulty  *big.Int       // Provides information for DIFFICULTY
	BaseFee     *big.Int       // Provides information for BASEFEE
	Random      *common.Hash   // Provides information for PREVRANDAO
}
```

> state_processor.Process 开始执行交易处理，就是在那里为入口进入到 evm 的执行的，具体见[core-state-process-analysis.md](core-state-process-analysis.md)

##EVM 的实现
以太坊的 EVM 整个完全是自己实现的，能够直接执行 Solidity 字节码，没有使用任何第三方运行时。
运行过程是同步的，没有启用 go 协程。

1. evm 最终是调用 Interpreter 运行字节码；
2. Interpreter.go 实现运行处理；解析出操作码后，通过 JumpTable 获取操作码对应的函数运行，并维护 pc 计数器、处理返回值等；
3. jump_table.go 定义了操作码的跳转映射；
4. instructions.go 实现每一个操作码的具体的处理；
5. opcodes.go 中定义了操作码常量

对于 EVM 的测试，以太坊将测试代码放在了 core\vm\runtime 目录下，提供了供测试用的运行时及测试用例。
测试用例的示例如：

```
func TestExecute(t *testing.T) {
	ret, _, err := Execute([]byte{
		byte(vm.PUSH1), 10,
		byte(vm.PUSH1), 0,
		byte(vm.MSTORE),
		byte(vm.PUSH1), 32,
		byte(vm.PUSH1), 0,
		byte(vm.RETURN),
	}, nil, nil)
	if err != nil {
		t.Fatal("didn't expect error", err)
	}

	num := new(big.Int).SetBytes(ret)
	if num.Cmp(big.NewInt(10)) != 0 {
		t.Error("Expected 10, got", num)
	}
}
```

#合约数据的存储
参考：[分享 | 来自 10 年经验的大咖对以太坊数据存储的思考与解读](http://www.blockchainbrother.com/article/805)
