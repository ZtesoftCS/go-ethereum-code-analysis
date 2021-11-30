## 一些术语理解

### 什么是智能合约
  智能合约(smart code)其实质就是一串代码，目的很明确期望用代码来代替一些需要公信力的地方， 代码的执行不会受人为意志而转移。 只要代码被公开，所有执行的结果就是可预知的， 不会出现黑幕， 不会出现暗箱操作等。
  
### 什么是evm
  既然智能合约是一串代码, 那它就需要有执行的宿主环境， 因此evm(以太坊虚拟机)就是执行智能合约的宿主机环境。 
  
### 什么是solidity
  solidity是一种编程语言， 编写代码有很多种语言， C， C++， 而solidity就是一种用于编写以太坊智能合约的语言， 以太坊官方之前推出了多种智能合约编程语言， 目前看来使用最广泛和支持最好的既是solidity。
  
### 什么是solc 
  如果我们写过C/C++ 我们肯定知道gcc/g++, solc就是类似于gcc编译器的东西。 
  
### 一段solidity的代码示例
```solidity
pragma solidity ^0.4.21;

interface BaseInterface {
    function CurrentVersion() external view returns(string);
}

contract Helloworld {
    uint256 balance;
    event Triggle(address, string);
    mapping(address=>uint256) _mapamount; 
    
    constructor() public {
        balance = 6000000000;
        _mapamount[0] = 100;
        _mapamount[1] = 200;
    }
    
    function getbalance() public  returns (address, uint256) {
        emit Triggle(msg.sender, "funck");
        return (msg.sender, balance--);
    }
    
    function onlytest() public{
        _mapamount[1] = 100;
        emit Triggle(msg.sender, "onlytest");
    }
    
    function setBalance(uint256 tmp) public {
        balance = tmp;
    }
    
    function getVersion(address contractAddr) public view returns (string) {
        BaseInterface baseClass = BaseInterface(contractAddr);
       return baseClass.CurrentVersion();
    }
    
}

```

### 什么是以太坊账户体系
账户可以类比我们现实中的银行账户的概念， 一个银行账户至少有卡号， 密码， 你的所有交易流水等信息。
以太坊是有两种账户， 一种称为普通的账户， 类似于我们的银行账户， 还有一种类似于合约账户， 代表着智能合约代码。

先说普通账户:
账户是有地址的， 地址对应着我们的银行卡号， 有了地址我们就能查询到所有与其相关的交易。 
除了账户还有私钥，私钥类似于银行卡的密码， 唯一不同的地方在于一个银行卡我们可以随意修改它的密码， 但是对于以太坊普通账户地址(注意是普通账户)， 不能修改私钥， 地址是根据私钥推导出来的(反之则不行)。 私钥是不可泄露不可更改的。
除了账户还有nonce值， nonce值代表当前账户执行交易的次数。 每次执行交易加1.
地址通过私钥-->公钥-->公钥SHA3-->取前20个字节的16进制字符串表示形式

再说智能合约账户:
智能合约账户的地址格式和普通账户是一样的， 只根据地址是区分不出它是智能合约还是普通账户地址。 
但是智能合约的地址是没有私钥的，为什么没有私钥也能创建出地址呢？
试想一下，一串智能合约代码如果要发送到以太坊节点上， 必然需要有一个普通账户作为发起方， 当一个普通账户发起一笔发布智能合约的交易时, 根据from地址及其当前nonce进行hash运算取前20个字节的16进制字符串即为智能合约账户的地址。
所以说地址格式一样，只能根据账户地址去节点中查询才能知道代表的是何种账户类型。

注意:
智能合约账户不仅包含了智能合约编译后的字节码， 它依然可以进行以太坊收款和转账。 只是实现方式是通过智能合约代码来实现而已。




## 智能合约的创建流程

有了上面的术语理解， 会对我们理解以太坊智能合约有很大的帮助， 至少会让我们知道智能合约是什么， 它的作用是干嘛的。 可是对于它到底是如何工作的。 它是如何会被发布到所谓的各个以太坊节点之中的。 又是如何去调用的等等需要问题都是不了解的。 下面一步步去说明这些过程。

为了更容易的说明一个问题， 我们举例来描述其过程。

