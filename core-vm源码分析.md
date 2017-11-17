## contract.go
contract 代表了以太坊 state database里面的一个合约。包含了合约代码，调用参数。


结构
	
	// ContractRef is a reference to the contract's backing object
	type ContractRef interface {
		Address() common.Address
	}
	
	// AccountRef implements ContractRef.
	//
	// Account references are used during EVM initialisation and
	// it's primary use is to fetch addresses. Removing this object
	// proves difficult because of the cached jump destinations which
	// are fetched from the parent contract (i.e. the caller), which
	// is a ContractRef.
	type AccountRef common.Address
	
	// Address casts AccountRef to a Address
	func (ar AccountRef) Address() common.Address { return (common.Address)(ar) }
	
	// Contract represents an ethereum contract in the state database. It contains
	// the the contract code, calling arguments. Contract implements ContractRef
	type Contract struct {
		// CallerAddress is the result of the caller which initialised this
		// contract. However when the "call method" is delegated this value
		// needs to be initialised to that of the caller's caller.
		// CallerAddress是初始化这个合约的人。 如果是delegate，这个值被设置为调用者的调用者。
		CallerAddress common.Address
		caller        ContractRef
		self          ContractRef
	
		jumpdests destinations // result of JUMPDEST analysis.  JUMPDEST指令的分析
	
		Code     []byte  //代码
		CodeHash common.Hash  //代码的HASH
		CodeAddr *common.Address //代码地址
		Input    []byte     // 入参
	
		Gas   uint64  		// 合约还有多少Gas
		value *big.Int      
	
		Args []byte  //好像没有使用
	
		DelegateCall bool  
	}

构造
	
	// NewContract returns a new contract environment for the execution of EVM.
	func NewContract(caller ContractRef, object ContractRef, value *big.Int, gas uint64) *Contract {
		c := &Contract{CallerAddress: caller.Address(), caller: caller, self: object, Args: nil}
	
		if parent, ok := caller.(*Contract); ok {
			// Reuse JUMPDEST analysis from parent context if available.
			// 如果 caller 是一个合约，说明是合约调用了我们。 jumpdests设置为caller的jumpdests
			c.jumpdests = parent.jumpdests
		} else {
			c.jumpdests = make(destinations)
		}
	
		// Gas should be a pointer so it can safely be reduced through the run
		// This pointer will be off the state transition
		c.Gas = gas
		// ensures a value is set
		c.value = value
	
		return c
	}

AsDelegate将合约设置为委托调用并返回当前合同（用于链式调用）

	// AsDelegate sets the contract to be a delegate call and returns the current
	// contract (for chaining calls)
	func (c *Contract) AsDelegate() *Contract {
		c.DelegateCall = true
		// NOTE: caller must, at all times be a contract. It should never happen
		// that caller is something other than a Contract.
		parent := c.caller.(*Contract)
		c.CallerAddress = parent.CallerAddress
		c.value = parent.value
	
		return c
	}
		
GetOp  用来获取下一跳指令
	
	// GetOp returns the n'th element in the contract's byte array
	func (c *Contract) GetOp(n uint64) OpCode {
		return OpCode(c.GetByte(n))
	}
	
	// GetByte returns the n'th byte in the contract's byte array
	func (c *Contract) GetByte(n uint64) byte {
		if n < uint64(len(c.Code)) {
			return c.Code[n]
		}
	
		return 0
	}

	// Caller returns the caller of the contract.
	//
	// Caller will recursively call caller when the contract is a delegate
	// call, including that of caller's caller.
	func (c *Contract) Caller() common.Address {
		return c.CallerAddress
	}
UseGas使用Gas。 
	
	// UseGas attempts the use gas and subtracts it and returns true on success
	func (c *Contract) UseGas(gas uint64) (ok bool) {
		if c.Gas < gas {
			return false
		}
		c.Gas -= gas
		return true
	}
	
	// Address returns the contracts address
	func (c *Contract) Address() common.Address {
		return c.self.Address()
	}
	
	// Value returns the contracts value (sent to it from it's caller)
	func (c *Contract) Value() *big.Int {
		return c.value
	}
