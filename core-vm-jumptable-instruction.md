jumptable. 是一个 [256]operation 的数据结构. 每个下标对应了一种指令, 使用operation来存储了指令对应的处理逻辑, gas消耗, 堆栈验证方法, memory使用的大小等功能.
## jumptable

数据结构operation存储了一条指令的所需要的函数.

	type operation struct {
		// op is the operation function  执行函数
		execute executionFunc
		// gasCost is the gas function and returns the gas required for execution gas消耗函数
		gasCost gasFunc
		// validateStack validates the stack (size) for the operation 堆栈大小验证函数
		validateStack stackValidationFunc
		// memorySize returns the memory size required for the operation 需要的内存大小
		memorySize memorySizeFunc
	
		halts   bool // indicates whether the operation shoult halt further execution 表示操作是否停止进一步执行
		jumps   bool // indicates whether the program counter should not increment 指示程序计数器是否不增加
		writes  bool // determines whether this a state modifying operation 确定这是否是一个状态修改操作
		valid   bool // indication whether the retrieved operation is valid and known 指示检索到的操作是否有效并且已知
		reverts bool // determines whether the operation reverts state (implicitly halts)确定操作是否恢复状态（隐式停止）
		returns bool // determines whether the opertions sets the return data content 确定操作是否设置了返回数据内容
	}

指令集, 下面定义了三种指令集,针对三种不同的以太坊版本, 

var (
	frontierInstructionSet  = NewFrontierInstructionSet()
	homesteadInstructionSet = NewHomesteadInstructionSet()
	byzantiumInstructionSet = NewByzantiumInstructionSet()
)
NewByzantiumInstructionSet 拜占庭版本首先调用NewHomesteadInstructionSet创造了前一个版本的指令,然后增加自己特有的指令.STATICCALL ,RETURNDATASIZE ,RETURNDATACOPY ,REVERT
	
	// NewByzantiumInstructionSet returns the frontier, homestead and
	// byzantium instructions.
	func NewByzantiumInstructionSet() [256]operation {
		// instructions that can be executed during the homestead phase.
		instructionSet := NewHomesteadInstructionSet()
		instructionSet[STATICCALL] = operation{
			execute:       opStaticCall,
			gasCost:       gasStaticCall,
			validateStack: makeStackFunc(6, 1),
			memorySize:    memoryStaticCall,
			valid:         true,
			returns:       true,
		}
		instructionSet[RETURNDATASIZE] = operation{
			execute:       opReturnDataSize,
			gasCost:       constGasFunc(GasQuickStep),
			validateStack: makeStackFunc(0, 1),
			valid:         true,
		}
		instructionSet[RETURNDATACOPY] = operation{
			execute:       opReturnDataCopy,
			gasCost:       gasReturnDataCopy,
			validateStack: makeStackFunc(3, 0),
			memorySize:    memoryReturnDataCopy,
			valid:         true,
		}
		instructionSet[REVERT] = operation{
			execute:       opRevert,
			gasCost:       gasRevert,
			validateStack: makeStackFunc(2, 0),
			memorySize:    memoryRevert,
			valid:         true,
			reverts:       true,
			returns:       true,
		}
		return instructionSet
	}

NewHomesteadInstructionSet

	// NewHomesteadInstructionSet returns the frontier and homestead
	// instructions that can be executed during the homestead phase.
	func NewHomesteadInstructionSet() [256]operation {
		instructionSet := NewFrontierInstructionSet()
		instructionSet[DELEGATECALL] = operation{
			execute:       opDelegateCall,
			gasCost:       gasDelegateCall,
			validateStack: makeStackFunc(6, 1),
			memorySize:    memoryDelegateCall,
			valid:         true,
			returns:       true,
		}
		return instructionSet
	}



## instruction.go 
因为指令很多,所以不一一列出来,  只列举几个例子. 虽然组合起来的功能可以很复杂,但是单个指令来说,还是比较直观的.

	func opPc(pc *uint64, evm *EVM, contract *Contract, memory *Memory, stack *Stack) ([]byte, error) {
		stack.push(evm.interpreter.intPool.get().SetUint64(*pc))
		return nil, nil
	}
	
	func opMsize(pc *uint64, evm *EVM, contract *Contract, memory *Memory, stack *Stack) ([]byte, error) {
		stack.push(evm.interpreter.intPool.get().SetInt64(int64(memory.Len())))
		return nil, nil
	}



