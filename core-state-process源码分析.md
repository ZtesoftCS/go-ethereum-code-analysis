## StateTransition
状态转换模型



	/*
	The State Transitioning Model
	状态转换模型
	A state transition is a change made when a transaction is applied to the current world state
	状态转换 是指用当前的world state来执行交易，并改变当前的world state
	The state transitioning model does all all the necessary work to work out a valid new state root.
	状态转换做了所有所需的工作来产生一个新的有效的state root
	1) Nonce handling  Nonce 处理
	2) Pre pay gas     预先支付Gas
	3) Create a new state object if the recipient is \0*32 如果接收人是空，那么创建一个新的state object
	4) Value transfer  转账
	== If contract creation ==
	  4a) Attempt to run transaction data 尝试运行输入的数据
	  4b) If valid, use result as code for the new state object 如果有效，那么用运行的结果作为新的state object的code
	== end ==
	5) Run Script section 运行脚本部分
	6) Derive new state root 导出新的state root
	*/
	type StateTransition struct {
		gp         *GasPool   //用来追踪区块内部的Gas的使用情况
		msg        Message		// Message Call
		gas        uint64
		gasPrice   *big.Int		// gas的价格
		initialGas *big.Int		// 最开始的gas
		value      *big.Int		// 转账的值
		data       []byte		// 输入数据
		state      vm.StateDB	// StateDB
		evm        *vm.EVM		// 虚拟机
	}
	
	// Message represents a message sent to a contract.
	type Message interface {
		From() common.Address
		//FromFrontier() (common.Address, error)
		To() *common.Address	// 
	
		GasPrice() *big.Int  // Message 的 GasPrice
		Gas() *big.Int		//message 的 GasLimit
		Value() *big.Int
	
		Nonce() uint64
		CheckNonce() bool
		Data() []byte
	}


构造
	
	// NewStateTransition initialises and returns a new state transition object.
	func NewStateTransition(evm *vm.EVM, msg Message, gp *GasPool) *StateTransition {
		return &StateTransition{
			gp:         gp,
			evm:        evm,
			msg:        msg,
			gasPrice:   msg.GasPrice(),
			initialGas: new(big.Int),
			value:      msg.Value(),
			data:       msg.Data(),
			state:      evm.StateDB,
		}
	}


执行Message
	
	// ApplyMessage computes the new state by applying the given message
	// against the old state within the environment.
	// ApplyMessage 通过应用给定的Message 和状态来生成新的状态
	// ApplyMessage returns the bytes returned by any EVM execution (if it took place),
	// the gas used (which includes gas refunds) and an error if it failed. An error always
	// indicates a core error meaning that the message would always fail for that particular
	// state and would never be accepted within a block.
	// ApplyMessage返回由任何EVM执行（如果发生）返回的字节，
	// 使用的Gas（包括Gas退款），如果失败则返回错误。 一个错误总是表示一个核心错误，
	// 意味着这个消息对于这个特定的状态将总是失败，并且永远不会在一个块中被接受。
	func ApplyMessage(evm *vm.EVM, msg Message, gp *GasPool) ([]byte, *big.Int, bool, error) {
		st := NewStateTransition(evm, msg, gp)
	
		ret, _, gasUsed, failed, err := st.TransitionDb()
		return ret, gasUsed, failed, err
	}

