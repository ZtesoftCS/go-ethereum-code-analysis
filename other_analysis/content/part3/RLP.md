---
title: "详解以太坊RLP编码"
menuTitle: "RLP"
date: 2019-12-25T13:30:52+08:00
weight: 300004
description: "详解以太坊RLP编码，RLP算法规则"
mathjax: true
---

RLP(Recursive Length Prefix) 递归长度前缀编码是以太坊中最常使用的序列化格式方法。到处都在使用它，如区块、交易、账户、消息等等。RLP 旨在成为高度简约的序列化方法，唯一目标就是存储嵌套的字节数组。
不同于protobuf、BSON和其他序列化方法，RLP 不企图定义任何特定数据类型，如布尔值、浮点数、双精度数，甚至是整数。
相反，RLP 只是以嵌套数组形式存储结构型数据，由上层协议来确定数组的含义。

以太坊中的序列化算法并没有使用已有的 protobuf 或 BSON，这是因为 RLP 编码更容易实现，并且可确保字节操作的完全一致性。许多编程语言中键/值字典没有明确的排序，浮点格式有许多特殊情况，可能导致相同的数据却又不同的编码结果，导致出现不一致的哈希值。以太坊自行开发RLP 编码，可以确保在设计这些协议时更牢记这些目标。

## 协议定义

RLP 编码算法定义在以太坊黄皮书中，记  $\mathbb{T}$ 为可能的数据结构集:

<p>
<!-- htmlmin:ignore -->
\begin{array}{cc}
\mathbb{T} & \equiv & \mathbb{L} \cup \mathbb{B} \\
\mathbb{L} & \equiv & \{ \mathbf{t}: \mathbf{t} = ( \mathbf{t}[0], \mathbf{t}[1], ... ) \; \wedge \; \forall_{n < \lVert \mathbf{t} \rVert} \; \mathbf{t}[n] \in \mathbb{T} \} \\
\mathbb{B} & \equiv & \{ \mathbf{b}: \mathbf{b} = ( \mathbf{b}[0], \mathbf{b}[1], ... ) \;\wedge \; \forall_{n < \lVert \mathbf{b} \rVert} \; \mathbf{b}[n] \in \mathbb{O} \}
\end{array}
<!-- htmlmin:ignore -->
</p>

其中 $\mathbb{O}$ 是字节集，因此：

1. $\mathbb{B}$ 是所有字节的集合(数组)，其中 $\mathbf{b}[0]$ 是单字节，相对于树中的叶子。
2. $\mathbb{L}$ 是非单叶的所有树状（子）结构的集合（如果将其想象为数，则为分支节点）。
3. $\mathbb{T}$ 是所有字节数组和此类结构序列的集合。

通过两个子方法定义名为 RLP 方法作为 RLP 编码算法。当输入值是一个字节数组时，用第一个子方法执行编码。当值是更多值的序列时，用第二个子方法执行编码。

<p>
<!-- htmlmin:ignore -->
\begin{equation}
\mathtt{\tiny RLP}(\mathbf{x}) \equiv \begin{cases} R_{\mathrm{b}}(\mathbf{x}) & \text{if} \quad \mathbf{x} \in \mathbb{B} \\ R_{\mathrm{l}}(\mathbf{x}) & \text{otherwise} \end{cases}
\end{equation}
<!-- htmlmin:ignore -->
</p>

使用第一个子方法编码时（要序列化的值是字节数组），RLP 编码采用以下三种形式之一：

1. 对于[0x0,0x7f]范围内的单字节，则输入与输出完全（RLP 编码内容就是字节内容本身）。
1. 如果字节数组长度是[0,55]范围内，则输出等于前缀加字节内容。其前缀等于常量 0x80 加上字节数组长度。这样第一个字节的表达范围是[0x80,0x80+55=0xb7]。
1. 否则，输出等于前缀加字节内容。其前缀等于常量 0xb7 与字节数组长度的最小长度值之和加上字节数组长度大端字节值。第一个字节范围是[0xb7+1,0xbf]。比如，编码一个长度为 256（$2^8$=0x100）的字符串时，因 256 需要至少 2 个字节存储，其高位字节为 0x10，因此RLP 编码输出为 [ 0xb7+ 2, 0x01,0x00,字节内容...]。