假设小明最近在和他的2个兄弟(小米和小刚)一起玩石头剪刀布的游戏， 赢的人可以继承老爷子上亿资产。 三个人现在都怕对方使诈。 在出招的最后一刻变卦赢得了比赛。 
那如果这个时候我们用智能合约代码来决定胜负似乎就没有问题了。
我们先实现这个简单功能的代码:

```
pragma solidity ^0.4.21;

contract Winner {
    mapping(string=>uint8) _mapActions;
    mapping(address=>bool) _AllAccounts;
    mapping(address=>uint8) _AccountsActions;
    bool start; 
    
    // 这个是构造函数 在合约第一次创建时执行
    constructor() public {
        _mapActions["scissors"] = 1;
        _mapActions["hammer"] = 2;
        _mapActions["cloth"] = 3;
        
        _AllAccounts[0x763418009b636593e86256ffa32bef1b0218a1e1] = true;  // xiaomi
        _AllAccounts[0x14723a09acff6d2a60dcdf7aa4aff308fddc160c] = true; // xiaoming
        _AllAccounts[0x583031d1113ad414f02576bd6afabfb302140225] = true; // xiaogang
        
        _AccountsActions[0x763418009b636593e86256ffa32bef1b0218a1e1] = 0;
        _AccountsActions[0x14723a09acff6d2a60dcdf7aa4aff308fddc160c] = 0;
        _AccountsActions[0x583031d1113ad414f02576bd6afabfb302140225] = 0;
    }
    
    // 设置执行动作  要求只能是scissors hammer cloth 
    // 并且要求只能是上述要求的三个以太坊地址
    function setAction( string action) public  returns (bool) {
        if (_mapActions[action] == 0 ) {
            return false;
        }
    
        if (!_AllAccounts[msg.sender]) {
            return false;
        }
        _AccountsActions[msg.sender] = _mapActions[action];
        return true;
    }
    
    function reset() private {
        _AccountsActions[0x763418009b636593e86256ffa32bef1b0218a1e1] = 0;
        _AccountsActions[0x14723a09acff6d2a60dcdf7aa4aff308fddc160c] = 0;
        _AccountsActions[0x583031d1113ad414f02576bd6afabfb302140225] = 0;
    }
    
    function whoIsWinner() public returns (string, bool) {
        if (
            _AccountsActions[0x763418009b636593e86256ffa32bef1b0218a1e1] == 0 ||
            _AccountsActions[0x14723a09acff6d2a60dcdf7aa4aff308fddc160c] == 0 ||
            _AccountsActions[0x583031d1113ad414f02576bd6afabfb302140225] == 0
            ) {
                reset();
                return ("", false);
            }
        uint8  xiaomi = _AccountsActions[0x763418009b636593e86256ffa32bef1b0218a1e1];
        uint8  xiaoming = _AccountsActions[0x14723a09acff6d2a60dcdf7aa4aff308fddc160c];
        uint8  xiaogang = _AccountsActions[0x583031d1113ad414f02576bd6afabfb302140225];
        if (xiaomi != xiaoming && xiaomi != xiaogang && xiaoming != xiaogang) {
            reset();
            return ("", false);
        }
        
        if (xiaomi == xiaoming) {
            if (winCheck(xiaomi, xiaogang)) {
                return ("小刚", true);
            }else{
                reset();
                return ("", false);
            }
        }
        if (xiaomi == xiaogang) {
            if (winCheck(xiaomi, xiaoming)) {
                return ("小明", true);
            }else{
                reset();
                return ("", false);
            }
        } 
        if (xiaoming == xiaogang) {
            if (winCheck(xiaoming, xiaomi)) {
                return ("小米", true);
            }else{
                reset();
                return ("", false);
            }
        }
        reset();
        return ("", false);
    }
    
    function winCheck(uint8 a, uint8 b ) private returns( bool) {
        if(a == 1 && b==3) {
            return true;
        }else if (a==2 && b==1) {
            return true;
        }else if (a==3 && b==2) {
            return true;
        }
        return false;
    }
    
}

```
想象一下, 如果小明把这个代码发送到了以太坊上, 然后大家都调用智能合约的setAction函数设置自己想出的动作, 当大家都设置完成后, 最后再调用whoIsWinner函数来决定谁是胜负。 这个方案可是比葛优老师的分歧终端机逼格搞多了。

写到这里我并不是只是给大家讲一个段子， 只是期望以一个类似的生活分歧场景来引出智能合约在其中的解决方案。 作为技术研究者， 到了这里也只是刚刚开始， 下面我们要分析整个流程是如何实现的。

