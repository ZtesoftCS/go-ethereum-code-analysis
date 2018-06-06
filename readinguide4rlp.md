建议先大致了解黄皮书中 Appendix B. Recursive Length Prefix 相关内容

辅助阅读可以参考：[https://segmentfault.com/a/1190000011763339](https://segmentfault.com/a/1190000011763339)
或直接检索 rlp 相关内容

明白RLP总体意义后，建议从测试代码开始阅读，对于
[encode_test.go](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode_test.go)
中的代码段

	func TestEncode(t *testing.T) {
		runEncTests(t, func(val interface{}) ([]byte, error) {
			b := new(bytes.Buffer)
			[err := Encode(b, val)](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode_test.go#L275)
			return b.Bytes(), err
		})
	}

[err := Encode(b, val)](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode_test.go#L275)中的 Encode 作为编码的入口函数，实现在
[encode.go](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go)

	func Encode(w io.Writer, val interface{}) error {
		if outer, ok := w.(*encbuf); ok {
			// Encode was called by some type's EncodeRLP.
			// Avoid copying by writing to the outer encbuf directly.
			return outer.encode(val)
		}
		eb := encbufPool.Get().(*encbuf)
		defer encbufPool.Put(eb)
		eb.reset()
		if err := eb.encode(val); err != nil {
			return err
		}
		return eb.toWriter(w)
	}

[if err := eb.encode(val); err != nil {](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L89)中的 encbuf.encode 作为内容编码（内部）函数

[return eb.toWriter(w)](https://github.com/ethereum/go-ethereum/blob/master/rlp/encode.go#L92)
中的 encbuf.toWriter 作为头部编码（内部）函数

...
