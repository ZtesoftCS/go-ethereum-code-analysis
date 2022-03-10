#### MIPS:



#### minigeth:

运行环境：作为源码运行在`MIPS`系统中。

与Geth的不同点: 

1:此有一个oracle来获取stateDB所需要的所有数据。并且将拿到的数据进行hash，放在本地preimages,即 `hash(v)=>v`。

2:其底层的DB为`map[common.Hash][]byte preimages`，其实现了一个底层的Writer方法，使得在进行trieHash时（如对一系列交易进行merkle化生成一个merkle树）。**值得一提的是**,mips编译下，与第一个逻辑不同。preimage的填充由本地获取:

```go
//localtion: minigeth: oracle/embedded_mips.go

func Preimage(hash common.Hash) []byte {
	val, ok := preimages[hash]
	if !ok {
		// load in hash
		preImageHash := byteAt(0xB0001000, 0x20)
		copy(preImageHash, hash.Bytes())

		// used in unicorn emulator to trigger the load
		// in onchain mips, it's instant
    /*
    mipsevm/unicorn.go
    if syscall_no == 4020 {
			oracle_hash, _ := mu.MemRead(0xB0001000, 0x20)
			hash := common.BytesToHash(oracle_hash)
			key := fmt.Sprintf("/tmp/eth/%s", hash)
			value, _ := ioutil.ReadFile(key)

			tmp := []byte{0, 0, 0, 0}
			binary.BigEndian.PutUint32(tmp, uint32(len(value)))
			mu.MemWrite(0xB1000000, tmp)
			mu.MemWrite(0xB1000004, value)

			WriteRam(ram, 0xB1000000, uint32(len(value)))
			value = append(value, 0, 0, 0)
			for i := uint32(0); i < ram[0xB1000000]; i += 4 {
				WriteRam(ram, 0xB1000004+i, binary.BigEndian.Uint32(value[i:i+4]))
			}
    通过unicorn代码逻辑推测其syscall_no为4020，unicorn增加了一个指令钩子:mu.HookAdd(uc.HOOK_INTR, func(mu uc.Unicorn, intno uint32) {}),当调用os.Getpid()方法时，此钩子会读取内存地址[]"0xB1000000","0xB1000020"],拿到想要
    访问的image，并直接从本地文件夹中读取，将读取到的数据长度赋值给内存地址[]"0xB1000000","0xB1000004"],将数据赋值给
    由于规定读取长度&3==0.其为4的倍数，所以数据向后补0,保存在内存地址0xB1000004后
    */
		os.Getpid() //钩子启动

		// ready//此时钩子已经运行完毕
		rawSize := common.CopyBytes(byteAt(0xB1000000, 4))
		size := (int(rawSize[0]) << 24) | (int(rawSize[1]) << 16) | (int(rawSize[2]) << 8) | int(rawSize[3])
		ret := common.CopyBytes(byteAt(0xB1000004, size))

		// this is 20% of the exec instructions, this speedup is always an option
		realhash := crypto.Keccak256Hash(ret)
		if realhash != hash {
			panic("preimage has wrong hash")
		}

		preimages[hash] = ret//缓存
		return ret
	}
	return val
}
//通过内存地址与长度拿到在RAM中的对象
func byteAt(addr uint64, length int) []byte {
	var ret []byte
	bh := (*reflect.SliceHeader)(unsafe.Pointer(&ret))
	bh.Data = uintptr(addr)
	bh.Len = length
	bh.Cap = length
	return ret
}
```



3： 在orcale内部维持了`[8]common.Hash`数组，其用来保存当前oracle的持续性的全局信息: parentblock hash, tx hash, coinbase, unclehash, gaslimit, timestamp, assert block 的状态根，assert block的receiptHash。并将此数据保存在对应的区块文件中：