### 智能合约代码编写 

  假设小明联合两个兄弟一起写了上述的代码， 大家一起分析了代码， 并且认为其中没有漏洞，比如当有第四个人也想调用这个函数如何剔除它。 比如三个人一次没有决定胜负时要重新开始，比如兄弟中有一个人在一轮比赛期间没有给出自己的动作。
  最后三个人对上述代码的认同一致。 认为代码没有漏洞。 
  
### 智能合约编译
  代码如果想被虚拟机执行， 那么它必须应该是字节码。 这个时候就需要将上述代码进行编译了。 可以使用以太坊官方的solc进行编译。 或者使用truffle框架进行编译。最后获取到字节码。
  其字节码的形式类似于下面这个样子:
  "608060405234801561001057600080fd5b506001600060405180807f73636973736f72730....."
  
### 发布智能合约到以太坊各个节点

  这个时候假设小刚(0x583031d1113ad414f02576bd6afabfb302140225)想主动把此合约发布到节点上， 然后他构建了类似交易
  {
    "from": 0x583031d1113ad414f02576bd6afabfb302140225,
    "nonce": 100,
    "input":  "608060405234801561001057600080fd5b506001600060405180807f73636973736f72730.....",
    "to": nil
    "timestamp": 2018-11-27 12:32:48,
    "sign": ""
    ...
  }
  然后他用自己的私钥对上述内容进行了签名， 并将整个消息编码之后发给了一个以太坊节点。
  
### 以太坊节点部署智能合约

  我们假设有一个以太坊节点对接收到的编码消息进行了解码还原了上述的交易内容。
  验证发起方是否签名正确， 验证发起方余额是否足够， 验证发起方nonce是否是发起方最后一次持续交易的nonce加一。 然后开始执行交易内容。同时广播这个交易到它知道的所有相邻节点。
  当它发现to为nil, 那么它认为这就是要部署一个智能合约的节奏。
  部署智能合约前要创建一个智能合约账户。 所以此智能合约的账户地址为 hex(hash(from, nonce)[0:20])  假设创建的智能合约地址为0xfc713aab72f97671badcb14669248c4e922fe2bb
  合约的字节码为执行evm执行完input字节码返回的内容。 这里可能大家会有疑虑， 为什么合约字节码不直接是input, 我们在编写智能合约代码时会在构造函数进行一些初始化的内容。 那么在部署合约之前这些初始化的动作应该也要初始化。所以在input执行之后除了返回可执行的字节码之外, 一些初始化动作也就被执行完成了。
  
  这样一来， 所有的节点均会执行此交易。 智能合约代码在所有的以太坊节点都会部署一份。
  
### 智能合约调用

  当合约被部署完成之后, 接下来就是要调用合约了。 比如小明(0x763418009b636593e86256ffa32bef1b0218a1e1)想调用合约设置自己出剪刀的动作。 整个流程如下:
  
  小明也会发起一笔交易交易， 交易结构类似下面:
  {
    "from": "0x763418009b636593e86256ffa32bef1b0218a1e1",
    "to": "0xfc713aab72f97671badcb14669248c4e922fe2bb",  // 合约地址
    "value": 0,
    "input": "0x3e0e455a0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000668616d6d65720000000000000000000000000000000000000000000000000000",
    "gas": 300000000,
    "sign": ""
    "nonce" 101
  }
  
  注意上面的交易内容， from就是合约的调用者, to就是合约地址。 value表示向往此合约账户转账的以太坊金额。 我们现在专门关注一下input的内容。 
  input初看是一串数字。 其实其前四个字节是调用函数的hash值也即是'setAction(string)' hash运算之后返回的内容。 后面的字符串就是以太坊对输入的参数编码之后的内容。
  
  当此交易被广播到节点之后， 校验流程和上述部署合约流程一致。
  校验通过之后会被此节点中继到所有相邻的节点 进而全网收到此交易。
  
  首先节点发现to是一个合约地址， 进而加载合约地址， 解析input之后发现是调用setAction("hammer") 于是evm会执行setAction函数。 同时把执行结果放入交易收据详情中。
  
  这样一次智能合约调用就算完成了。
  

### 总结
  写到这里整个智能合约的概述也就说完了。 从以太坊节点看来， 不论是合约部署还是调用合约函数对其来说都是一次交易的过程。 只要有evm,  有图灵完备的语言。 就能实现想要的功能。

