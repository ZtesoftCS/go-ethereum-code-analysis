---
title: "详解Solidity合约数据存储布局"
menuTitle: "存储布局"
date: 2019-11-03T15:51:02+08:00
weight: 100000
description: "详解以太坊Solidity合约数据存储布局"
---


以太坊所设计的合约数据存储模型，并非常见方式。
因此，即使你身为程序员在理解存储模型时也会觉得新奇。
以太坊合约是经过 EVM 执行后，将从 KV 数据库中读写。这和常见的编程语言的内存数据模型差异很大。
这是因为合约在执行后必须方便存储到KV 数据库，也需要能拥有引用指针访问数据能力。
在主流编程语言中，数据的访问都可以通过指针访问，在以太坊中，访问数据是需要从 KV 数据中实时读取，因此在访问前必须知道某个数据确切的存储位置。
如何读写数据是由合约编译器决定，和 EVM 无关。这里我们讨论以太坊 **Solidity** 智能合约编程语言所设计的数据存储模型。

Solidity 合约数据存储采用的是为合约每项数据指定一个可计算的存储位置，数据存在容量为2<sup>256</sup>超级数组中，数组中每项数据的初始值为 0。
你不用担心存储会占用太多空间，实际上存储是稀疏的。在存储到 KV 数据库中时只有非零(空值)数据才会被写入。

