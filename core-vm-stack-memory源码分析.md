vm使用了stack.go里面的对象Stack来作为虚拟机的堆栈。memory代表了虚拟机里面使用的内存对象。

## stack
比较简单，就是用1024个big.Int的定长数组来作为堆栈的存储。

构造

	// stack is an object for basic stack operations. Items popped to the stack are
	// expected to be changed and modified. stack does not take care of adding newly
	// initialised objects.
	type Stack struct {
		data []*big.Int
	}
	
	func newstack() *Stack {
		return &Stack{data: make([]*big.Int, 0, 1024)}
	}

push操作 

	func (st *Stack) push(d *big.Int) { //追加到最末尾
		// NOTE push limit (1024) is checked in baseCheck
		//stackItem := new(big.Int).Set(d)
		//st.data = append(st.data, stackItem)
		st.data = append(st.data, d)
	}
	func (st *Stack) pushN(ds ...*big.Int) {
		st.data = append(st.data, ds...)
	}

pop操作


	func (st *Stack) pop() (ret *big.Int) { //从最末尾取出。
		ret = st.data[len(st.data)-1]
		st.data = st.data[:len(st.data)-1]
		return
	}
交换元素的值操作，还有这种操作？
	
	func (st *Stack) swap(n int) { 交换堆栈顶的元素和离栈顶n距离的元素的值。
		st.data[st.len()-n], st.data[st.len()-1] = st.data[st.len()-1], st.data[st.len()-n]
	}

dup操作 像复制指定位置的值到堆顶

	func (st *Stack) dup(pool *intPool, n int) {
		st.push(pool.get().Set(st.data[st.len()-n]))
	}

peek 操作. 偷看栈顶元素

	func (st *Stack) peek() *big.Int {
		return st.data[st.len()-1]
	}
Back 偷看指定位置的元素

	// Back returns the n'th item in stack
	func (st *Stack) Back(n int) *big.Int {
		return st.data[st.len()-n-1]
	}

require 保证堆栈元素的数量要大于等于n.

	func (st *Stack) require(n int) error {
		if st.len() < n {
			return fmt.Errorf("stack underflow (%d <=> %d)", len(st.data), n)
		}
		return nil
	}

## intpool
非常简单. 就是256大小的 big.int的池,用来加速bit.Int的分配
	
	var checkVal = big.NewInt(-42)
	
	const poolLimit = 256
	
	// intPool is a pool of big integers that
	// can be reused for all big.Int operations.
	type intPool struct {
		pool *Stack
	}
	
	func newIntPool() *intPool {
		return &intPool{pool: newstack()}
	}
	
	func (p *intPool) get() *big.Int {
		if p.pool.len() > 0 {
			return p.pool.pop()
		}
		return new(big.Int)
	}
	func (p *intPool) put(is ...*big.Int) {
		if len(p.pool.data) > poolLimit {
			return
		}
	
		for _, i := range is {
			// verifyPool is a build flag. Pool verification makes sure the integrity
			// of the integer pool by comparing values to a default value.
			if verifyPool {
				i.Set(checkVal)
			}
	
			p.pool.push(i)
		}
	}

## memory

构造, memory的存储就是byte[]. 还有一个lastGasCost的记录.
	
	type Memory struct {
		store       []byte
		lastGasCost uint64
	}
	
	func NewMemory() *Memory {
		return &Memory{}
	}

使用首先需要使用Resize分配空间

	// Resize resizes the memory to size
	func (m *Memory) Resize(size uint64) {
		if uint64(m.Len()) < size {
			m.store = append(m.store, make([]byte, size-uint64(m.Len()))...)
		}
	}

然后使用Set来设置值

	// Set sets offset + size to value
	func (m *Memory) Set(offset, size uint64, value []byte) {
		// length of store may never be less than offset + size.
		// The store should be resized PRIOR to setting the memory
		if size > uint64(len(m.store)) {
			panic("INVALID memory: store empty")
		}
	
		// It's possible the offset is greater than 0 and size equals 0. This is because
		// the calcMemSize (common.go) could potentially return 0 when size is zero (NO-OP)
		if size > 0 {
			copy(m.store[offset:offset+size], value)
		}
	}
Get来取值, 一个是获取拷贝, 一个是获取指针.
	
	// Get returns offset + size as a new slice
	func (self *Memory) Get(offset, size int64) (cpy []byte) {
		if size == 0 {
			return nil
		}
	
		if len(self.store) > int(offset) {
			cpy = make([]byte, size)
			copy(cpy, self.store[offset:offset+size])
	
			return
		}
	
		return
	}
	
	// GetPtr returns the offset + size
	func (self *Memory) GetPtr(offset, size int64) []byte {
		if size == 0 {
			return nil
		}
	
		if len(self.store) > int(offset) {
			return self.store[offset : offset+size]
		}
	
		return nil
	}


## 一些额外的帮助函数 在stack_table.go里面

	
	func makeStackFunc(pop, push int) stackValidationFunc {
		return func(stack *Stack) error {
			if err := stack.require(pop); err != nil {
				return err
			}
	
			if stack.len()+push-pop > int(params.StackLimit) {
				return fmt.Errorf("stack limit reached %d (%d)", stack.len(), params.StackLimit)
			}
			return nil
		}
	}
	
	func makeDupStackFunc(n int) stackValidationFunc {
		return makeStackFunc(n, n+1)
	}
	
	func makeSwapStackFunc(n int) stackValidationFunc {
		return makeStackFunc(n, n)
	}


