建议先大致了解黄皮书中 Appendix B. Recursive Length Prefix 相关内容

辅助阅读可以参考：[https://segmentfault.com/a/1190000011763339](https://segmentfault.com/a/1190000011763339)
或直接检索 rlp 相关内容

从工程角度上说， rlp 分为两类数据定义，并且其中一类可以递归包含另外一类即：

```
T ≡ L∪B // T 由 L 或 B 组成
L ≡ {t:t=(t[0],t[1],...) ∧ \forall n<‖t‖ t[n]∈T} // L 中的任何成员都属于 T （T 又是由 L 或 B 组成：注意递归定义）
B ≡ {b:b=(b[0],b[1],...) ∧ \forall n<‖b‖ b[n]∈O} // T 中的任何成员都属于 O
```

其中的

* [\forall](https://en.wikibooks.org/wiki/LaTeX/Mathematics#Symbols) 参考 LaTeX 语法标准
* O 被定义为一个 bytes 集合
* 如果把 T 想象成为一个树形的数据结构，则 B 为树叶，其只包含 byte 序列结构；而 L 为树干，包含多个 B 或者其自身

就是大家依托 B 的基础之上形成 T 与 L 的递归定义：整个 RLP 由 T 组成， T 包含 L 和 B ，而 L 的成员又都是 T 。这样的递归定义，可以描述很灵活的数据结构

在具体编码中，也只需要通过头一个 byte 的编码空间即可区分这些结构上的差异：

```
B编码规则：叶子
RLP_B0 [0000 0001, 0111 1111] 如果为不为 0 且小于 128[1000 0000] 的 byte 则不需要头，内容即为编码
RLP_B1 [1000 0000, 1011 0111] 如果 byte 内容的长度小于 56 ， 即 55[0011 0111] ，则将其长度按大端字节序压缩到一个 byte 中，并加上 128 形成头，再接上实际的内容
RLP_B2 (1011 0111, 1100 0000) 对于更长的内容，则在第 2 个 bit 不为 1 的空间内，描述内容长度的长度。其空间为 (192-1)[1011 1111]-(183+1)[1011 1000]=7[0111] ，即长度需要小于 2^(7*8) 是一个巨大到不可能被用完的数
L编码规则：树枝
RLP_L1 [1100 0000, 1111 0111) 如果为多个上面的编码内容组合的情况，通过第 2 个 bit 为 1 表达。后续的内容长度小于 56 ， 即 55[0011 0111] 则先将长度压缩后放到第一个 byte 中（加 192[1100 0000]），再接上实际的内容
RLP_L2 [1111 0111, 1111 1111] 对于更长的内容，则在剩余的空间内，描述内容长度的长度。其空间为 255[1111 1111]-247[1111 0111]=8[1000]，即长度需要小于 2^(8*8) 同样是一个巨大到不可能被用完的数
```

请复制下列代码至具有文本折叠功能的编辑器中进行代码查阅（推荐 Notepad++ 将所有的 github 引用格式下的函数进行适当折叠，便于从全局进行逻辑理解）

```code
[/rlp/encode_test.go#TestEncode](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode_test.go#L272)
func TestEncode(t *testing.T) {
	runEncTests(t, func(val interface{}) ([]byte, error) {
		b := new(bytes.Buffer)
		err := Encode(b, val)
		[/rlp/encode.go#Encode](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L80)
		func Encode(w io.Writer, val interface{}) error {
			if outer, ok := w.(*encbuf); ok {
				// Encode was called by some type's EncodeRLP.
				// Avoid copying by writing to the outer encbuf directly.
				return outer.encode(val)
			}
			eb := encbufPool.Get().(*encbuf)
			[/rlp/encode.go#encbuf](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L121)
			type encbuf struct { // 有状态的编码器
				str     []byte      // string data, contains everything except list headers // 已编码的内容，不包含 L 头
				lheads  []*listhead // all list headers // 当前递归层级的 L 头信息数组
				
				[/rlp/encode.go#listhead](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L128)
				type listhead struct {
					offset int // index of this header in string data // TODO
					size   int // total size of encoded data (including list headers) // TODO
				}
				
				lhsize  int         // sum of sizes of all encoded list headers // 当前递归层级的 L 头信息长度 TODO
				sizebuf []byte      // 9-byte auxiliary buffer for uint encoding // 用于 size 编码的 buf 其中的 buf[0] 为头，余下的 8 byte 供 size 编码 // TODO
			}

			defer encbufPool.Put(eb)
			eb.reset()
			if err := eb.encode(val); err != nil { // encbuf.encode 作为 B 编码（内部）函数， eb 为有状态的 encbuf
				[/rlp/encode.go#encbuf.encode](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L181) 函数具体实现为
				func (w *encbuf) encode(val interface{}) error {
				rval := reflect.ValueOf(val)
				ti, err := cachedTypeInfo(rval.Type(), tags{}) // 从缓存中获取当前类型的内容编码函数
				if err != nil {
					return err
				}
				return ti.writer(rval, w) // 执行函数
				[/rlp/encode.go#writeUint](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L392)
				func writeUint(val reflect.Value, w *encbuf) error {
					i := val.Uint()
					if i == 0 {
						w.str = append(w.str, 0x80) // 防止编码意义上的全0异常格式，将 0 编码为 0x80
					} else if i < 128 { // 实现 RLP_B0 编码逻辑
						// fits single byte
						w.str = append(w.str, byte(i))
					} else { // 实现 RLP_B1 编码逻辑：因为 uint 的 byte 长度只有 8 不会超过 56
						// TODO: encode int to w.str directly
						s := putint(w.sizebuf[1:], i) // 将 uint 高位为零的bit，按byte粒度去除，并返回去除后的 byte 数
						w.sizebuf[0] = 0x80 + byte(s) // 对于 uint 最长为 64 bit/8 byte，所以将长度压缩到 byte[0,256) 是完全足够的
						w.str = append(w.str, w.sizebuf[:s+1]...) // 将 sizebuf 中的所有可用 byte 作为编码后的内容输出
					}
					return nil
				}
				[/rlp/encode.go#writeUint](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L461)
				func writeString(val reflect.Value, w *encbuf) error {
					s := val.String()
					if len(s) == 1 && s[0] <= 0x7f { // 0x7f=127 实现 RLP_B0 编码逻辑，注意空字符串会走下面的 else
						// fits single byte, no string header
						w.str = append(w.str, s[0])
					} else {
						w.encodeStringHeader(len(s)) // 实现 RLP_B1, RLP_B2 编码逻辑
						[/rlp/encode.go#encbuf.encodeStringHeader](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L191)
						func (w *encbuf) encodeStringHeader(size int) {
							if size < 56 { // 实现 RLP_B1 编码逻辑
								w.str = append(w.str, 0x80+byte(size))
							} else { // 实现 RLP_B2 编码逻辑
								// TODO: encode to w.str directly
								sizesize := putint(w.sizebuf[1:], uint64(size)) // 将 size 按大端字节序，按 byte 粒度去掉高位的 [0000 0000] 并范围 byte 个数
								w.sizebuf[0] = 0xB7 + byte(sizesize) // 0xB7[1011 0111]183 将头部长度的长度编码进第一个 byte 中
								w.str = append(w.str, w.sizebuf[:sizesize+1]...) // 完成头部的长度信息编码
							}
						}
						w.str = append(w.str, s...) // 将实际内容追加在头部之后
					}
					return nil
				}
				[/rlp/encode.go#makeStructWriter](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L529)
				func makeStructWriter(typ reflect.Type) (writer, error) {
					fields, err := structFields(typ) // 通过反射获取字段信息，以便逐条编码
					if err != nil {
						return nil, err
					}
					writer := func(val reflect.Value, w *encbuf) error {
						lh := w.list() // 创建一个 listhead 存储对象
						[/rlp/encode.go#encbuf.list](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L212)
						func (w *encbuf) list() *listhead {
							lh := &listhead{offset: len(w.str), size: w.lhsize} // 创建一个新的 listhead 对象，并将当前的编码总长度作为 offset ，当前的头部总长度 lhsize 作为 size
							w.lheads = append(w.lheads, lh)
							return lh // 加入头部序列后返回给 listEnd 使用
						}
						for _, f := range fields {
							if err := f.info.writer(val.Field(f.index), w); err != nil {
								return err
							}
						}
						w.listEnd(lh) // 设置好 listhead 对象的值
						[/rlp/encode.go#encbuf.listEnd](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L218)
						func (w *encbuf) listEnd(lh *listhead) {
							lh.size = w.size() - lh.offset - lh.size // 新的头部size等于新增加的编码长度减去？TODO
							if lh.size < 56 {
								w.lhsize += 1 // length encoded into kind tag
							} else {
								w.lhsize += 1 + intsize(uint64(lh.size))
							}
						}
						return nil
					}
					return writer, nil
				}
			}
				return err
			}
			return eb.toWriter(w) // encbuf.toWriter 作为 L 头部编码（内部）函数
			[/rlp/encode.go#encbuf.toWriter](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L249)
			func (w *encbuf) toWriter(out io.Writer) (err error) {
				strpos := 0
				for _, head := range w.lheads { // 对于无 lheads 数据情况下，直接忽略下面的头部编码逻辑
					// write string data before header
					if head.offset-strpos > 0 {
						n, err := out.Write(w.str[strpos:head.offset])
						strpos += n
						if err != nil {
							return err
						}
					}
					// write the header
					enc := head.encode(w.sizebuf)
					[/rlp/encode.go#encbuf.listhead.encode](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L135)
					func (head *listhead) encode(buf []byte) []byte {
						// 转换二进制
						// 0xC0 192: 1100 0000
						// 0xF7 247: 1111 0111
						return buf[:puthead(buf, 0xC0, 0xF7, uint64(head.size))]
						[/rlp/encode.go#puthead](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L150)
						func puthead(buf []byte, smalltag, largetag byte, size uint64) int {
							if size < 56 {
								buf[0] = smalltag + byte(size)
								return 1
							} else {
								sizesize := putint(buf[1:], size)
								buf[0] = largetag + byte(sizesize)
								return sizesize + 1
							}
						}
					}
					if _, err = out.Write(enc); err != nil {
						return err
					}
				}
				if strpos < len(w.str) { // strpos 为 0 必然成立，直接将有头部编码的内容作为最终的输出
					// write string data after the last list header
					_, err = out.Write(w.str[strpos:])
				}
				return err
			}
		}
		return b.Bytes(), err
	})
}
```



# 测试文档格式附录

明白RLP大体意义后，建议从测试代码开始阅读，对于
[/rlp/encode_test.go](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode_test.go#L272)
中的代码段

	func TestEncode(t *testing.T) {
		runEncTests(t, func(val interface{}) ([]byte, error) {
			b := new(bytes.Buffer)
			err := Encode(b, val)
			return b.Bytes(), err
		})
	}

err := Encode(b, val) 调用的 Encode 作为编码的入口函数，具体实现在
[/rlp/encode.go#Encode](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L80)中

	func Encode(w io.Writer, val interface{}) error {
		if outer, ok := w.(*encbuf); ok {
			// Encode was called by some type's EncodeRLP.
			// Avoid copying by writing to the outer encbuf directly.
			return outer.encode(val)
		}
		eb := encbufPool.Get().(*encbuf)
		defer encbufPool.Put(eb)
		eb.reset()
		if err := eb.encode(val); err != nil { // encbuf.encode 作为内容编码（内部）函数
			return err
		}
		return eb.toWriter(w) // encbuf.toWriter 作为头部编码（内部）函数
	}

[/rlp/encode.go#encbuf.encode](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L181) 函数具体实现为

	func (w *encbuf) encode(val interface{}) error {
		rval := reflect.ValueOf(val)
		ti, err := cachedTypeInfo(rval.Type(), tags{}) // 从缓存中获取当前类型的内容编码函数
		if err != nil {
			return err
		}
		return ti.writer(rval, w) // 执行函数
	}

我们忽略缓存类型与编码函数的获取及生成函数 cachedTypeInfo ，将关注点直接移到具体类型的内容编码函数

普通的 uint 编码实现在[/rlp/encode.go#writeUint](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L392)处

	func writeUint(val reflect.Value, w *encbuf) error {
		i := val.Uint()
		if i == 0 {
			w.str = append(w.str, 0x80) // 防止编码意义上的全0异常格式，将 0 编码为 0x80
		} else if i < 128 {
			// fits single byte
			w.str = append(w.str, byte(i))
		} else {
			// TODO: encode int to w.str directly
			s := putint(w.sizebuf[1:], i) // 将 uint 高位为零的bit，按byte粒度去除，并返回去除后的 byte 数
			w.sizebuf[0] = 0x80 + byte(s) // 对于 uint 最长为 64 bit/8 byte，所以将长度压缩到 byte[0,256) 是完全足够的
			w.str = append(w.str, w.sizebuf[:s+1]...) // 将 sizebuf 中的所有可用 byte 作为编码后的内容输出
		}
		return nil
	}

那么在 [/rlp/encode.go#Encode](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L80) 中的后续逻辑 [/rlp/encode.go#encbuf.toWriter](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L249) 中

	func (w *encbuf) toWriter(out io.Writer) (err error) {
		strpos := 0
		for _, head := range w.lheads { // 对于无 lheads 数据情况下，直接忽略下面的头部编码逻辑
			// write string data before header
			if head.offset-strpos > 0 {
				n, err := out.Write(w.str[strpos:head.offset])
				strpos += n
				if err != nil {
					return err
				}
			}
			// write the header
			enc := head.encode(w.sizebuf)
			if _, err = out.Write(enc); err != nil {
				return err
			}
		}
		if strpos < len(w.str) { // strpos 为 0 必然成立，直接将有头部编码的内容作为最终的输出
			// write string data after the last list header
			_, err = out.Write(w.str[strpos:])
		}
		return err
	}

对于 string 编码 [/rlp/encode.go#writeString](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L461) 与 uint 类似，不包含头部的编码信息。可以参考黄皮书，就不赘述

	func writeString(val reflect.Value, w *encbuf) error {
		s := val.String()
		if len(s) == 1 && s[0] <= 0x7f {
			// fits single byte, no string header
			w.str = append(w.str, s[0])
		} else {
			w.encodeStringHeader(len(s))
			w.str = append(w.str, s...)
		}
		return nil
	}

[/rlp/encode.go#makeStructWriter](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L529) 函数包含了较复杂的

	func makeStructWriter(typ reflect.Type) (writer, error) {
		fields, err := structFields(typ)
		if err != nil {
			return nil, err
		}
		writer := func(val reflect.Value, w *encbuf) error {
			lh := w.list() // 创建一个 listhead 存储对象
			for _, f := range fields {
				if err := f.info.writer(val.Field(f.index), w); err != nil {
					return err
				}
			}
			w.listEnd(lh) // 设置好 listhead 对象的值
			return nil
		}
		return writer, nil
	}

[/rlp/encode.go#encbuf.list/listEnd](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L212)

	func (w *encbuf) list() *listhead {
		lh := &listhead{offset: len(w.str), size: w.lhsize} // 创建一个新的 listhead 对象，并将当前的编码总长度作为 offset ，当前的头部总长度 lhsize 作为 size
		w.lheads = append(w.lheads, lh)
		return lh // 加入头部序列后返回给 listEnd 使用
	}

	func (w *encbuf) listEnd(lh *listhead) {
		lh.size = w.size() - lh.offset - lh.size // 新的头部size等于新增加的编码长度减去？TODO
		if lh.size < 56 {
			w.lhsize += 1 // length encoded into kind tag
		} else {
			w.lhsize += 1 + intsize(uint64(lh.size))
		}
	}

[encbuf.toWriter](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L248) 函数具体实现为

	func (w *encbuf) toWriter(out io.Writer) (err error) {
		strpos := 0
		for _, head := range w.lheads {
			// write string data before header
			if head.offset-strpos > 0 {
				n, err := out.Write(w.str[strpos:head.offset])
				strpos += n
				if err != nil {
					return err
				}
			}
			// write the header
			enc := head.encode(w.sizebuf)
			if _, err = out.Write(enc); err != nil {
				return err
			}
		}
		if strpos < len(w.str) {
			// write string data after the last list header
			_, err = out.Write(w.str[strpos:])
		}
		return err
	}

https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L135

	func (head *listhead) encode(buf []byte) []byte {
		// 转换二进制
		// 0xC0 192: 1100 0000
		// 0xF7 247: 1111 0111
		return buf[:puthead(buf, 0xC0, 0xF7, uint64(head.size))]
	}

https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L150

	func puthead(buf []byte, smalltag, largetag byte, size uint64) int {
		if size < 56 {
			buf[0] = smalltag + byte(size)
			return 1
		} else {
			sizesize := putint(buf[1:], size)
			buf[0] = largetag + byte(sizesize)
			return sizesize + 1
		}
	}

...



goroutine 1 [running]:
main.f(0x0)
        D:/coding/ztesoft/golang/src/defer2.go:30 +0x1b8
main.f(0x1)
        D:/coding/ztesoft/golang/src/defer2.go:32 +0x187
main.f(0x2)
        D:/coding/ztesoft/golang/src/defer2.go:32 +0x187
main.f(0x3)
        D:/coding/ztesoft/golang/src/defer2.go:32 +0x187
main.main()
        D:/coding/ztesoft/golang/src/defer2.go:26 +0xc9
exit status 2


 0 1 2 3 4 5  6 7 8
+---+
|
+---+

```flow
st=>start: Start
op=>operation: Your Operation
cond=>condition: Yes or No?
e=>end
st->op->cond
cond(yes)->e
cond(no)->op
```