TransitionDb
	
	// TransitionDb will transition the state by applying the current message and returning the result
	// including the required gas for the operation as well as the used gas. It returns an error if it
	// failed. An error indicates a consensus issue.
	// TransitionDb 
	func (st *StateTransition) TransitionDb() (ret []byte, requiredGas, usedGas *big.Int, failed bool, err error) {
		if err = st.preCheck(); err != nil {
			return
		}
		msg := st.msg
		sender := st.from() // err checked in preCheck
	
		homestead := st.evm.ChainConfig().IsHomestead(st.evm.BlockNumber)
		contractCreation := msg.To() == nil // 如果msg.To是nil 那么认为是一个合约创建
	
		// Pay intrinsic gas
		// TODO convert to uint64
		// 计算最开始的Gas  g0
		intrinsicGas := IntrinsicGas(st.data, contractCreation, homestead)
		if intrinsicGas.BitLen() > 64 {
			return nil, nil, nil, false, vm.ErrOutOfGas
		}
		if err = st.useGas(intrinsicGas.Uint64()); err != nil {
			return nil, nil, nil, false, err
		}
	
		var (
			evm = st.evm
			// vm errors do not effect consensus and are therefor
			// not assigned to err, except for insufficient balance
			// error.
			vmerr error
		)
		if contractCreation { //如果是合约创建， 那么调用evm的Create方法
			ret, _, st.gas, vmerr = evm.Create(sender, st.data, st.gas, st.value)
		} else {
			// Increment the nonce for the next transaction
			// 如果是方法调用。那么首先设置sender的nonce。
			st.state.SetNonce(sender.Address(), st.state.GetNonce(sender.Address())+1)
			ret, st.gas, vmerr = evm.Call(sender, st.to().Address(), st.data, st.gas, st.value)
		}
		if vmerr != nil {
			log.Debug("VM returned with error", "err", vmerr)
			// The only possible consensus-error would be if there wasn't
			// sufficient balance to make the transfer happen. The first
			// balance transfer may never fail.
			if vmerr == vm.ErrInsufficientBalance {
				return nil, nil, nil, false, vmerr
			}
		}
		requiredGas = new(big.Int).Set(st.gasUsed()) // 计算被使用的Gas数量
	
		st.refundGas()  //计算Gas的退费 会增加到 st.gas上面。 所以矿工拿到的是退税后的
		st.state.AddBalance(st.evm.Coinbase, new(big.Int).Mul(st.gasUsed(), st.gasPrice)) // 给矿工增加收入。
		// requiredGas和gasUsed的区别一个是没有退税的， 一个是退税了的。
		// 看上面的调用 ApplyMessage直接丢弃了requiredGas, 说明返回的是退税了的。
		return ret, requiredGas, st.gasUsed(), vmerr != nil, err
	}