## gas_table.go
gas_table返回了各种指令消耗的gas的函数
这个函数的返回值基本上只有errGasUintOverflow 整数溢出的错误.

	func gasBalance(gt params.GasTable, evm *EVM, contract *Contract, stack *Stack, mem *Memory, memorySize uint64) (uint64, error) {
		return gt.Balance, nil
	}
	
	func gasExtCodeSize(gt params.GasTable, evm *EVM, contract *Contract, stack *Stack, mem *Memory, memorySize uint64) (uint64, error) {
		return gt.ExtcodeSize, nil
	}
	
	func gasSLoad(gt params.GasTable, evm *EVM, contract *Contract, stack *Stack, mem *Memory, memorySize uint64) (uint64, error) {
		return gt.SLoad, nil
	}
	
	func gasExp(gt params.GasTable, evm *EVM, contract *Contract, stack *Stack, mem *Memory, memorySize uint64) (uint64, error) {
		expByteLen := uint64((stack.data[stack.len()-2].BitLen() + 7) / 8)
	
		var (
			gas      = expByteLen * gt.ExpByte // no overflow check required. Max is 256 * ExpByte gas
			overflow bool
		)
		if gas, overflow = math.SafeAdd(gas, GasSlowStep); overflow {
			return 0, errGasUintOverflow
		}
		return gas, nil
	}

## interpreter.go  解释器

数据结构
	
	// Config are the configuration options for the Interpreter
	type Config struct {
		// Debug enabled debugging Interpreter options
		Debug bool
		// EnableJit enabled the JIT VM
		EnableJit bool
		// ForceJit forces the JIT VM
		ForceJit bool
		// Tracer is the op code logger
		Tracer Tracer
		// NoRecursion disabled Interpreter call, callcode,
		// delegate call and create.
		NoRecursion bool
		// Disable gas metering
		DisableGasMetering bool
		// Enable recording of SHA3/keccak preimages
		EnablePreimageRecording bool
		// JumpTable contains the EVM instruction table. This
		// may be left uninitialised and will be set to the default
		// table.
		JumpTable [256]operation
	}
	
	// Interpreter is used to run Ethereum based contracts and will utilise the
	// passed evmironment to query external sources for state information.
	// The Interpreter will run the byte code VM or JIT VM based on the passed
	// configuration.
	type Interpreter struct {
		evm      *EVM
		cfg      Config
		gasTable params.GasTable   // 标识了很多操作的Gas价格
		intPool  *intPool
	
		readOnly   bool   // Whether to throw on stateful modifications
		returnData []byte // Last CALL's return data for subsequent reuse 最后一个函数的返回值
	}

构造函数
	
	// NewInterpreter returns a new instance of the Interpreter.
	func NewInterpreter(evm *EVM, cfg Config) *Interpreter {
		// We use the STOP instruction whether to see
		// the jump table was initialised. If it was not
		// we'll set the default jump table.
		// 用一个STOP指令测试JumpTable是否已经被初始化了, 如果没有被初始化,那么设置为默认值
		if !cfg.JumpTable[STOP].valid { 
			switch {
			case evm.ChainConfig().IsByzantium(evm.BlockNumber):
				cfg.JumpTable = byzantiumInstructionSet
			case evm.ChainConfig().IsHomestead(evm.BlockNumber):
				cfg.JumpTable = homesteadInstructionSet
			default:
				cfg.JumpTable = frontierInstructionSet
			}
		}
	
		return &Interpreter{
			evm:      evm,
			cfg:      cfg,
			gasTable: evm.ChainConfig().GasTable(evm.BlockNumber),
			intPool:  newIntPool(),
		}
	}