### 关于ERC20代币

  如果问以太坊的智能合约应用最广泛的地方在哪里， 肯定就是发币了。 虽然可能V神也没想到世界还没被改变， ICO(圈钱)的方式倒是又多出了一个。
  
  既然是数字token， 代码实现起来就可以有各种各样的方案。 实质无外乎就是记录下每个用户拥有的数字token数量， 具有转账，查询余额等功能就行了。 上面我们说到只要调用对应相关的函数去执行即可完成相关的功能。 可是这个时候假如某个ICO方A 写了代币转账功能， 它的转账函数叫做tx(uint256). 
  那么如果想调用它的转账就要调用tx这个函数， 我们知道只要调用函数不相同， input的内容就不会一样。 如果所有的ICO方写的这些函数名称均不一样。 调用者就要查看每一个ICO方的合约代码。 
  于是这个时候ERC20就来了， 它定义了一些发币(圈钱)的规范。也即是如果你想发行ICO， 最好按着我的规范来， 这样大家用起来就跟方便了。ERC20简而言之就是定义了下面几个接口
  
  ```solidity
  contract ERC20 {

    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 value);  // 转账触发
    event Approval(address indexed owner, address indexed spender, uint256 value); // 容许提取触发

    function balanceOf(address who) public view returns (uint256);  // 查询余额函数
    function transfer(address to, uint256 value) public returns (bool);   // 进行转账函数

    function approve(address spender, uint256 value) public returns (bool);   // 容许某个地址提款
    function transferFrom(address from, address to, uint256 value) public returns (bool);  // 从一方向另一方转账的余额

}
  ```
  有了这个规范， 各个ICO方在发行token时都实现上面的接口， 这样无论任何的ERC20代币， 均可以用一套方法实现所有代币转账,查询余额等功能。
  

  
  
  
### 分析一下PAX稳定币的智能合约代码