SetCode	，SetCallCode 设置代码。

	// SetCode sets the code to the contract
	func (self *Contract) SetCode(hash common.Hash, code []byte) {
		self.Code = code
		self.CodeHash = hash
	}
	
	// SetCallCode sets the code of the contract and address of the backing data
	// object
	func (self *Contract) SetCallCode(addr *common.Address, hash common.Hash, code []byte) {
		self.Code = code
		self.CodeHash = hash
		self.CodeAddr = addr
	}


## evm.go

结构


	// Context provides the EVM with auxiliary information. Once provided
	// it shouldn't be modified.
	// 上下文为EVM提供辅助信息。 一旦提供，不应该修改。
	type Context struct {
		// CanTransfer returns whether the account contains
		// sufficient ether to transfer the value
		// CanTransfer 函数返回账户是否有足够的ether用来转账
		CanTransfer CanTransferFunc
		// Transfer transfers ether from one account to the other
		// Transfer 用来从一个账户给另一个账户转账
		Transfer TransferFunc
		// GetHash returns the hash corresponding to n
		// GetHash用来返回入参n对应的hash值
		GetHash GetHashFunc
	
		// Message information
		// 用来提供Origin的信息 sender的地址
		Origin   common.Address // Provides information for ORIGIN
		// 用来提供GasPrice信息
		GasPrice *big.Int       // Provides information for GASPRICE
	
		// Block information
		Coinbase    common.Address // Provides information for COINBASE
		GasLimit    *big.Int       // Provides information for GASLIMIT
		BlockNumber *big.Int       // Provides information for NUMBER
		Time        *big.Int       // Provides information for TIME
		Difficulty  *big.Int       // Provides information for DIFFICULTY
	}
	
	// EVM is the Ethereum Virtual Machine base object and provides
	// the necessary tools to run a contract on the given state with
	// the provided context. It should be noted that any error
	// generated through any of the calls should be considered a
	// revert-state-and-consume-all-gas operation, no checks on
	// specific errors should ever be performed. The interpreter makes
	// sure that any errors generated are to be considered faulty code.
	// EVM是以太坊虚拟机基础对象，并提供必要的工具，以使用提供的上下文运行给定状态的合约。
	// 应该指出的是，任何调用产生的任何错误都应该被认为是一种回滚修改状态和消耗所有GAS操作，
	// 不应该执行对具体错误的检查。 解释器确保生成的任何错误都被认为是错误的代码。
	// The EVM should never be reused and is not thread safe.
	type EVM struct {
		// Context provides auxiliary blockchain related information
		Context
		// StateDB gives access to the underlying state
		StateDB StateDB
		// Depth is the current call stack
		// 当前的调用堆栈
		depth int
	
		// chainConfig contains information about the current chain
		// 包含了当前的区块链的信息
		chainConfig *params.ChainConfig
		// chain rules contains the chain rules for the current epoch
		chainRules params.Rules
		// virtual machine configuration options used to initialise the
		// evm.
		vmConfig Config
		// global (to this context) ethereum virtual machine
		// used throughout the execution of the tx.
		interpreter *Interpreter
		// abort is used to abort the EVM calling operations
		// NOTE: must be set atomically
		abort int32
	}

构造函数
	
	// NewEVM retutrns a new EVM . The returned EVM is not thread safe and should
	// only ever be used *once*.
	func NewEVM(ctx Context, statedb StateDB, chainConfig *params.ChainConfig, vmConfig Config) *EVM {
		evm := &EVM{
			Context:     ctx,
			StateDB:     statedb,
			vmConfig:    vmConfig,
			chainConfig: chainConfig,
			chainRules:  chainConfig.Rules(ctx.BlockNumber),
		}
	
		evm.interpreter = NewInterpreter(evm, vmConfig)
		return evm
	}
	
	// Cancel cancels any running EVM operation. This may be called concurrently and
	// it's safe to be called multiple times.
	func (evm *EVM) Cancel() {
		atomic.StoreInt32(&evm.abort, 1)
	}