![以太坊数据存储](https://img.learnblockchain.cn/book_geth/2019-11-3-21-30-13.png!de?width=600px&heigth=400px)

每个插槽可存储 32 字节数据：

![](https://img.learnblockchain.cn/book_geth/2019-11-3-21-44-32.png!de?width=600px)

当某项数据超过 32 字节，则需要占用多个连续插槽(data.length/32)。
因此，当数据长度是已知时，则存储位置将在编译时指定存储位置，而对于长度不确定的类型（如 动态数组、字典）则按一定规则计算存储位置。

2<sup>256</sup>是一个超级大的数字，足够容量合约需要任意大小的存储。

{{% notice tip%}}
2<sup>256</sup>是一个超级大的数字，等于2<sup>32</sup> * 8，而 2<sup>32</sup> 约等于40 亿。
如果你无法直观理解的的话，可以做一个比较：地球上的沙子总数量大约为“7.5 *  10<sup>15</sup>”，
而2<sup>256</sup>等于1.158*10<sup>77</sup>，相当于五倍多的全地区沙子总量。
{{% /notice %}}


## 定长数据存储

在 Solidity 语言中，一部分的值类型所需要占用的存储是确定的。
比如布尔类型，只需要占用一字节，uint16 只需要占用 2 字节。
Solidity 编译器在编译合约时，将严格的根据定义顺序，依次给他们设定存储位置。

```solidity
pragma solidity >0.5.0;

contract StorageExample {
    uint8  public a = 11;
    uint256 b=12;
    uint[2] c= [13,14];

    struct Entry {
        uint id;
        uint  value;
    }
    Entry d;
}
```

上面合约中，有定义 a、b、c、d 四个存储字段。a、b 分配在 0，1位置。
而字段 c 是定长 2 且元素类型是 uint，需要用 32 字节存储一个元素，一共需要占用两个插槽 2和 3。
字段 d 是一个结构类型数据，其中 Entry 的数据长度也是确定的 64 字节，因此字段 d 也占用两个插槽 4 和 5。

![](https://img.learnblockchain.cn/book_geth/2019-11-3-22-19-1.png!de?width=400px)

当数据类型是值类型（固定大小的值）时，编译时将严格根据字段排序顺序，给每个要存储的值类型数据预分配存储位置。
相当于已提前指定了固定不变的数据指针。

部署上面合约，根据合约地址可以直接通过`eth_getStorageAt(contractAddress,slot)`API 获取存储数据。

```js
var contractAddr="0xe700184a875390d7c98371769315E9A2504Ad556"; # 我部署上方合约的合约地址。
for(i=0;i<6;i++){
    console.log(web3.eth.getStorageAt(contractAddr,i))
}
// 输出
0x000000000000000000000000000000000000000000000000000000000000000b
0x000000000000000000000000000000000000000000000000000000000000000c
0x000000000000000000000000000000000000000000000000000000000000000d
0x000000000000000000000000000000000000000000000000000000000000000e
0x0000000000000000000000000000000000000000000000000000000000000000
0x0000000000000000000000000000000000000000000000000000000000000000
```

上面是根据存储位置遍历合约的所有存储， 存储到 DB 的数据是十六进制，我们可以直接使用工具类函数转换数据。
```
web3.toBigNumber(web3.eth.getStorageAt(contractAddr,0))
// 输出： 11
```
但如果数据长度是不确定的呢？如数组、Map等，或者说数据仅需要占用 1 字节呢？如 bool值。
在存储模型中有包含一点规则来定义存储布局。


{{% notice warning %}}
注意，本文脚本运行在 geth 控制台中，和 NodeJs 运行有所差异。geth 控制台中有修改 web3 方法定义。
{{% /notice %}}

{{% notice tip   %}}
**如何快速跑一个开发环境？**

1. 下载 geth 安装 https://geth.ethereum.org/downloads/
2. 命令行运行开发节点： `./geth --dev --rpc --rpccorsdomain "*" console`
3. 打开 https://remix.ethereum.org/ 编写合约
4. 修改 remix IDE 的连接环境，选择后，直接点击确定即可。
![20191107162515.png](https://img.learnblockchain.cn/book_geth/20191107162515.png!de?width=400px)
5. 此时，remix 已经连接到第二步运行的 geth 中。
{{% /notice %}}


## 紧凑存储

一大部分值类型实际上不需要用到 32 字节，如布尔型、uint1 到 uint256。
为了节约存储量，编译器在发现所用存储不超过 32 字节时，将会将其和后面字段尽可能的存储在一个存储中。

```solidity
pragma solidity >0.5.0;

contract StorageExample2 {
    uint256 a = 11; // 插槽 0
    uint8 b = 12; // 插槽1，1 字节
    uint128 c = 13; // 插槽1，16 字节
    bool d = true; // 插槽1，1 字节
    uint128 e =  14;//插槽2
}
```

上面合约总共使用 3 个插槽存储数据。

+ 字段 a 需要 32 字节占用 1 个插槽，存于插槽 0 中。
+ b 只需要 1 字节，存于插槽 1 中。
+ 因为 插槽 1 还剩余 31 字节可用，而 c 只需要 16 字节，因此 c 也可以存储在插槽 1 中。
+ 此时，插槽 1 剩余 15 字节，可以继续存放 d 的一字节。
+ 插槽 1 还剩余 14 字节，但是 e 需要 16 字节存储，插槽 1 已不能容纳 e。需将 e 存放到下一个插槽 2 中。

![合约的存储布局](https://img.learnblockchain.cn/book_geth/2019-11-6-21-56-39.png!de?width=600px)

上图是合约的存储布局，被紧凑地存放在插槽 1 中的 b、c、d 他们将依次从右往左存储于插槽 1 中。读取插槽 1 中的数据得到 data 为：

0x0000000000000000000000000000010000000000000000000000000000000d0c

如果希望得到b、c、d 的值，则需要进行分割读取。data 是一串 Hex 字符串，两个字符代表一个字节。

```js
data = web3.eth.getStorageAt(contractAddr,1);
b = parseInt(data.substr(66-1*2,1*2),16);
c = parseInt(data.substr(66-1*2-16*2,16*2),16);
d = parseInt(data.substr(66-1*2-16*2-1*2,1*2),16);
```

鉴于这种紧凑存储原则，有效降低了存储占用。而因以太坊存储是昂贵的，因此为了降低存储占用，
你在编写合约时，记得注意字段的**定义顺序**。

比如在合约中的结构类型字段，依次是 uint256、uint8和 uint8，占用两个插槽。如果你定义成： age、id、sex 顺序，则将占用 3 个插槽。
```solidity
contract StorageExample3 {
    struct User {
        uint256 id;
        uint8 age;
        uint8  sex
    }
}
```

但这种机制也引发了**另一个问题**。因为以太坊虚拟机每次读取数据都是 32 字节，当你的数据小于 32 字节时需要更多的指令操作才能将所需值取出。
如上面实例中，当你取  c 值时，首先要读取插槽 1 的 32 字节数据外，还需要截取 32 字节的中间一小部分。
在使得相比取 32 字节值的数据，需要花费更多的 gas 来获取小于 32 字节的数据。
当然这种开销，相对于更多的存储占用要便宜得多。

## 动态大小数据存储

当数据大小是不可预知时，无法在编译期直接确定其存储位置。因此 Solidity 在编译动态数字、字典数据时采用的是特定算法。

### 字符串

字符串 string 和 bytes 实际是一个特殊的 array ，编译器对这类数据有进行优化。如果 `string` 和 `bytes` 的数据很短。那么它们的长度也会和数据一起存储到同一个插槽。
具体为：

1. 如果数据长度小于等于 31 字节， 则它存储在高位字节（左对齐），最低位字节存储 length * 2。
2. 如果数据长度超出 31 字节，则在主插槽存储 length * 2 + 1， 数据照常存储在 keccak256(slot) 中。

以下面示例说明：

```solidity
contract StorageExample3 {
   string a  = "我比较短";
   string b  = "我特别特别长，已经超过了一个插槽存储量";
}
```

合约有两个字段 a 和 b，他们所需要占用的存储各不相同。根据规则一，a 的内容和长度一起存储在插槽 0 中。

```
data=web3.eth.getStorageAt('0x24aA059A03bC2f1EdC8412f673b6Bd3319A2c5CB',0)
//输出：`0xe68891e6af94e8be83e79fad0000000000000000000000000000000000000018`
```

a 占用存储 12 (0x18/2) 字节，根据长度可解码 a 的值：

```js
web3.toUtf8( data.substr(2,12*2))
```

而字段 b 需要占用57 字节 (=web3.fromUtf8('我特别特别长，已经超过了一个插槽存储量').length/2 -1)，已超过 31 字节。
那么将在插槽 1 中存储值 115(= 57 * 2 + 1): "0x0000000000000000000000000000000000000000000000000000000000000073"。
而 b 值起始存储在 keccak256(0x1) 中，需要使用连续两个插槽存储。


调用 SlotHelp 函数 `dataSolot(1)`，得到 b 字符串的起始存储位置：start=0xb10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf6。
而 b 字符串需要两个插槽存储，下一个存储位置是 start +1 。

```js
b1 = web3.eth.getStorageAt('0x0a4Efc37f85023Fae282DE0c885669DaEF02E02A',"0xb10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf6")
//0xe68891e789b9e588abe789b9e588abe995bfefbc8ce5b7b2e7bb8fe8b685e8bf
b2 = web3.eth.getStorageAt('0x0a4Efc37f85023Fae282DE0c885669DaEF02E02A',"0xb10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf7")
//0x87e4ba86e4b880e4b8aae68f92e6a7bde5ad98e582a8e9878f00000000000000
str = web3.toUtf8(b1+b2.substr(2))
```

至此，我们已得到完整的 b 字符串值。bytes 也是相同方式，不再复述。


{{% notice tip%}}
keccak256 是 Solidity 中合约中使用的 sha3 函数，不等同于 web3.sha 。
为了计算方便，我定义了一个 Solot 的帮助类来计算存储位置，具体见[文档底部](#SlotHelp)。
{{% /notice%}}

### 动态数组

动态数组 `T[]` 由两部分组成，数组长度和元素值。在 Solidity 中定义动态数组后，将在定义的插槽位置存储数组元素数量，
元素数据存储的起始位置是：keccak256(slot)，每个元素需要根据下标和元素大小来读取数据。

```solidity

contract StorageExample4 {

   uint16[] public a =  [401,402,403,405,406];

   uint256[] public b =  [401,402,403,405,406];
}
```

上面有定义两个数组 a 和 b，都有 5 个相同初始值。
a 和 b 在插槽 0 和 1 上分别存储他们的长度值 5，而数组元素值存储有所不同（紧缩存储）。
因为数组 a 元素宽度(width)是 2 字节，因此一个插槽可以存储 16 个元素，而数组 b 则只能是一个插槽存储一个元素（uint256 需要用 32 字节存储）。

已知:

+ keccak256(0)=0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563
+ keccak256(1)=0xb10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf6

如果要获取 a[3] 值，首先确认 a[3]的存储位置:

`keccak256(0)+ index* width / 32` = 0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563

可得到插槽中存储的数据:

data=0x0000000000000000000000000000000000000000000001960195019301920191

根据第一项以低位对齐(右对齐)的存储方式，可以知道 a[3] 需要向左偏移 `index*width`= 6 个字节，值为`data.substr(32*2+2-3*2*2,2*2)`

![以太坊技术与实现-图1](https://img.learnblockchain.cn/book_geth/以太坊技术与实现-图2019-11-6-22-7-15!de?width=600px)

同样取值b[3]，因为元素宽度为 32，一个插槽就是存储一个元素。


### 字典 Mapping

字典的存储布局是直接存储 Key 对应的 value，每个 Key 对应一份存储。一个 Key 的对应存储位置是 `keccak256(key.slot)`，其中`.`是拼接符合，实际上编码时进行拼接`abi.encodePacked(key,slot)`;
可直接获得  map[key] 的存储位置。

```solidity
contract StorageExample5 {
   mappping(uint256 => string) a;

   constructor()public {
       a["u1"]=18;
       a["u2"]=19;
   }
}
```

如上面示例中，字段 a 定义在 0 插槽，初始化合约时有添加两个key u1 和 u2。那么 u1的存储位置就是：
`keccak256("u1",0)`，u2 存储在 ``keccak256("u2",0)``中。调用 `SlotHelp.mappingValueSlotString(0,"u1")` ([见下][1]) 可计算出存储位置，分别是：

1. keccak256("u1",0) = 0x666a0898319983ee51fdb14dca8cb63a131f53ef02192cda872152628bb15fd7
2. keccak256("u2",0) = 0xb8f3bac818d08a6d5c3fc2cecdc63de9db8e456c49b3877ea67282ec9d7ef62c

取值为：

```js
addr="0xB793D15FF1e9F652D66a58E7C963c4c6766DA193" #部署后的合约地址
web3.eth.getStorageAt(addr,'0x666a0898319983ee51fdb14dca8cb63a131f53ef02192cda872152628bb15fd7')
// Result
// "0x0000000000000000000000000000000000000000000000000000000000000012"
web3.eth.getStorageAt(addr,'0xb8f3bac818d08a6d5c3fc2cecdc63de9db8e456c49b3877ea67282ec9d7ef62c')
// Result
// "0x0000000000000000000000000000000000000000000000000000000000000013"
```

{{% notice info %}}
思考：为何在合约中无法对 mapping 进行遍历？可在评论中留言。
{{% /notice %}}

### 组合型

当前数据类型不是基础类型时，是进行内部递归处理，遵守上述规则来存储数据的。
比如 结构、map 的值是一个结构等等。下面通过一个稍微复杂的合约来画出合约的存储分布。

```solidity
pragma solidity >0.5.0;

contract StorageExample6 {
    uint256 a = 11;
    uint8 b = 12;
    uint128 c = 13;
    bool d = true;
    uint128 e =  14;
    uint256[] public array =  [401,402,403,405,406];

    address owner;
    mapping(address => UserInfo) public users;
    string  str="name value";

    struct UserInfo {
        string name;
        uint8 age;
        uint8 weight;
        uint256[] orders;
        uint64[3] lastLogins;
    }

   constructor()public {
       owner=msg.sender;

       addUser(owner,"admin",17,120);
   }

   function addUser(address user,string memory name,uint8 age,uint8 weight) public {
       require(age>0 && age <100 ,"bad age");

       uint256[] memory orders;
       uint64[3] memory logins;

       users[user] = UserInfo({
           name: name, age:    age,  weight:weight,
           orders:orders,  lastLogins:logins
       });
   }
   function addLog(address user,uint64 id1,uint64 id2,uint64 id3) public{
       UserInfo storage u = users[user];
       assert(u.age>0);

       u.lastLogins[0]=id1;
       u.lastLogins[1]=id2;
       u.lastLogins[2]=id3;
   }

   function addOrder(address user,uint256 orderID) public{
       UserInfo storage u = users[user];
       assert(u.age>0);
       u.orders.push(orderID);
   }
   function getLogins(address user) public view returns (uint64,uint64,uint64){
        UserInfo storage u = users[user];
       return  (u.lastLogins[0],u.lastLogins[1],u.lastLogins[2]);
   }
   function getOrders(address user) public view returns (uint256[] memory){
        UserInfo storage u = users[user];
       return  u.orders;
   }
}
```

![Solidity 合约存储布局示例.png](https://img.learnblockchain.cn/book_geth/20191107160911.png!de)

上图是针对上面合约 StorageExample6 而绘制的数据存储布局，基本包括了常见定义的数据存储。你可以根据前面所将的取数方式来尝试部署合约和读取合约数据。
有任何疑问，都可以在下方留言。

{{% notice info %}}
思考：通过 keccak256(...) 来确定数据的存储插槽，是否出现重复，导致数据被覆盖？欢迎在评论区留言。
{{% /notice %}}


## SlotHelp

```solidity
pragma solidity >0.5.0;


contract SlotHelp {

    // 获取字符串的存储起始位置
    function dataSolot(uint256 slot) public pure returns (bytes32) {
        bytes memory slotEncoded  = abi.encodePacked(slot);
        return  keccak256(slotEncoded);
    }

    // 获取字符串 Key 的字典值存储位置
    function mappingValueSlotString(uint256 slot,string memory key ) public pure returns (bytes32) {
        bytes memory slotEncoded  = abi.encodePacked(key,slot);
        return  keccak256(slotEncoded);
    }
}
```
参考资料：

1. https://solidity.readthedocs.io/en/v0.5.10/types.html
2. https://medium.com/@hayeah/diving-into-the-ethereum-vm-the-hidden-costs-of-arrays-28e119f04a9b


[1]: #slothelp