关于g0的计算，在黄皮书上由详细的介绍
和黄皮书有一定出入的部分在于if contractCreation && homestead {igas.SetUint64(params.TxGasContractCreation) 这是因为 Gtxcreate+Gtransaction = TxGasContractCreation

	func IntrinsicGas(data []byte, contractCreation, homestead bool) *big.Int {
		igas := new(big.Int)
		if contractCreation && homestead {
			igas.SetUint64(params.TxGasContractCreation)
		} else {
			igas.SetUint64(params.TxGas)
		}
		if len(data) > 0 {
			var nz int64
			for _, byt := range data {
				if byt != 0 {
					nz++
				}
			}
			m := big.NewInt(nz)
			m.Mul(m, new(big.Int).SetUint64(params.TxDataNonZeroGas))
			igas.Add(igas, m)
			m.SetInt64(int64(len(data)) - nz)
			m.Mul(m, new(big.Int).SetUint64(params.TxDataZeroGas))
			igas.Add(igas, m)
		}
		return igas
	}


执行前的检查

	func (st *StateTransition) preCheck() error {
		msg := st.msg
		sender := st.from()
	
		// Make sure this transaction's nonce is correct
		if msg.CheckNonce() {
			nonce := st.state.GetNonce(sender.Address())
			// 当前本地的nonce 需要和 msg的Nonce一样 不然就是状态不同步了。
			if nonce < msg.Nonce() {
				return ErrNonceTooHigh
			} else if nonce > msg.Nonce() {
				return ErrNonceTooLow
			}
		}
		return st.buyGas()
	}

buyGas， 实现Gas的预扣费，  首先就扣除你的GasLimit * GasPrice的钱。 然后根据计算完的状态在退还一部分。

	func (st *StateTransition) buyGas() error {
		mgas := st.msg.Gas()
		if mgas.BitLen() > 64 {
			return vm.ErrOutOfGas
		}
	
		mgval := new(big.Int).Mul(mgas, st.gasPrice)
	
		var (
			state  = st.state
			sender = st.from()
		)
		if state.GetBalance(sender.Address()).Cmp(mgval) < 0 {
			return errInsufficientBalanceForGas
		}
		if err := st.gp.SubGas(mgas); err != nil { // 从区块的gaspool里面减去， 因为区块是由GasLimit限制整个区块的Gas使用的。 
			return err
		}
		st.gas += mgas.Uint64()
	
		st.initialGas.Set(mgas)
		state.SubBalance(sender.Address(), mgval)
		// 从账号里面减去 GasLimit * GasPrice
		return nil
	}
		

退税，退税是为了奖励大家运行一些能够减轻区块链负担的指令， 比如清空账户的storage. 或者是运行suicide命令来清空账号。
	
	func (st *StateTransition) refundGas() {
		// Return eth for remaining gas to the sender account,
		// exchanged at the original rate.
		sender := st.from() // err already checked
		remaining := new(big.Int).Mul(new(big.Int).SetUint64(st.gas), st.gasPrice)
		// 首先把用户还剩下的Gas还回去。
		st.state.AddBalance(sender.Address(), remaining)
	
		// Apply refund counter, capped to half of the used gas.
		// 然后退税的总金额不会超过用户Gas总使用的1/2。 
		uhalf := remaining.Div(st.gasUsed(), common.Big2)
		refund := math.BigMin(uhalf, st.state.GetRefund())
		st.gas += refund.Uint64()
		// 把退税的金额加到用户账户上。
		st.state.AddBalance(sender.Address(), refund.Mul(refund, st.gasPrice))
	
		// Also return remaining gas to the block gas counter so it is
		// available for the next transaction.
		// 同时也把退税的钱还给gaspool给下个交易腾点Gas空间。
		st.gp.AddGas(new(big.Int).SetUint64(st.gas))
	}


## StateProcessor
StateTransition是用来处理一个一个的交易的。那么StateProcessor就是用来处理区块级别的交易的。

结构和构造
	
	// StateProcessor is a basic Processor, which takes care of transitioning
	// state from one point to another.
	//
	// StateProcessor implements Processor.
	type StateProcessor struct {
		config *params.ChainConfig // Chain configuration options
		bc     *BlockChain         // Canonical block chain
		engine consensus.Engine    // Consensus engine used for block rewards
	}
	
	// NewStateProcessor initialises a new StateProcessor.
	func NewStateProcessor(config *params.ChainConfig, bc *BlockChain, engine consensus.Engine) *StateProcessor {
		return &StateProcessor{
			config: config,
			bc:     bc,
			engine: engine,
		}
	}


Process，这个方法会被blockchain调用。
	
	// Process processes the state changes according to the Ethereum rules by running
	// the transaction messages using the statedb and applying any rewards to both
	// the processor (coinbase) and any included uncles.
	// Process 根据以太坊规则运行交易信息来对statedb进行状态改变，以及奖励挖矿者或者是其他的叔父节点。
	// Process returns the receipts and logs accumulated during the process and
	// returns the amount of gas that was used in the process. If any of the
	// transactions failed to execute due to insufficient gas it will return an error.
	// Process返回执行过程中累计的收据和日志，并返回过程中使用的Gas。 如果由于Gas不足而导致任何交易执行失败，将返回错误。
	func (p *StateProcessor) Process(block *types.Block, statedb *state.StateDB, cfg vm.Config) (types.Receipts, []*types.Log, *big.Int, error) {
		var (
			receipts     types.Receipts
			totalUsedGas = big.NewInt(0)
			header       = block.Header()
			allLogs      []*types.Log
			gp           = new(GasPool).AddGas(block.GasLimit())
		)
		// Mutate the the block and state according to any hard-fork specs
		// DAO 事件的硬分叉处理 
		if p.config.DAOForkSupport && p.config.DAOForkBlock != nil && p.config.DAOForkBlock.Cmp(block.Number()) == 0 {
			misc.ApplyDAOHardFork(statedb)
		}
		// Iterate over and process the individual transactions
		for i, tx := range block.Transactions() {
			statedb.Prepare(tx.Hash(), block.Hash(), i)
			receipt, _, err := ApplyTransaction(p.config, p.bc, nil, gp, statedb, header, tx, totalUsedGas, cfg)
			if err != nil {
				return nil, nil, nil, err
			}
			receipts = append(receipts, receipt)
			allLogs = append(allLogs, receipt.Logs...)
		}
		// Finalize the block, applying any consensus engine specific extras (e.g. block rewards)
		p.engine.Finalize(p.bc, header, statedb, block.Transactions(), block.Uncles(), receipts)
		// 返回收据 日志 总的Gas使用量和nil
		return receipts, allLogs, totalUsedGas, nil
	}

ApplyTransaction
	
	// ApplyTransaction attempts to apply a transaction to the given state database
	// and uses the input parameters for its environment. It returns the receipt
	// for the transaction, gas used and an error if the transaction failed,
	// indicating the block was invalid.
	ApplyTransaction尝试将事务应用于给定的状态数据库，并使用其环境的输入参数。 
	//它返回事务的收据，使用的Gas和错误，如果交易失败，表明块是无效的。
	
	func ApplyTransaction(config *params.ChainConfig, bc *BlockChain, author *common.Address, gp *GasPool, statedb *state.StateDB, header *types.Header, tx *types.Transaction, usedGas *big.Int, cfg vm.Config) (*types.Receipt, *big.Int, error) {
		// 把交易转换成Message 
		// 这里如何验证消息确实是Sender发送的。 TODO
		msg, err := tx.AsMessage(types.MakeSigner(config, header.Number))
		if err != nil {
			return nil, nil, err
		}
		// Create a new context to be used in the EVM environment
		// 每一个交易都创建了新的虚拟机环境。
		context := NewEVMContext(msg, header, bc, author)
		// Create a new environment which holds all relevant information
		// about the transaction and calling mechanisms.
		vmenv := vm.NewEVM(context, statedb, config, cfg)
		// Apply the transaction to the current state (included in the env)
		_, gas, failed, err := ApplyMessage(vmenv, msg, gp)
		if err != nil {
			return nil, nil, err
		}
	
		// Update the state with pending changes
		// 求得中间状态
		var root []byte
		if config.IsByzantium(header.Number) {
			statedb.Finalise(true)
		} else {
			root = statedb.IntermediateRoot(config.IsEIP158(header.Number)).Bytes()
		}
		usedGas.Add(usedGas, gas)
	
		// Create a new receipt for the transaction, storing the intermediate root and gas used by the tx
		// based on the eip phase, we're passing wether the root touch-delete accounts.
		// 创建一个收据, 用来存储中间状态的root, 以及交易使用的gas
		receipt := types.NewReceipt(root, failed, usedGas)
		receipt.TxHash = tx.Hash()
		receipt.GasUsed = new(big.Int).Set(gas)
		// if the transaction created a contract, store the creation address in the receipt.
		// 如果是创建合约的交易.那么我们把创建地址存储到收据里面.
		if msg.To() == nil {
			receipt.ContractAddress = crypto.CreateAddress(vmenv.Context.Origin, tx.Nonce())
		}
	
		// Set the receipt logs and create a bloom for filtering
		receipt.Logs = statedb.GetLogs(tx.Hash())
		receipt.Bloom = types.CreateBloom(types.Receipts{receipt})
		// 拿到所有的日志并创建日志的布隆过滤器.
		return receipt, gas, err
	}