合约创建 Create 会创建一个新的合约。

	
	// Create creates a new contract using code as deployment code.
	func (evm *EVM) Create(caller ContractRef, code []byte, gas uint64, value *big.Int) (ret []byte, contractAddr common.Address, leftOverGas uint64, err error) {
	
		// Depth check execution. Fail if we're trying to execute above the
		// limit.
		if evm.depth > int(params.CallCreateDepth) {
			return nil, common.Address{}, gas, ErrDepth
		}
		if !evm.CanTransfer(evm.StateDB, caller.Address(), value) {
			return nil, common.Address{}, gas, ErrInsufficientBalance
		}
		// Ensure there's no existing contract already at the designated address
		// 确保特定的地址没有合约存在
		nonce := evm.StateDB.GetNonce(caller.Address())
		evm.StateDB.SetNonce(caller.Address(), nonce+1)
	
		contractAddr = crypto.CreateAddress(caller.Address(), nonce)
		contractHash := evm.StateDB.GetCodeHash(contractAddr)
		if evm.StateDB.GetNonce(contractAddr) != 0 || (contractHash != (common.Hash{}) && contractHash != emptyCodeHash) { //如果已经存在
			return nil, common.Address{}, 0, ErrContractAddressCollision
		}
		// Create a new account on the state
		snapshot := evm.StateDB.Snapshot()  //创建一个StateDB的快照，以便回滚
		evm.StateDB.CreateAccount(contractAddr) //创建账户
		if evm.ChainConfig().IsEIP158(evm.BlockNumber) {
			evm.StateDB.SetNonce(contractAddr, 1) //设置nonce
		}
		evm.Transfer(evm.StateDB, caller.Address(), contractAddr, value)  //转账
	
		// initialise a new contract and set the code that is to be used by the
		// E The contract is a scoped evmironment for this execution context
		// only.
		contract := NewContract(caller, AccountRef(contractAddr), value, gas)
		contract.SetCallCode(&contractAddr, crypto.Keccak256Hash(code), code)
	
		if evm.vmConfig.NoRecursion && evm.depth > 0 {
			return nil, contractAddr, gas, nil
		}
		ret, err = run(evm, snapshot, contract, nil) //执行合约的初始化代码
		// check whether the max code size has been exceeded
		// 检查初始化生成的代码的长度不超过限制
		maxCodeSizeExceeded := evm.ChainConfig().IsEIP158(evm.BlockNumber) && len(ret) > params.MaxCodeSize
		// if the contract creation ran successfully and no errors were returned
		// calculate the gas required to store the code. If the code could not
		// be stored due to not enough gas set an error and let it be handled
		// by the error checking condition below.
		//如果合同创建成功并且没有错误返回，则计算存储代码所需的GAS。 如果由于没有足够的GAS而导致代码不能被存储设置错误，并通过下面的错误检查条件来处理。
		if err == nil && !maxCodeSizeExceeded {
			createDataGas := uint64(len(ret)) * params.CreateDataGas
			if contract.UseGas(createDataGas) {
				evm.StateDB.SetCode(contractAddr, ret)
			} else {
				err = ErrCodeStoreOutOfGas
			}
		}
	
		// When an error was returned by the EVM or when setting the creation code
		// above we revert to the snapshot and consume any gas remaining. Additionally
		// when we're in homestead this also counts for code storage gas errors.
		// 当错误返回我们回滚修改，
		if maxCodeSizeExceeded || (err != nil && (evm.ChainConfig().IsHomestead(evm.BlockNumber) || err != ErrCodeStoreOutOfGas)) {
			evm.StateDB.RevertToSnapshot(snapshot)
			if err != errExecutionReverted {
				contract.UseGas(contract.Gas)
			}
		}
		// Assign err if contract code size exceeds the max while the err is still empty.
		if maxCodeSizeExceeded && err == nil {
			err = errMaxCodeSizeExceeded
		}
		return ret, contractAddr, contract.Gas, err
	}