解释器一共就两个方法enforceRestrictions方法和Run方法.


	
	func (in *Interpreter) enforceRestrictions(op OpCode, operation operation, stack *Stack) error {
		if in.evm.chainRules.IsByzantium {
			if in.readOnly {
				// If the interpreter is operating in readonly mode, make sure no
				// state-modifying operation is performed. The 3rd stack item
				// for a call operation is the value. Transferring value from one
				// account to the others means the state is modified and should also
				// return with an error.
				if operation.writes || (op == CALL && stack.Back(2).BitLen() > 0) {
					return errWriteProtection
				}
			}
		}
		return nil
	}
	
	// Run loops and evaluates the contract's code with the given input data and returns
	// the return byte-slice and an error if one occurred.
	// 用给定的入参循环执行合约的代码，并返回返回的字节片段，如果发生错误则返回错误。
	// It's important to note that any errors returned by the interpreter should be
	// considered a revert-and-consume-all-gas operation. No error specific checks
	// should be handled to reduce complexity and errors further down the in.
	// 重要的是要注意，解释器返回的任何错误都会消耗全部gas。 为了减少复杂性,没有特别的错误处理流程。
	func (in *Interpreter) Run(snapshot int, contract *Contract, input []byte) (ret []byte, err error) {
		// Increment the call depth which is restricted to 1024
		in.evm.depth++
		defer func() { in.evm.depth-- }()
	
		// Reset the previous call's return data. It's unimportant to preserve the old buffer
		// as every returning call will return new data anyway.
		in.returnData = nil
	
		// Don't bother with the execution if there's no code.
		if len(contract.Code) == 0 {
			return nil, nil
		}
	
		codehash := contract.CodeHash // codehash is used when doing jump dest caching
		if codehash == (common.Hash{}) {
			codehash = crypto.Keccak256Hash(contract.Code)
		}
	
		var (
			op    OpCode        // current opcode
			mem   = NewMemory() // bound memory
			stack = newstack()  // local stack
			// For optimisation reason we're using uint64 as the program counter.
			// It's theoretically possible to go above 2^64. The YP defines the PC
			// to be uint256. Practically much less so feasible.
			pc   = uint64(0) // program counter
			cost uint64
			// copies used by tracer
			stackCopy = newstack() // stackCopy needed for Tracer since stack is mutated by 63/64 gas rule 
			pcCopy uint64 // needed for the deferred Tracer
			gasCopy uint64 // for Tracer to log gas remaining before execution
			logged bool // deferred Tracer should ignore already logged steps
		)
		contract.Input = input
	
		defer func() {
			if err != nil && !logged && in.cfg.Debug {
				in.cfg.Tracer.CaptureState(in.evm, pcCopy, op, gasCopy, cost, mem, stackCopy, contract, in.evm.depth, err)
			}
		}()
	
		// The Interpreter main run loop (contextual). This loop runs until either an
		// explicit STOP, RETURN or SELFDESTRUCT is executed, an error occurred during
		// the execution of one of the operations or until the done flag is set by the
		// parent context.
		// 解释器的主要循环， 直到遇到STOP，RETURN，SELFDESTRUCT指令被执行，或者是遇到任意错误，或者说done 标志被父context设置。
		for atomic.LoadInt32(&in.evm.abort) == 0 {
			// Get the memory location of pc
			// 难道下一个需要执行的指令
			op = contract.GetOp(pc)
	
			if in.cfg.Debug {
				logged = false
				pcCopy = uint64(pc)
				gasCopy = uint64(contract.Gas)
				stackCopy = newstack()
				for _, val := range stack.data {
					stackCopy.push(val)
				}
			}
	
			// get the operation from the jump table matching the opcode
			// 通过JumpTable拿到对应的operation
			operation := in.cfg.JumpTable[op]
			// 这里检查了只读模式下面不能执行writes指令
			// staticCall的情况下会设置为readonly模式
			if err := in.enforceRestrictions(op, operation, stack); err != nil {
				return nil, err
			}
	
			// if the op is invalid abort the process and return an error
			if !operation.valid { //检查指令是否非法
				return nil, fmt.Errorf("invalid opcode 0x%x", int(op))
			}
	
			// validate the stack and make sure there enough stack items available
			// to perform the operation
			// 检查是否有足够的堆栈空间。 包括入栈和出栈
			if err := operation.validateStack(stack); err != nil {
				return nil, err
			}
	
			var memorySize uint64
			// calculate the new memory size and expand the memory to fit
			// the operation
			if operation.memorySize != nil { // 计算内存使用量，需要收费
				memSize, overflow := bigUint64(operation.memorySize(stack))
				if overflow {
					return nil, errGasUintOverflow
				}
				// memory is expanded in words of 32 bytes. Gas
				// is also calculated in words.
				if memorySize, overflow = math.SafeMul(toWordSize(memSize), 32); overflow {
					return nil, errGasUintOverflow
				}
			}
	
			if !in.cfg.DisableGasMetering { //这个参数在本地模拟执行的时候比较有用，可以不消耗或者检查GAS执行交易并得到返回结果
				// consume the gas and return an error if not enough gas is available.
				// cost is explicitly set so that the capture state defer method cas get the proper cost
				// 计算gas的Cost 并使用，如果不够，就返回OutOfGas错误。
				cost, err = operation.gasCost(in.gasTable, in.evm, contract, stack, mem, memorySize)
				if err != nil || !contract.UseGas(cost) {
					return nil, ErrOutOfGas
				}
			}
			if memorySize > 0 { //扩大内存范围
				mem.Resize(memorySize)
			}
	
			if in.cfg.Debug {
				in.cfg.Tracer.CaptureState(in.evm, pc, op, gasCopy, cost, mem, stackCopy, contract, in.evm.depth, err)
				logged = true
			}
	
			// execute the operation
			// 执行命令
			res, err := operation.execute(&pc, in.evm, contract, mem, stack)
			// verifyPool is a build flag. Pool verification makes sure the integrity
			// of the integer pool by comparing values to a default value.
			if verifyPool {
				verifyIntegerPool(in.intPool)
			}
			// if the operation clears the return data (e.g. it has returning data)
			// set the last return to the result of the operation.
			if operation.returns { //如果有返回值，那么就设置返回值。 注意只有最后一个返回有效果。
				in.returnData = res
			}
	
			switch {
			case err != nil:
				return nil, err
			case operation.reverts:
				return res, errExecutionReverted
			case operation.halts:
				return res, nil
			case !operation.jumps:
				pc++
			}
		}
		return nil, nil
	}