```solidity
pragma solidity ^0.4.24;
pragma experimental "v0.5.0";

// 导入外部包  此包中主要是一些
// 安全的数学运算 
// 因为在一些场景 出现了数据溢出没有考虑的问题导致了
// 一些ico币直接归零
import "./zeppelin/SafeMath.sol";

contract PAXImplementation {

    using SafeMath for uint256;
    bool private initialized = false;

    // 定义了ERC20规定的代币名称 符号 精度
    mapping(address => uint256) internal balances;
    uint256 internal totalSupply_;
    string public constant name = "PAX"; // solium-disable-line uppercase
    string public constant symbol = "PAX"; // solium-disable-line uppercase
    uint8 public constant decimals = 18; // solium-disable-line uppercase

    // ERC20 DATA
    mapping (address => mapping (address => uint256)) internal allowed;

    // OWNER DATA
    address public owner;

    // PAUSABILITY DATA
    bool public paused = false;

    // LAW ENFORCEMENT DATA
    address public lawEnforcementRole;
    mapping(address => bool) internal frozen;

    // SUPPLY CONTROL DATA
    address public supplyController;

    // 定义触发时间  当转账或者授权别人转账时 调用此事件  当调用时 其实质会在以太坊节点区块上写入日志。
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    // OWNABLE EVENTS
    event OwnershipTransferred(
        address indexed oldOwner,
        address indexed newOwner
    );

    // PAUSABLE EVENTS
    event Pause();
    event Unpause();

    // LAW ENFORCEMENT EVENTS
    event AddressFrozen(address indexed addr);
    event AddressUnfrozen(address indexed addr);
    event FrozenAddressWiped(address indexed addr);
    event LawEnforcementRoleSet (
        address indexed oldLawEnforcementRole,
        address indexed newLawEnforcementRole
    );

    // SUPPLY CONTROL EVENTS
    event SupplyIncreased(address indexed to, uint256 value);
    event SupplyDecreased(address indexed from, uint256 value);
    event SupplyControllerSet(
        address indexed oldSupplyController,
        address indexed newSupplyController
    );

    /**
     * FUNCTIONALITY
     */

    // INITIALIZATION FUNCTIONALITY

    /**
    合约部署时的初始化过程
    设置合约拥有者为部署合约的账户
    设置总供应量为0
    并保证此函数只会被调用一次
     */
    function initialize() public {
        require(!initialized, "already initialized");
        owner = msg.sender;
        lawEnforcementRole = address(0);
        totalSupply_ = 0;
        supplyController = msg.sender;
        initialized = true;
    }

    /**
    合约的构造函数 调用上面的初始化函数 并且设置暂停交易 
     */
    constructor() public {
        initialize();
        pause();
    }

    // ERC20 BASIC FUNCTIONALITY

    /**
    ERC20接口 返回总的供应量
    */
    function totalSupply() public view returns (uint256) {
        return totalSupply_;
    }

    /*
    转账函数 实现将调用者的token转给其他人
    msg.sender 即为合约的调用者 
    并且此函数要求必须是非暂停状态  即whenNotPaused返回真
    
    这个函数有需要验证条件 
    1.交易没有被暂停
    2.接收方地址不能是0
    3.接收方和发起方均不可以是冻结地址
    4.转账的token余额要足够。
    */
    function transfer(address _to, uint256 _value) public whenNotPaused returns (bool) {
        require(_to != address(0), "cannot transfer to address zero");
        require(!frozen[_to] && !frozen[msg.sender], "address frozen");
        require(_value <= balances[msg.sender], "insufficient funds");

        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(_value);
        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    /**
    ERC20接口 返回某个账户的token余额
    */
    function balanceOf(address _addr) public view returns (uint256) {
        return balances[_addr];
    }

    // ERC20 FUNCTIONALITY

    /*
      ERC20接口 实现了 _from地址下容许调用方可以转出金额到其他_to
      此函数要求必须是非暂停状态
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    )
    public
    whenNotPaused
    returns (bool)
    {
        require(_to != address(0), "cannot transfer to address zero");
        require(!frozen[_to] && !frozen[_from] && !frozen[msg.sender], "address frozen");
        require(_value <= balances[_from], "insufficient funds");
        require(_value <= allowed[_from][msg.sender], "insufficient allowance");

        balances[_from] = balances[_from].sub(_value);
        balances[_to] = balances[_to].add(_value);
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
        emit Transfer(_from, _to, _value);
        return true;
    }

    /**
      ERC20接口 实现调用方容许_spender 可以从我的账户转出的金额  这个函数和上面的函数是相对应的。
      只有一个账户容许了其他账户能从我的账户转出的金额 上述的函数才能转账成功。
     */
    function approve(address _spender, uint256 _value) public whenNotPaused returns (bool) {
        require(!frozen[_spender] && !frozen[msg.sender], "address frozen");
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    /**
    ERC20接口 返回_owner账户容许_spender账户从自己名下转移出去的资产数量
     */
    function allowance(
        address _owner,
        address _spender
    )
    public
    view
    returns (uint256)
    {
        return allowed[_owner][_spender];
    }

    // OWNER FUNCTIONALITY

    /**
     这个函数被称为修饰函数 上面的whenNotPaused 也是一个修饰函数  实质是一种断言。 只有
     断言通过 才会执行函数内部的内容
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "onlyOwner");
        _;
    }

    /*
    将只能合约的拥有者转给别人
     */
    function transferOwnership(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "cannot transfer ownership to address zero");
        emit OwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }

    // PAUSABILITY FUNCTIONALITY

    /**
     *  修饰函数 要求处于非暂停交易状态
     */
    modifier whenNotPaused() {
        require(!paused, "whenNotPaused");
        _;
    }

    /**
     * 只有合约的拥有者才可以设置暂停交易
     */
    function pause() public onlyOwner {
        require(!paused, "already paused");
        paused = true;
        emit Pause();
    }

    /**
     * 只有合约的拥有者才能取消暂停交易
     */
    function unpause() public onlyOwner {
        require(paused, "already unpaused");
        paused = false;
        emit Unpause();
    }

    // LAW ENFORCEMENT FUNCTIONALITY

    /**
     设置一个法定的的强制角色 这个角色可以冻结或者解冻别人账户的token
     设置一个这样的角色要求首先调用方要么是合约的拥有者 要么自己已经是法定的强制者
     * @param _newLawEnforcementRole The new address allowed to freeze/unfreeze addresses and seize their tokens.
     */
    function setLawEnforcementRole(address _newLawEnforcementRole) public {
        require(msg.sender == lawEnforcementRole || msg.sender == owner, "only lawEnforcementRole or Owner");
        emit LawEnforcementRoleSet(lawEnforcementRole, _newLawEnforcementRole);
        lawEnforcementRole = _newLawEnforcementRole;
    }

    // 断言函数 要求调用方必须是强制者角色
    modifier onlyLawEnforcementRole() {
        require(msg.sender == lawEnforcementRole, "onlyLawEnforcementRole");
        _;
    }

    /**
      冻结某个账户的token  使用了断言 onlyLawEnforcementRole 也是只有调用方角色是
      法定强制者才有权限冻结别人的token
     */
    function freeze(address _addr) public onlyLawEnforcementRole {
        require(!frozen[_addr], "address already frozen");
        frozen[_addr] = true;
        emit AddressFrozen(_addr);
    }

    /**
        解冻某个账户的token  使用了断言 onlyLawEnforcementRole 也是只有调用方角色是
      法定强制者才有权限解冻别人的token
     */
    function unfreeze(address _addr) public onlyLawEnforcementRole {
        require(frozen[_addr], "address already unfrozen");
        frozen[_addr] = false;
        emit AddressUnfrozen(_addr);
    }

    /**
    摧毁冻结账户的token 也就是说如果这个地址是一个冻结地址调用这个函数会把这个地址的token销毁同时总供应数量也会被减少
    当然这个函数也不是谁都可以调用的 只有法定的强制者才有权限
     */
    function wipeFrozenAddress(address _addr) public onlyLawEnforcementRole {
        require(frozen[_addr], "address is not frozen");
        uint256 _balance = balances[_addr];
        balances[_addr] = 0;
        totalSupply_ = totalSupply_.sub(_balance);
        emit FrozenAddressWiped(_addr);
        emit SupplyDecreased(_addr, _balance);
        emit Transfer(_addr, address(0), _balance);
    }

    /**
    用于检查某个地址是否被冻结了
    */
    function isFrozen(address _addr) public view returns (bool) {
        return frozen[_addr];
    }

    // SUPPLY CONTROL FUNCTIONALITY

    /**
    设置token供应量的控制着 在合约初始化时 token供应量是合约发起则  调用这个函数可以更改
    这个函数只有调用方已经是token供应量控制着或者整个合约的拥有者才能调用成功
    也就是在整个合约中 合约的拥有者实质是可以控制一切权限的。 它能更改法定强制者 更改总token
    供应量的控制者。
     */
    function setSupplyController(address _newSupplyController) public {
        require(msg.sender == supplyController || msg.sender == owner, "only SupplyController or Owner");
        require(_newSupplyController != address(0), "cannot set supply controller to address zero");
        emit SupplyControllerSet(supplyController, _newSupplyController);
        supplyController = _newSupplyController;
    }

    modifier onlySupplyController() {
        require(msg.sender == supplyController, "onlySupplyController");
        _;
    }

    /**
    增加总的token供应量 并把新增供应量加到supplyController这个账户的名下。
     */
    function increaseSupply(uint256 _value) public onlySupplyController returns (bool success) {
        totalSupply_ = totalSupply_.add(_value);
        balances[supplyController] = balances[supplyController].add(_value);
        emit SupplyIncreased(supplyController, _value);
        emit Transfer(address(0), supplyController, _value);
        return true;
    }

    /**
    减少总的token供应量 待减少供应量从supplyController这个账户的名下减掉 。
    这个函数要求supplyController 
     */
    function decreaseSupply(uint256 _value) public onlySupplyController returns (bool success) {
        require(_value <= balances[supplyController], "not enough supply");
        balances[supplyController] = balances[supplyController].sub(_value);
        totalSupply_ = totalSupply_.sub(_value);
        emit SupplyDecreased(supplyController, _value);
        emit Transfer(supplyController, address(0), _value);
        return true;
    }
}

```
  
### PAX稳定币功能概述
PAX除了具有这个ERC20的功能外，还具有一些其他功能:

1. 可以暂停整个代币转账
2. 可以增加或者减少整个代币的数量
3. 可以任意冻结或者解冻某个账户的代币
4. 可以销毁某个冻结账户的代币
5. 可以转移合约控制权。可以转移总供应量控制权。 

总的来说PAX币做的限制特别多， 它的合约拥有机会可以做任何事情。 就算token转移给你了， 依然能分分钟钟消失。
  
  
  

## 最后
智能合约工作原理，整个开发，部署，调用流程也就这么多。 许多小细节可能没有详细说明， 但是最重要的部分已经进行了描述。
关于solidity语法， 如何使用truffle进行智能合约的开发，如何进行开发调试的等以后具体详细说明。