Call方法, 无论我们转账或者是执行合约代码都会调用到这里， 同时合约里面的call指令也会执行到这里。

	
	// Call executes the contract associated with the addr with the given input as
	// parameters. It also handles any necessary value transfer required and takes
	// the necessary steps to create accounts and reverses the state in case of an
	// execution error or failed value transfer.
	
	// Call 执行与给定的input作为参数与addr相关联的合约。 
	// 它还处理所需的任何必要的转账操作，并采取必要的步骤来创建帐户
	// 并在任意错误的情况下回滚所做的操作。

	func (evm *EVM) Call(caller ContractRef, addr common.Address, input []byte, gas uint64, value *big.Int) (ret []byte, leftOverGas uint64, err error) {
		if evm.vmConfig.NoRecursion && evm.depth > 0 {
			return nil, gas, nil
		}
	
		// Fail if we're trying to execute above the call depth limit
		//  调用深度最多1024
		if evm.depth > int(params.CallCreateDepth) {
			return nil, gas, ErrDepth
		}
		// Fail if we're trying to transfer more than the available balance
		// 查看我们的账户是否有足够的金钱。
		if !evm.Context.CanTransfer(evm.StateDB, caller.Address(), value) {
			return nil, gas, ErrInsufficientBalance
		}
	
		var (
			to       = AccountRef(addr)
			snapshot = evm.StateDB.Snapshot()
		)
		if !evm.StateDB.Exist(addr) { // 查看指定地址是否存在
			// 如果地址不存在，查看是否是 native go的合约， native go的合约在
			// contracts.go 文件里面
			precompiles := PrecompiledContractsHomestead
			if evm.ChainConfig().IsByzantium(evm.BlockNumber) {
				precompiles = PrecompiledContractsByzantium
			}
			if precompiles[addr] == nil && evm.ChainConfig().IsEIP158(evm.BlockNumber) && value.Sign() == 0 {
				// 如果不是指定的合约地址， 并且value的值为0那么返回正常，而且这次调用没有消耗Gas
				return nil, gas, nil
			}
			// 负责在本地状态创建addr
			evm.StateDB.CreateAccount(addr)
		}
		// 执行转账
		evm.Transfer(evm.StateDB, caller.Address(), to.Address(), value)
	
		// initialise a new contract and set the code that is to be used by the
		// E The contract is a scoped environment for this execution context
		// only.
		contract := NewContract(caller, to, value, gas)
		contract.SetCallCode(&addr, evm.StateDB.GetCodeHash(addr), evm.StateDB.GetCode(addr))
	
		ret, err = run(evm, snapshot, contract, input)
		// When an error was returned by the EVM or when setting the creation code
		// above we revert to the snapshot and consume any gas remaining. Additionally
		// when we're in homestead this also counts for code storage gas errors.
		if err != nil {
			evm.StateDB.RevertToSnapshot(snapshot)
			if err != errExecutionReverted { 
				// 如果是由revert指令触发的错误，因为ICO一般设置了人数限制或者资金限制
				// 在大家抢购的时候很可能会触发这些限制条件，导致被抽走不少钱。这个时候
				// 又不能设置比较低的GasPrice和GasLimit。因为要速度快。
				// 那么不会使用剩下的全部Gas，而是只会使用代码执行的Gas
				// 不然会被抽走 GasLimit *GasPrice的钱，那可不少。
				contract.UseGas(contract.Gas)
			}
		}
		return ret, contract.Gas, err
	}


剩下的三个函数 CallCode, DelegateCall, 和 StaticCall，这三个函数不能由外部调用，只能由Opcode触发。


