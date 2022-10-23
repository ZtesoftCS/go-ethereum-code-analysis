# cosmos地址

comsos对地址，公钥，私钥对定义如下：
```
//tendermint/crypto/crypto.go
type Address = cmn.HexBytes

type PubKey interface {
	Address() Address
	Bytes() []byte
	VerifyBytes(msg []byte, sig []byte) bool
	Equals(PubKey) bool
}

type PrivKey interface {
	Bytes() []byte
	Sign(msg []byte) ([]byte, error)
	PubKey() PubKey
	Equals(PrivKey) bool
}
```
从上可以看出，私钥导出公钥，公钥导出地址，地址的本质是一个[]byte类型。
为了更加方便的识辨出一个地址的不同作用，对`Address`又可以进行如下三种转变：

* AccAddress 作为普通账户存在，因为代表的是账户，所以可以转账，委托等
* ConsAddress 作为共识地址存在，只是一个地址，不是账户，所以没有转账，委托等，只能作为一个验证者进行签名
* ValAddress ？？

`ValAddress`和`ConsAddress`本质是同一个地址，也就是来自于`priv_validator.json`文件的地址。
通过客户端产生一个普通的`AccAddress`，此地址所代表的账户可以把自己的代币利用`create-validator`命令对来自于`priv_validator.json`文件的公钥进行创建验证者申请，一旦申请交易成功，`AccAddress`这个地址所代表的账户就和来自于`priv_validator.json`文件的`ValAddress`地址产生了映射，以后别的普通账户要对一个验证者进行委托，委托的对象将会是`AccAddress`这个地址所代表的账户，而不是直接委托给来自于`priv_validator.json`文件的`ValAddress`地址，因为地址不可以委托，只能账户才能接受委托。