最终， $R_{\mathrm{b}}$ 定义为:

<p>
<!-- htmlmin:ignore -->
\begin{eqnarray}
R_{\mathrm{b}}(\mathbf{x}) & \equiv & \begin{cases}
\mathbf{x} & \text{if} \quad \lVert \mathbf{x} \rVert = 1 \wedge \mathbf{x}[0] < 128 \\
(128 + \lVert \mathbf{x} \rVert) \cdot \mathbf{x} & \text{else if} \quad \lVert \mathbf{x} \rVert < 56 \\
\big(183 + \big\lVert \mathtt{\tiny BE}(\lVert \mathbf{x} \rVert) \big\rVert \big) \cdot \mathtt{\tiny BE}(\lVert \mathbf{x} \rVert) \cdot \mathbf{x} & \text{otherwise}
\end{cases} \\
\mathtt{\tiny BE}(x) & \equiv & (b_0, b_1, ...): b_0 \neq 0 \wedge x = \sum_{n = 0}^{n < \lVert \mathbf{b} \rVert} b_{\mathrm{n}} \cdot 256^{\lVert \mathbf{b} \rVert - 1 - n} \\
(a) \cdot (b, c) \cdot (d, e) & = & (a, b, c, d, e)
\end{eqnarray}
<!-- htmlmin:ignore -->
</p>

其中，$\mathtt{BE}$ 是将正整数值扩展为最小长度的高端字节数组的函数，点运算符是执行序列拼接。

相反，在编码一个结构体数据时，将依次递归编码结构体中的每项数据。形同于从树的叶子开始向上编码。
当编码的值是一个其他 Item （非单叶）的序列化值，则 RLP 采用以下两种形式之一：

1. 如果 Item 的内容（它的所有子项的组合）长度范围是[ 0,55]时，它的RLP编码由常量 0xC0 加上所有的项的RLP编码串联起来的长度得到的单个字节，后跟所有的项的RLP编码的串联组成。 第一字节的范围因此是[0xc0, 0xf7]。
2. 如果 Item 的内容超过55字节，它的RLP编码由 0xf7 加上所有的项的RLP编码串联起来的长度的长度得到的单个字节，后跟所有的项的RLP编码串联起来的长度，再后跟所有的项的RLP编码的串联组成。 第一字节的范围因此是[0xf8, 0xff] 。

因此，我们通过正式定义如下 $R_{\mathrm{l}}$:

<p>
<!-- htmlmin:ignore -->
\begin{eqnarray}
R_{\mathrm{l}}(\mathbf{x}) & \equiv & \begin{cases}
(192 + \lVert s(\mathbf{x}) \rVert) \cdot s(\mathbf{x}) & \text{if} \quad \lVert s(\mathbf{x}) \rVert < 56 \\
\big(247 + \big\lVert \mathtt{\tiny BE}(\lVert s(\mathbf{x}) \rVert) \big\rVert \big) \cdot \mathtt{\tiny BE}(\lVert s(\mathbf{x}) \rVert) \cdot s(\mathbf{x}) & \text{otherwise}
\end{cases} \\
s(\mathbf{x}) & \equiv & \mathtt{\tiny RLP}(\mathbf{x}_0) \cdot \mathtt{\tiny RLP}(\mathbf{x}_1) ...
\end{eqnarray}
<!-- htmlmin:ignore -->
</p>

下图则是公式的图形版：

