---
title: "签名与校验"
date: 2019-07-31T23:42:24+08:00 
weight: 300001
---

原本写有以太坊交易签名的文章，但觉得对以太坊的数字签名还讲得不够夯实。这里从原理上聊聊以太坊签名与校验，希望这篇文章让你一次性掌握以太坊数字签名技术。

## 为何选择签名算法 secp256k1

比特币在2009年1月4日成功挖出创世区块，稳定运行至今。出色的稳定运行能力，让其他区块链都大量借鉴比特币技术方案，其中包括密码学领域的哈希算法、加密算法。站在巨人的肩膀改进技术，是我们一贯的做法，以太坊也不例外。以太坊在2015年7月30日上公链时，同样采用了比特币的签名算法：椭圆曲线算法 secp256k1。

secp256k1 是[高效密码组标准(SECG)](https://www.secg.org/) 协会开发的一套高效的椭圆曲线签名算法标准。 在比特币流行之前，secp256k1并未真正使用过。secp256k1 命名由几部分组成：sec来自SECG标准，p表示曲线坐标是素数域，256表示素数是256位长，k 表示它是 Koblitz 曲线的变体，1表示它是第一个标准中该类型的曲线。

> SECG(Standards for Efficient Cryptography Group) 成立于1998年，一个从事密码标准通用性潜力研究的组织。旨在促进在各种计算平台上采用高效加密和提高互操作性。

但因具有几个不错的特性，现在它越来越受欢迎。大多数常用的椭圆曲线是随机结构，但 secp256k1是为了更有效率的计算而构造了一个非随机结构。因此经过充分地优化算法代码实现，其计算效率可以比其他椭圆曲线算法快30%以上。此外，与常用的NIST曲线不同，secp256k1 的常量是以可预测的方式挑选的，这可以有效降低曲线设计者安置后门的可能性。

密码学内容涉及太多数学知识，这里我虞双齐还没能力说清这里面的一二三 :)。有兴趣的可以看 Secp256k1[算法标准文档](http://www.secg.org/sec2-v2.pdf)，这里我只画一张图，让大家对签名算法归类所有了解。

![密码学技术分类](https://img.learnblockchain.cn/2019/05/03_cryptography-technology.png!de)

从图中看到，secp256k1 是 ECDSA 算法中的一个标准，出现的也比较晚。为何中本聪为比特币secp256k1作为交易验证的签名算法？比特币开发者社区曾讨论过 [secp256k1](https://bitcointalk.org/?topic=2699.0) 是否安全。中本聪没有明确解释，只是说道"有根据的推测"。社区的讨论不外乎是在安全和效率上做权衡，选择一个不受任何政府控制、无后门的签名算法是比特币的首要考虑因素，其次，也需要提供计算速度，毕竟在比特币中加密、签名、校验签名是不断在处理的事情（60%左右的CPU时间几乎全用在这上面），而具有可预测性、高计算效率特性的Koblitz曲线是不错的选择。基于安全第一，效率第二原则，secp256k1 就是一个最优解。



## 以太坊与比特币签名的差异化

虽然以太坊签名算法是 secp256k1 ，但是在签名的格式有所差异。

比特币在 [BIP66](https://github.com/bitcoin/bips/blob/master/bip-0066.mediawiki)中对签名数据格式采用严格的[DER](https://www.itu.int/ITU-T/studygroups/com17/languages/X.690-0207.pdf)编码格式，其签名数据格式如下：

```
 0x30 [total-length] 0x02 [R-length] [R] 0x02 [S-length] [S]
```

这里的 0x30 、0x02 是DER数据格式中定义的Tag，不同Tag对应不同含义。以 secp256k1 算法来说：

+ total-length： 1字节，表示签名字节总长度，其值等于：4byte(Tag total-length 后面的四个Tag)+R的长度+S的长度。而secp256k1算法是256长度，即32字节。因此签名字节总长度为0x44(68=4+32+32)。
+ R-length： 1字节，表示R值长度。其值始终等于0x20(表示十进制32)。
+ R： 32字节，secp256k1 算法中的R值。
+ S-length: 1字节，表示S值长度。始终等于0x20。
+ S：32字节，secp256k1 算法中的S值。

> 注意，这里还尚未包含签名内容的哈希标志信息。

例如，如下代码是利用Go语言版的比特币对字符串`ethereum`签名，

```go
package main
import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"log"
	
	"github.com/btcsuite/btcd/btcec" 
)
func main()  {
	dataHash := sha256.Sum256([]byte("ethereum"))

	// 准备私钥
	pkeyb,err :=hex.DecodeString("289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032")
	if err!=nil{
		log.Fatalln(err)
	}
	// 基于secp256k1的私钥
	privk,_:=btcec.PrivKeyFromBytes(btcec.S256(),pkeyb)

	// 对内容的 hash 进行签名
	sigInfo,err:= privk.Sign(dataHash[:])
	if err!=nil{
		log.Fatal(err)
	}
	// 获得DER格式的签名
	sig :=sigInfo.Serialize()
	fmt.Println("sig length:",len(sig))
	fmt.Println("sig hex:",hex.EncodeToString(sig))
}
```

执行代码，输出内容如下：

```
sig length 70
sig hex: 304402207912f50819764de81ab7791ab3d62f8dabe84c2fdb2f17d76465d28f8a968f73022055fbb6cd8dfc7545b6258d4b032753b2074232b07f3911822b37f024cd101166
```

我们从下图中可以清晰地看到，比特币签名是对secp256k1的签名进行DER格式编码处理。
![比特币签名格式举例](https://img.learnblockchain.cn/2019/05/04_bitcoin-sign-demo.png!de)

而以太坊中对内容签名时，尚未进行DER格式。同样在以太坊中对字符串`ethereum`签名。

```go
package main
import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"log"
	
	"github.com/ethereum/go-ethereum/crypto" 
)
func main()  {  
  dataHash := sha256.Sum256([]byte("ethereum"))

	// 准备私钥
	pkeyb,err :=hex.DecodeString("289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032")
	if err!=nil{
		log.Fatalln(err)
	}
	// 基于secp256k1的私钥
	pkey,err:=crypto.ToECDSA(pkeyb)
	if err!=nil{
		log.Fatalln(err)
	}
	// 签名
	sig,err:= crypto.Sign(dataHash[:],pkey)
	if err!=nil{
		log.Fatal(err)
	}
	fmt.Println("sig length:",len(sig))
	fmt.Println("sig hex:",hex.EncodeToString(sig))
}	
```

执行代码，输出内容如下：

```
sig length: 65
sig hex: 7912f50819764de81ab7791ab3d62f8dabe84c2fdb2f17d76465d28f8a968f7355fbb6cd8dfc7545b6258d4b032753b2074232b07f3911822b37f024cd10116600
```

对比比特币签名，以太坊的签名格式是`r+s+v`。 r 和 s 是ECDSA签名的原始输出，而末尾的一个字节为 recovery id 值，但在以太坊中用`V`表示，v 值为1或者0。recovery id 简称 recid，表示从内容和签名中成功恢复出公钥时需要查找的次数（因为根据`r`值在椭圆曲线中查找符合要求的坐标点可能有多个），但在比特币下最多需要查找两次。这样在签名校验恢复公钥时，不需要遍历查找，一次便可找准公钥，加速签名校验速度。

在以太坊中签名代码实现如下：

```go
//crypto/signature_nocgo.go:60
func Sign(hash []byte, prv *ecdsa.PrivateKey) ([]byte, error) {
	if len(hash) != 32 {//❶
		return nil, fmt.Errorf("hash is required to be exactly 32 bytes (%d)", len(hash))
	}
	if prv.Curve != btcec.S256() {//❷
		return nil, fmt.Errorf("private key curve is not secp256k1")
	}
  //❸
	sig, err := btcec.SignCompact(btcec.S256(), (*btcec.PrivateKey)(prv), hash, false)
	if err != nil {
		return nil, err
	}
	// Convert to Ethereum signature format with 'recovery id' v at the end.
	v := sig[0] - 27 //❹
	copy(sig, sig[1:])//❺
	sig[64] = v
	return sig, nil
}
```

+ ❶ 首先，签名是针对32字节的byte，实际上是对应待签名内容的哈希值，以太坊中哈希值`common.Hash`长度固定为32。比如对交易签名时传入的是交易哈希` crypto.Sign(tx.Hash()[:], prv)`。
+ ❷ 确保私钥的曲线算法是比特币的secp256k1。目的是控制所有签名均通过 secp256k1 算法计算。
+ ❸ 调用比特币的签名函数，传入 secp256k1 、私钥和签名内容,并说明并非压缩的私钥。此时 SignCompact 函数返还一定格式的签名。其格式为：`[27 + recid] [R]  [S]`
+ ❹  以太坊将比特币中记录的recovery id 提取出。减去27的原因是，比特币中第一个字节的值等于`27+recid`，因此 recid= sig[0]-27。
+ ❺ 以太坊签名格式是`[R] [S] [V]`，和比特币不同。因此需要进行调换，将 R  和 S 值放到前面，将 recid 放到最后。

下图中展示的上面操作签名数据转换示例流程。只是在第一次查找便查找到合法公钥，因此 recid 为零。
![以太坊签名数据格式](https://img.learnblockchain.cn/2019/05/05_ethereum-sign-format.png!de)

有一点需要注意，以太坊的 crypto.Sign 函数实际是采用两个代码库，C语言版和Go语言版。那么在外部在实际调用时调用的是哪个语言版本的secp256k1呢？这在编译期由[编译约束条件](https://golang.org/pkg/go/build/#hdr-Build_Constraints)决定。如下图以太坊的签名函数提供了C版调用和纯Go调用，两个语言版本在文件开头会标记编译条件和文件名上做区分，上面的解析代码属比特币 secp256k1 Go语言版调用，其Go语言库是 github.com/btcsuite/btcd/btcec 。

![以太坊crypto签名调用提供CGo和GO调用](https://img.learnblockchain.cn/2019/05/05_ethereum-crypto-cgo.png!de)

> cgo 能让Go语言跨语言调用 C ，可以将Go代码和C代码打包到一起，想了解更多可参加官方文章 [C? Go? Cgo!](https://blog.golang.org/c-go-cgo)

## 签名校验

使用使用 crypto.Sign 对内容签名后，同样可以使用 crypto.VerifySignature 方法校验签名是否正确。下面示例代码演示将上面示例中获得的签名结果进行验证。

```go
func main()  {
	decodeHex:= func(s string) []byte {
		b,err:=hex.DecodeString(s)
		if err!=nil{
			log.Fatal(err)
		}
		return b
	}
	dataHash := sha256.Sum256([]byte("ethereum"))
	sig:=decodeHex(
"7912f50819764de81ab7791ab3d62f8dabe84c2fdb2f17d76465d28f8a968f7355fbb6cd8dfc7545b6258d4b032753b2074232b07f3911822b37f024cd10116600")
	pubkey:=decodeHex(
	"037db227d7094ce215c3a0f57e1bcc732551fe351f94249471934567e0f5dc1bf7")

	ok:=crypto.VerifySignature(pubkey,dataHash[:],sig[:len(sig)-1])
	fmt.Println("verify pass?",ok)
}
```

关键点在于调用校验签名函数时，第三个参数sig 送入的是 `sig[:len(sig)-1]` 去掉了末尾的一个字节。这是因为函数`VerifySignature`要求 `sig`参数必须是`[R] [S]`格式，因此需要去除末尾的`[V]`。

## 链数据签名与校验

上面的签名仅仅是 secp256k1 的签名与校验。但实际在区块链中，为了安全性签名中加入了特性数据，比如签名类型(环签、单私钥签名等)、链标识符等。在以太坊中区块中的数据需要签名的仅有交易，因此下面我以交易为示例讲解以太坊的链数据签名和交易。

## 交易数据签名

以太坊加密算法是采用比特币的椭圆曲线 secp256k1加密算法。签名交易对应代码如下：

```go
//core/types/transaction_signing.go:56
func SignTx(tx *Transaction, s Signer, prv *ecdsa.PrivateKey) (*Transaction, error) {//❶
   h := s.Hash(tx)//❷
   sig, err := crypto.Sign(h[:], prv)//❸
   if err != nil {
      return nil, err
   }
   return tx.WithSignature(s, sig)//❹
}
```

+ ❶ 交易签名时，需要提供一个签名器(Signer)和私钥(PrivateKey)。需要Singer是因为在[EIP155](http://eips.ethereum.org/EIPS/eip-155)修复简单重复攻击漏洞后，需要保持旧区块链的签名方式不变，但又需要提供新版本的签名方式。因此通过接口实现新旧签名方式，根据区块高度创建不同的签名器。

  ```go
  //core/types/transaction_signing.go:42
  func MakeSigner(config *params.ChainConfig, blockNumber *big.Int) Signer {
     var signer Signer
     switch {
     case config.IsEIP155(blockNumber):
        signer = NewEIP155Signer(config.ChainID)
     case config.IsHomestead(blockNumber):
        signer = HomesteadSigner{}
     default:
        signer = FrontierSigner{}
     }
     return signer
  }
  ```

+ ❷ 重点介绍EIP155改进提案中所实现的新哈希算法，主要目的是获取交易用于签名的哈希值 TxSignHash。和旧方式相比，哈希计算中混入了链ID和两个空值。注意这个哈希值 TxSignHash 在EIP155中并不等同于交易哈希值。

  ![以太坊交易签名内容哈希新补充](https://img.learnblockchain.cn/2019/04/27_tx-sign-content-hash.png!de)

  这样，一笔已签名的交易就只可能属于某一确定的唯一一条区块链。

+ ❸ 内部利用私钥使用secp256k1加密算法对`TxSignHash`签名，获得签名结果`sig`。

+ ❹ 执行交易`WithSignature`方法，将签名结果解析成三段`R、S、V`，拷贝交易对象并赋值签名结果。最终返回一笔新的已签名交易。

  ```go
  func (tx *Transaction) WithSignature(signer Signer, sig []byte) (*Transaction, error) {
     r, s, v, err := signer.SignatureValues(tx, sig)
     if err != nil {
        return nil, err
     }
     cpy := &Transaction{data: tx.data}
     cpy.data.R, cpy.data.S, cpy.data.V = r, s, v
     return cpy, nil
  } 
  ```

根据上面代码逻辑，提炼出如下交易签名流程，整个过程利用了 RLP编码、Keccak256哈希算法和椭圆曲线 secp256k1加密算法。从这里可以看出，密码学技术是区块链成功的最大基石。

![以太坊交易签名流程](https://img.learnblockchain.cn/2019/04/27_ethereum-tx-sign-flow.png!de)

上图中还有一个关键数据，则 Signer 是如何生成 R 、S、V值的。从前面的签名算法过程，可以知道 R 和 S 是ECDSA签名的原始输出，V 值是 recid，其值是0或者1。但是在交易签名时，V 值不再是recid, 而是 recid+ chainID*2+ 35。比如：

```go
tx:=types.NewTransaction(1,
   common.HexToAddress("0x002e08000acbbae2155fab7ac01929564949070d"),
   big.NewInt(100),21000,big.NewInt(1),nil)
```

创建一笔交易，使用私钥 289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032 进行签名。

```go
// 实例化一个签名器
signer:=types.NewEIP155Signer(big.NewInt(888))
tx,err=types.SignTx(tx,signer,pkey)
	if err!=nil{
		log.Fatalln(err)
	}
v,r,s:=tx.RawSignatureValues()
fmt.Printf("tx sign V=%d,R=%d,S=%d\n",v,r,s)
```

得到 V = 888*2+recid+35= 1812。

## 交易签名解析流程

签名交易后，如何才能获得交易签名者呢？这个是加密算法的逆向解签名者，是利用用户签名内容以及签名信息(R、S、V)得到用户私钥的公钥，从而得到签名者账户地址。具体细节如下。

对比交易签名流程，解签名是逆向推导。

```go
//core/types/transaction_signing.go:127
func (s EIP155Signer) Sender(tx *Transaction) (common.Address, error) {
   if !tx.Protected() { //❶
      return HomesteadSigner{}.Sender(tx)
   }
   if tx.ChainId().Cmp(s.chainId) != 0 { //❷
      return common.Address{}, ErrInvalidChainId
   }
   V := new(big.Int).Sub(tx.data.V, s.chainIdMul)//❸ 
   V.Sub(V, big8)
   return recoverPlain(s.Hash(tx), tx.data.R, tx.data.S, V, true)
}
```

+ ❶EIP155 下交易属于受保护交易，如果不受保护，则说明属于旧的签名格式，使用HomesteadSigner校验。

	交易是否受保护取决于是否是 EIP155 签名器签名，因为在 EIP155 中  v =  recid+ chainID*2+ 35，旧算法是 v= recid+27，而 recid 为0或者1，即 v 为 27 或28。因此只要 v 值不等于 27和28则为受保护的交易。

```go
//core/types/transaction.go:117
func isProtectedV(V *big.Int) bool {
   if V.BitLen() <= 8 {
      v := V.Uint64()
      return v != 27 && v != 28
   }
   return true
}
```

+ ❷ 根据 v =  recid+ chainID*2+ 35 ，其中recid为0或者1 ，得 chainID= (v-35)/2 或者 (v-36)/2，不管v是奇数还是偶数，两种计算方式的结果那么是整除,要么留有小数，即要么等于chainID，那么是稍大于chainID。因此可以对结果直接取整，即等于 chainID。以太坊的实现代码如下：

  ```go
  //core/types/transaction_signing.go:251
  func deriveChainId(v *big.Int) *big.Int {
     if v.BitLen() <= 64 {
        v := v.Uint64()
        if v == 27 || v == 28 {
           return new(big.Int)
        }
        return new(big.Int).SetUint64((v - 35) / 2)
     }
     v = new(big.Int).Sub(v, big.NewInt(35))
     return v.Div(v, big.NewInt(2))
  }
  ```

  即考虑了超过MaxUint64,也考虑了 27或者28的旧签名方式。拿到 chainID 后，则判断tx.ChainID 是否等于当前的网络的ChainID。

+ ❸ 最后根据 v =  recid+ chainID*2+ 35，还原出 `recid = v -  chainID * 2 - 35=v -  chainID * 2 - 8-27`。这里并没有直接减去 35 的原因是`recoverPlain`方法中会按照旧方式减去 27 ，因此这里只需要减去 8 ，其他在recoverPlain中处理。

至此，我们说明了以太坊的签名以及和比特币的差异，最后还讲解了以太坊中一笔交易的签名流程和校验签名过程。