CallCode

	// CallCode differs from Call in the sense that it executes the given address'
	// code with the caller as context.
	// CallCode与Call不同的地方在于它使用caller的context来执行给定地址的代码。
	
	func (evm *EVM) CallCode(caller ContractRef, addr common.Address, input []byte, gas uint64, value *big.Int) (ret []byte, leftOverGas uint64, err error) {
		if evm.vmConfig.NoRecursion && evm.depth > 0 {
			return nil, gas, nil
		}
	
		// Fail if we're trying to execute above the call depth limit
		if evm.depth > int(params.CallCreateDepth) {
			return nil, gas, ErrDepth
		}
		// Fail if we're trying to transfer more than the available balance
		if !evm.CanTransfer(evm.StateDB, caller.Address(), value) {
			return nil, gas, ErrInsufficientBalance
		}
	
		var (
			snapshot = evm.StateDB.Snapshot()
			to       = AccountRef(caller.Address())  //这里是最不同的地方 to的地址被修改为caller的地址了 而且没有转账的行为
		)
		// initialise a new contract and set the code that is to be used by the
		// E The contract is a scoped evmironment for this execution context
		// only.
		contract := NewContract(caller, to, value, gas)
		contract.SetCallCode(&addr, evm.StateDB.GetCodeHash(addr), evm.StateDB.GetCode(addr))
	
		ret, err = run(evm, snapshot, contract, input)
		if err != nil {
			evm.StateDB.RevertToSnapshot(snapshot)
			if err != errExecutionReverted {
				contract.UseGas(contract.Gas)
			}
		}
		return ret, contract.Gas, err
	}

DelegateCall

	// DelegateCall differs from CallCode in the sense that it executes the given address'
	// code with the caller as context and the caller is set to the caller of the caller.
	// DelegateCall 和 CallCode不同的地方在于 caller被设置为 caller的caller
	func (evm *EVM) DelegateCall(caller ContractRef, addr common.Address, input []byte, gas uint64) (ret []byte, leftOverGas uint64, err error) {
		if evm.vmConfig.NoRecursion && evm.depth > 0 {
			return nil, gas, nil
		}
		// Fail if we're trying to execute above the call depth limit
		if evm.depth > int(params.CallCreateDepth) {
			return nil, gas, ErrDepth
		}
	
		var (
			snapshot = evm.StateDB.Snapshot()
			to       = AccountRef(caller.Address()) 
		)
	
		// Initialise a new contract and make initialise the delegate values
		// 标识为AsDelete()
		contract := NewContract(caller, to, nil, gas).AsDelegate() 
		contract.SetCallCode(&addr, evm.StateDB.GetCodeHash(addr), evm.StateDB.GetCode(addr))
	
		ret, err = run(evm, snapshot, contract, input)
		if err != nil {
			evm.StateDB.RevertToSnapshot(snapshot)
			if err != errExecutionReverted {
				contract.UseGas(contract.Gas)
			}
		}
		return ret, contract.Gas, err
	}
	
	// StaticCall executes the contract associated with the addr with the given input
	// as parameters while disallowing any modifications to the state during the call.
	// Opcodes that attempt to perform such modifications will result in exceptions
	// instead of performing the modifications.
	// StaticCall不允许执行任何修改状态的操作，
	
	func (evm *EVM) StaticCall(caller ContractRef, addr common.Address, input []byte, gas uint64) (ret []byte, leftOverGas uint64, err error) {
		if evm.vmConfig.NoRecursion && evm.depth > 0 {
			return nil, gas, nil
		}
		// Fail if we're trying to execute above the call depth limit
		if evm.depth > int(params.CallCreateDepth) {
			return nil, gas, ErrDepth
		}
		// Make sure the readonly is only set if we aren't in readonly yet
		// this makes also sure that the readonly flag isn't removed for
		// child calls.
		if !evm.interpreter.readOnly {
			evm.interpreter.readOnly = true
			defer func() { evm.interpreter.readOnly = false }()
		}
	
		var (
			to       = AccountRef(addr)
			snapshot = evm.StateDB.Snapshot()
		)
		// Initialise a new contract and set the code that is to be used by the
		// EVM. The contract is a scoped environment for this execution context
		// only.
		contract := NewContract(caller, to, new(big.Int), gas)
		contract.SetCallCode(&addr, evm.StateDB.GetCodeHash(addr), evm.StateDB.GetCode(addr))
	
		// When an error was returned by the EVM or when setting the creation code
		// above we revert to the snapshot and consume any gas remaining. Additionally
		// when we're in Homestead this also counts for code storage gas errors.
		ret, err = run(evm, snapshot, contract, input)
		if err != nil {
			evm.StateDB.RevertToSnapshot(snapshot)
			if err != errExecutionReverted {
				contract.UseGas(contract.Gas)
			}
		}
		return ret, contract.Gas, err
	}