```go

//localtion: minigeth/oracle/prefetch.go

// put in the start block header
	if startBlock {
		blockHeaderRlp, _ := rlp.EncodeToBytes(blockHeader)
		hash := crypto.Keccak256Hash(blockHeaderRlp)
		preimages[hash] = blockHeaderRlp
		emptyHash := common.Hash{}
		if inputs[0] == emptyHash {
			inputs[0] = hash
		}
		return
	}

	// second block
	if blockHeader.ParentHash != Input(0) {
		fmt.Println(blockHeader.ParentHash, Input(0))
		panic("block transition isn't correct")
	}
	inputs[1] = blockHeader.TxHash
	inputs[2] = blockHeader.Coinbase.Hash()
	inputs[3] = blockHeader.UncleHash
	inputs[4] = common.BigToHash(big.NewInt(int64(blockHeader.GasLimit)))
	inputs[5] = common.BigToHash(big.NewInt(int64(blockHeader.Time)))

	// secret input
	inputs[6] = blockHeader.Root
	inputs[7] = blockHeader.ReceiptHash

	// save the inputs
	saveinput := make([]byte, 0)
	for i := 0; i < len(inputs); i++ {
		saveinput = append(saveinput, inputs[i].Bytes()[:]...)
	}
	key := fmt.Sprintf("/tmp/eth/%d", blockNumber.Uint64()-1)
	ioutil.WriteFile(key, saveinput, 0644)
```



并在unicorn中将其写入对应的内存:

unicorn模式:

```go
//location: mipsevm/unicorn.go

// inputs
	inputFile := fmt.Sprintf("/tmp/eth/%d", 13284469)
	inputs, _ := ioutil.ReadFile(inputFile)
	mu.MemWrite(0xB0000000, inputs)

	LoadMappedFile(fn, ram, 0)
	LoadMappedFile(inputFile, ram, 0xB0000000)
```



内存模式:

```go
//location: mispsevm/main.go

func RunMinigeth(fn string, steps int, debug int) {
	ram := make(map[uint32](uint32))
	LoadMappedFile(fn, ram, 0)
	LoadMappedFile(fmt.Sprintf("/tmp/eth/%d", 13284469), ram, 0xB0000000)
	RunWithRam(ram, steps, debug, nil)
}

```

其两者的差别为:unicorn模式为适配EVM的unicorn系统，而内存模式是为了辅助在EVM合约中运行unicorn系统。此两者都为unicorn系统，用来比较合约状态与实际状态的差异。

当两者的RAM的代码为minigeth代码时，其内部将会运行minigeth。



#### mipsevm：mips系统：

其实现了两套系统，一套为原生的mips增加一些钩子。另一套为合约实现。

合约实现：

contracts/MIPSMemory.sol:

实现在mips内存读写功能，支持用户提供mips运行所需要的所有数据。其内部维持了一个merkleTrie，将所有的KV对保存在内部并运算其root。其的序列化golang实现如下:

```go
//location: mipsevm/trie.go

func RamToTrie(ram map[uint32](uint32)) common.Hash {
	mt := trie.NewStackTrie(PreimageKeyValueWriter{})

	sram := make([]uint64, len(ram))

	i := 0
	for k, v := range ram {
		sram[i] = (uint64(k) << 32) | uint64(v)
		i += 1
	}
	sort.Slice(sram, func(i, j int) bool { return sram[i] < sram[j] })

	for _, kv := range sram {
		k, v := uint32(kv>>32), uint32(kv)
		k >>= 2
		//fmt.Printf("insert %x = %x\n", k, v)
		tk := make([]byte, 4)
		tv := make([]byte, 4)
		binary.BigEndian.PutUint32(tk, k)
		binary.BigEndian.PutUint32(tv, v)
		mt.Update(tk, tv)
	}
	mt.Commit()
	/*fmt.Println("ram hash", mt.Hash())
	fmt.Println("hash count", len(Preimages))
	parseNode(mt.Hash(), 0)*/
	return mt.Hash()
}
```



contracts/Challenge.sol: 

用来寻找两个参与者一件不一致的状态，并初始化状态到合约实现的MIPS内存，其内存布局与mipsevm中的内存布局一致。



contract/MIPS.sol:

MIPS系统运行的逻辑，由其实现了MIPS系统，其内存布局与逻辑对标mipsevm/unicorn.go。

其中的insn模型如下[6byte]op,[5byte]rs,[5byte]rt,[5byte]rd,[5byte]shift,[6byte]funct。其内存为MIPSMemory的实现。