![以太坊技术与实现-图-以太坊RLP 编码算法-数据标记规则](https://img.learnblockchain.cn/book_geth/2019-12-28-23-20-21.png!de?width=700px)


从图中可以看出，不同类型的数据，将有不同的前缀标识。
前缀也可以理解为报文头，通过报文头可准确获取报文内容。
图中灰色部分则为RLP编码输出前缀。

## RLP编码示例

根据上面规则，我们可以计算出如下输入的 RLP 编码输出值。

1. 字符串 "dog" = [ 0x83, 'd', 'o', 'g' ]
2. 列表 [ "cat", "dog" ] = [ 0xc8, 0x83, 'c', 'a', 't', 0x83, 'd', 'o', 'g' ]
3. 空字符串 ('null') = [ 0x80 ]
4. 空列表 = [ 0xc0 ]
5. 数字 15 ('\x0f') = [ 0x0f ]
6. 数字 1024 ('\x04\x00') = [ 0x82, 0x04, 0x00 ]
7. 空子集合  [ [], [[]], [ [], [[]] ] ] = [ 0xc7, 0xc0, 0xc1, 0xc0, 0xc3, 0xc0, 0xc1, 0xc0 ]
8. 字符串 "Lorem ipsum dolor sit amet, consectetur adipisicing elit" = [ 0xb8, 0x38, 'L', 'o', 'r', 'e', 'm', ' ', ... , 'e', 'l', 'i', 't' ]

需要清楚的是 RLP 编码时，并不关注结构数据的具体定义，均会被转换为一个嵌套型字节数组拼接处理。
比如，我们定义如下结构。

```go

type Entity struct {
	AccountNonce uint64
	Price        *big.Int
	Payload      []byte
	S            *big.Int
	More         struct {
		CreateTime uint64
		Remark     string
	}
}
```

在进行 RLP 编码时，该结构体等同于字节数组：`[AccountNonce,  Price,Payload,S ,[CreateTime, Remark ]]`。
下面，我们写一段代码来展示RLP 过程。

```go
package main

import (
	"fmt"
	"math/big"
	"os"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/rlp"
)

func toBig(v string) *big.Int {
	b, ok := new(big.Int).SetString(v, 10)
	if !ok {
		panic("bad big.Int string")
	}
	return b
}

func main() {

	items := []interface{}{
		uint64(333013),
		common.FromHex("0xfb8f2d4ae37582cb7ae307196d6e789b7f8ccb665d34ac77000000000"),
		toBig("37788494754494904754064770007423869431791776276838145493898599251081614922324"),
		[]interface{}{
			uint64(131231012),
			"交易扩展信息",
		},
	}

	b, err := rlp.EncodeToBytes(items)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	fmt.Println("RLP编码输出：\n", common.Bytes2Hex(b))

	for i, v := range items {
		b, err := rlp.EncodeToBytes(v)
		if err != nil {
			fmt.Println(err)
			os.Exit(1)
		}
		fmt.Printf("items[%d]=RLP(%v)=%s\n", i, v, common.Bytes2Hex(b))
		if list, ok := v.([]interface{}); ok {
			for i, v := range list {
				b, err := rlp.EncodeToBytes(v)
				if err != nil {
					fmt.Println(err)
					os.Exit(1)
				}
				fmt.Printf("\t\t [%d]=RLP(%v)=%s\n", i, v, common.Bytes2Hex(b))
			}
		}
	}
}
```

执行实例，我们可以得到输出结果。分别输出了 items 的 RLP 编码结构以及 items 中所有元素单独的RLP 编码结果。

```html
RLP编码输出：
 f85c830514d59d0fb8f2d4ae37582cb7ae307196d6e789b7f8ccb665d34ac77000000000a0538b87b3af985c8f03a7bd0785ef8d087f833a1a56312ce3c67d40b292d51254d88407d26d2492e4baa4e69893e689a9e5b195e4bfa1e681af
items[0]=RLP(333013)=830514d5
items[1]=RLP([15 184 242 212 174 55 88 44 183 174 48 113 150 214 231 137 183 248 204 182 101 211 74 199 112 0 0 0 0])=9d0fb8f2d4ae37582cb7ae307196d6e789b7f8ccb665d34ac77000000000
items[2]=RLP(37788494754494904754064770007423869431791776276838145493898599251081614922324)=a0538b87b3af985c8f03a7bd0785ef8d087f833a1a56312ce3c67d40b292d51254
items[3]=RLP([131231012 交易扩展信息])=d88407d26d2492e4baa4e69893e689a9e5b195e4bfa1e681af
		 [0]=RLP(131231012)=8407d26d24
		 [1]=RLP(交易扩展信息)=92e4baa4e69893e689a9e5b195e4bfa1e681af

```

RLP 编码 items 时，所有元素都可以转换为字节数组。将其元素作为叶子转换为字节数组后，再将各项输出根据子方法2 的规则拼接成最终 RLP 编码结果。

![以太坊技术与实现-图-2019-12-28-0-50-55.png](https://img.learnblockchain.cn/book_geth/2019-12-28-0-50-55.png!de?width=600px)

下图是本示例的 RLP 编码计算过程。先依次 RLP 编码 items[0]、items[1]、items[2]和 items[3]。
因为 items[3] 并非字节数组，将使用子方法2处理。

![以太坊技术与实现-图-2019-12-28-0-54-39.png](https://img.learnblockchain.cn/book_geth/2019-12-28-0-54-39.png!de)

items[3]的两个子项 RLP 拼接后的值为`0x8407d26d2492e4baa4e69893e689a9e5b195e4bfa1e681af`，
占用 24 字节，因此 items[3] 的前缀为 0xC0+24=0xd8。
而items[0]到 items[3] 的各项 RLP 拼接后的字节数组长度为  占用 92 个字节，因此 items 的前缀为 `[0xf7+1,92]`。

## 代码实现

在 go-ethereum 项目中， RLP 的实现在 github.com/ethereum/go-ethereum/rlp 包中，文件结构如下：

```html
rlp
├── decode.go
├── doc.go
├── encode.go
├── raw.go
└── typecache.go
```

1. decode.go: RLP 反序列化解码实现
2. encode.go: RLP 序列化编码实现
3. raw.go: 辅助类
4. typecache.go: 类型反射缓存

我们重点关注 encode.go，反向的 decode.go 不进行说明。

首先，RLP 提供三个 API 接口：

1. Encode(w io.Writer, val interface{}) error
2. EncodeToBytes(val interface{}) ([]byte, error)
3. EncodeToReader(val interface{}) (size int, r io.Reader, err error)

允许将符合要求的 val 编码为字节输出或者写入到文件流中。最重要的则是不同类型数据的RLP实现。
go-ethereum 中分别实现了不同数据类型转换为字节数组的函数：

1. writeUint
1. writeBigInt
1. writeBigIntNoPtr
1. writeBigIntPtr
1. writeBool
1. writeByteArray
1. writeBytes
1. writeRawValue
1. writeString
1. writeInterface
1. writeEncoder
1. writeEncoderNoPtr

根据数据的不同类型分别使用对应的转换函数，在 makeWriter 函数中完成转换。

```go
//rlp/encode.go:345
func makeWriter(typ reflect.Type, ts tags) (writer, error) {
	kind := typ.Kind()
	switch {
	case typ == rawValueType:
		return writeRawValue, nil
	case typ.Implements(encoderInterface):
		return writeEncoder, nil
	case kind != reflect.Ptr && reflect.PtrTo(typ).Implements(encoderInterface):
		return writeEncoderNoPtr, nil
	case kind == reflect.Interface:
		return writeInterface, nil
	case typ.AssignableTo(reflect.PtrTo(bigInt)):
		return writeBigIntPtr, nil
	case typ.AssignableTo(bigInt):
		return writeBigIntNoPtr, nil
	case isUint(kind):
		return writeUint, nil
	case kind == reflect.Bool:
		return writeBool, nil
	case kind == reflect.String:
		return writeString, nil
	case kind == reflect.Slice && isByte(typ.Elem()):
		return writeBytes, nil
	case kind == reflect.Array && isByte(typ.Elem()):
		return writeByteArray, nil
	case kind == reflect.Slice || kind == reflect.Array:
		return makeSliceWriter(typ, ts)
	case kind == reflect.Struct:
		return makeStructWriter(typ)
	case kind == reflect.Ptr:
		return makePtrWriter(typ)
	default:
		return nil, fmt.Errorf("rlp: type %v is not RLP-serializable", typ)
	}
}
```

可以看到 RLP 仅只是能转换非负整数的基本数据类型：bool、uint、string、byte、big.Int。
而具体 RLP 编码工作由 encbuf 类实现。

```go
//rlp/encode.go:121
type encbuf struct {
	str     []byte      // 字符串数据，包含列表标题以外的所有内容
	lheads  []*listhead // 所有列表标题
	lhsize  int         // 所有编码列表标题的大小总和
	sizebuf []byte      // 9字节辅助缓冲区，用于uint编码
}

func (w *encbuf) reset() {
	w.lhsize = 0
	if w.str != nil {
		w.str = w.str[:0]
	}
	if w.lheads != nil {
		w.lheads = w.lheads[:0]
	}
}

// encbuf implements io.Writer so it can be passed it into EncodeRLP.
func (w *encbuf) Write(b []byte) (int, error) {
	w.str = append(w.str, b...)
	return len(b), nil
}

func (w *encbuf) encode(val interface{}) error {
	rval := reflect.ValueOf(val)
	ti, err := cachedTypeInfo(rval.Type(), tags{})
	if err != nil {
		return err
	}
	return ti.writer(rval, w)
}

func (w *encbuf) encodeStringHeader(size int) {
	if size < 56 {
		w.str = append(w.str, 0x80+byte(size))
	} else {
		sizesize := putint(w.sizebuf[1:], uint64(size))
		w.sizebuf[0] = 0xB7 + byte(sizesize)
		w.str = append(w.str, w.sizebuf[:sizesize+1]...)
	}
}

func (w *encbuf) encodeString(b []byte) {
	if len(b) == 1 && b[0] <= 0x7F {
		// fits single byte, no string header
		w.str = append(w.str, b[0])
	} else {
		w.encodeStringHeader(len(b))
		w.str = append(w.str, b...)
	}
}

func (w *encbuf) list() *listhead {
	lh := &listhead{offset: len(w.str), size: w.lhsize}
	w.lheads = append(w.lheads, lh)
	return lh
}

func (w *encbuf) listEnd(lh *listhead) {
	lh.size = w.size() - lh.offset - lh.size
	if lh.size < 56 {
		w.lhsize++ // length encoded into kind tag
	} else {
		w.lhsize += 1 + intsize(uint64(lh.size))
	}
}

func (w *encbuf) size() int {
	return len(w.str) + w.lhsize
}

func (w *encbuf) toBytes() []byte {
	out := make([]byte, w.size())
	strpos := 0
	pos := 0
	for _, head := range w.lheads {
		// write string data before header
		n := copy(out[pos:], w.str[strpos:head.offset])
		pos += n
		strpos += n
		// write the header
		enc := head.encode(out[pos:])
		pos += len(enc)
	}
	// copy string data after the last list header
	copy(out[pos:], w.str[strpos:])
	return out
}

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
```

该类的设计，主要是存储 RLP 递归编码的树节点内容。同级节点则通过 head 有序排列。

> ps: 代码实现的理解并非难事，只有掌握算法协议，则非常容易理解。

在我看你以太坊的 RLP 虽然高效，但是不经济的。所有存储在区块链中的数据应该仅可能少，而 RLP 并没有数据压缩过程。

## 参考资料

1. [WIKI-RLP](
https://github.com/ethereum/wiki/wiki/%5B%E4%B8%AD%E6%96%87%5D-RLP)