模拟运行：

在本地提供合约所需要的所有信息，由于MIPS合约中，当我们不生成MIPSMemory时，其读写操作直接使用sload，所以改写本地StateDB的sload方法，将其直接hook到早已生成好的内存布局中即可。如写操作：

```go
//location: mipsevm/minievm.go

func (s *StateDB) SetState(fakeaddr common.Address, key, value common.Hash) {
	if s.useRealState {
		if s.Debug >= 2 {
			fmt.Println("SetState", fakeaddr, key, value)
		}
		s.RealState[key] = value//此处用来测试使用K，V对，即合约中的merkle化。
		return
	}

	//fmt.Println("SetState", addr, key, value)
	addr := bytesTo32(key.Bytes())
	dat := bytesTo32(value.Bytes())

	if addr == 0xc0000080 {
		s.seenWrite = true
	}

	if s.Debug >= 2 {
		fmt.Println("HOOKED WRITE!  ", fmt.Sprintf("%x = %x (at step %d)", addr, dat, s.PcCount))
	}

	WriteRam(s.Ram, addr, dat)//直接写向本地维持的RAM。
}
```



而本地的RAM根据运行的代码进行初始化。

```go
//location:	misevm/main.go

	LoadMappedFile(fn, ram, 0)//加载二进制文件fn，在内存偏移量为0开始写入RAM，此RAM的结构为 map[uint32]uint32,即映射存储地址与值的关系。

	LoadMappedFile(fmt.Sprintf("/tmp/eth/%d", 13284469), ram, 0xB0000000)//由于系统默认将块等不变信息保存在以0xB0000000起始的位置中，此处将块信息填充到内存偏移0xB0000000。


// 0xdb7df598
	from := common.Address{}
	to := common.HexToAddress("0x1337")
	bytecode := GetBytecode(true)
	statedb.Bytecodes[to] = bytecode

	input := crypto.Keccak256Hash([]byte("Steps(bytes32,uint256)")).Bytes()[:4]
	input = append(input, common.BigToHash(common.Big0).Bytes()...)
	input = append(input, common.BigToHash(big.NewInt(int64(steps))).Bytes()...)
	//调用MIPS合约的Step方法
	
contract := vm.NewContract(vm.AccountRef(from), vm.AccountRef(to), common.Big0, gas)
	contract.SetCallCode(&to, crypto.Keccak256Hash(bytecode), bytecode)//设置MIPS合约的代码

	_, err := interpreter.Run(contract, input, false)//run
```



由于要测试merkleTrie所组成的内存模型，所以便有了`real map[Hash]Hash`,其代表真正的状态map，相当于原生的storage trie的底层DB。



---------

内存布局:

11.1

| 名称         | 地址范围                  | 属性                                                         |
| ------------ | ------------------------- | ------------------------------------------------------------ |
| inputHash    | [0x0x30000000,0x30000020] | inputHash=hash(parantHash,txHash,coinbase,uncleHash,gaslimit,timestamp) |
| parantHash   |                           | 运行区块的父区块                                             |
| txHash       |                           | 运行区块的交易的交易trie根                                   |
| coinbase     |                           | 运行区块的矿工地址                                           |
| uncleHash    |                           | 运行区块的父节点的兄弟节点                                   |
| gaslimit     |                           | 运行区块的的gaslimit                                         |
| timestamp    |                           | 运行区块的时间戳                                             |
|              |                           |                                                              |
| magic        | [0x30000800,0x30000804]   | 充当哨兵作用以确保输出执行动作发生，即交易正常执行完成并输出。 |
| newroot      | [0x30000804,0x30000824]   | 由上一个区块运行成功后的新的状态根                           |
| receiptHash  | [0x30000824,0x30000844]   | 由上一个区块运行成功后的新块的收据trie根                     |
|              |                           |                                                              |
| preImageHash | [0x30001000,0x30001020]   | hash(data)                                                   |
| dataLength   | [0x31000000,0x31000004]   | len(data)                                                    |
| data         | [0x31000004,]             |                                                              |


