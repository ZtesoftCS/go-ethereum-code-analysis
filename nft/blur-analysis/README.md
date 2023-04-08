# blur-analysis

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [1. BlurSwap](#1-blurswap)
- [2. BlurExchange](#2-blurexchange)
  - [2.1 代码地址](#21-%E4%BB%A3%E7%A0%81%E5%9C%B0%E5%9D%80)
  - [2.2 整体架构](#22-%E6%95%B4%E4%BD%93%E6%9E%B6%E6%9E%84)
  - [2.3 BlurExchange](#23-blurexchange)
- [3. PolicyManager](#3-policymanager)
  - [3.1 MatchingPolicy](#31-matchingpolicy)
- [4. BlurPool](#4-blurpool)
- [5. Blur Bid](#5-blur-bid)
  - [5.1 出价](#51-%E5%87%BA%E4%BB%B7)
  - [5.2 Opensea Offer](#52-opensea-offer)
  - [5.3 Blur Bid](#53-blur-bid)
- [6. Opensea 和 版税](#6-opensea-%E5%92%8C-%E7%89%88%E7%A8%8E)
- [7. 总结](#7-%E6%80%BB%E7%BB%93)
- [8. 参考](#8-%E5%8F%82%E8%80%83)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## 1. BlurSwap

<https://etherscan.io/address/0x39da41747a83aee658334415666f3ef92dd0d541>

BlurSwap 合约， fork 自 GemSwap。二者代码一致。

主要用于处理聚合交易相关逻辑。

## 2. BlurExchange

<https://etherscan.io/address/0x000000000000ad05ccc4f10045630fb830b95127>

BlurExchange 合约。Blur 自建的交易市场合约。

BlurExchange 的交易模型于 Opensea 一样是中央订单簿的交易模型，都是由链下的中心化的订单簿和链上的交易组成。

其中链下的订单簿负责存储用户的挂单信息，并对订单进行撮合。最终的成交和转移 NFT 是由 BlurExchange 来负责的。

### 2.1 代码地址

Blur 官方没有给出具体的代码仓库地址。不过我在 GitHub 上找到了下面这个代码仓库，应该是之前提交审计的时候留下来的。

<https://github.com/code-423n4/2022-10-blur>

ps: 这个代码库里的代码跟最新的实现合约有了不小的差别，仅做参考。

### 2.2 整体架构

![](exchange_architecture.png)

<https://etherscan.io/viewsvg?t=1&a=0x39da41747a83aeE658334415666f3EF92DD0D541>

![](mainnet-0x39da41747a83aee658334415666f3ef92dd0d541.svg)

按照模块可以分为一下几类：

1. BlurExchange：主合约，负责交易的执行。
2. PolicyManager：订单交易策略管理者。
3. MatchingPolicy：订单交易策略，负责判断买单、买单是否可以匹配。
4. ExecutionDelegate：负责具体的转移代币的逻辑。

### 2.3 BlurExchange

这是一个 upgradeable 合约，因此会有不同版本的实现合约。

目前实现合约的地址是 <https://etherscan.io/address/0x983e96c26782a8db500a6fb8ab47a52e1b44862d>

#### 2.3.0 数据结构

```solidity
// 交易方向
enum Side { Buy, Sell }
// 签名类型
enum SignatureVersion { Single, Bulk }
// 资产类型
enum AssetType { ERC721, ERC1155 }

// 收费详情
struct Fee {
    uint16 rate; // 比率
    address payable recipient; // 接收者
}

// 订单数据
struct Order {
    address trader; // 订单创建者
    Side side; // 交易方向
    address matchingPolicy; // 交易策略
    address collection; // 合约地址
    uint256 tokenId; // tokenId
    uint256 amount; // 数量
    address paymentToken; // 支付的代币
    uint256 price; // 价格
    uint256 listingTime; // 挂单时间
    /* Order expiration timestamp - 0 for oracle cancellations. */
    uint256 expirationTime; // 过期时间，oracle cancellations 的是 0
    Fee[] fees; // 费用
    uint256 salt;
    bytes extraParams; // 额外数据，如果长度大于 0，且第一个元素是 1 则表示是oracle authorization
}

// 订单和签名数据
struct Input {
    Order order; // 订单数据
    uint8 v; 
    bytes32 r;
    bytes32 s;
    bytes extraSignature; // 批量订单校验和 Oracle 校验使用的额外数据
    SignatureVersion signatureVersion; // 签名类型
    uint256 blockNumber; // 挂单时的区块高度
}

// 交易双方的数据
struct Execution {
  Input sell;
  Input buy;
}

```

#### 2.3.1 需要注意的成员变量

##### 2.3.1.1 isOpen

交易开启和关闭的开关。

设置的时候会发出事件。

```solidity
    uint256 public isOpen;

    modifier whenOpen() {
        require(isOpen == 1, "Closed");
        _;
    }

    event Opened();
    event Closed();

    function open() external onlyOwner {
        isOpen = 1;
        emit Opened();
    }
    function close() external onlyOwner {
        isOpen = 0;
        emit Closed();
    }
```

##### 2.3.1.2 isInternal 和 remainingETH

`isInternal` 用来防止重入攻击，并限制 `_execute()` 函数只能通过被 `setupExecution` 修饰的函数调用，目前只有 `execute()` 和 `bulkExecute()` 被 `setupExecution` 修饰。

`remainingETH` 用来记录 `msg.sender` 的 ETH。交易过程中会根据订单信息来转移指定数量的 ETH，如果最后执行玩交易后还剩余的就通过 `_returnDust()` 转回给 `msg.sender`。

```solidity
    bool public isInternal = false;
    uint256 public remainingETH = 0;

    modifier setupExecution() {
        require(!isInternal, "Unsafe call"); // add redundant re-entrancy check for clarity
        remainingETH = msg.value;
        isInternal = true;
        _;
        remainingETH = 0;
        isInternal = false;
    }

    modifier internalCall() {
        require(isInternal, "Unsafe call");
        _;
    }
```

```solidity
function _returnDust() private {
        uint256 _remainingETH = remainingETH;
        assembly {
            if gt(_remainingETH, 0) {
                let callStatus := call(
                    gas(),
                    caller(),
                    _remainingETH,
                    0,
                    0,
                    0,
                    0
                )
                if iszero(callStatus) {
                  revert(0, 0)
                }
            }
        }
    }
```

##### 2.3.1.3 cancelledOrFilled

用于记录取消的和已成交订单信息。类型是 mapping，key是订单的 `orderHash`。

```solidity
    mapping(bytes32 => bool) public cancelledOrFilled;
```

正如之前说的 BlurExchange 是链下中心化订单簿的交易模型，所有的订单数据都存在链下。因此挂单的时候只需要进行签名，Blur 会将签名信息和订单信息放到自己的中心化服务器上，这个流程是不消耗 gas 的（当然授权 NFT 的操作还是需要消耗 gas）。

但是如果用户想要取消挂单，就需要调用 BlurExchange 合约的 `cancelOrder()` 方法将这个订单的 hash 设置到 `cancelledOrFilled` 这一成员变量中，这一个过程涉及到链上数据的修改，因此需要消耗 gas。

而且这一步是必须的。如果只在链下订单簿上将订单删除，没有设置 `cancelledOrFilled`。这时候其他人如果能在用户删除订单数据之前拿到这个订单数据和签名信息还是能通过 BlurExchange 合约进行成单的。而大部分交易所（比如 Opensea 和 Blur）的订单数据都是能通过特定 API 来获取的。

##### 2.3.1.4 nonces

用于记录用户的 nonce 。类型是 mapping，key是用户的 `address`。

```solidity
    mapping(address => uint256) public nonces;
```

这一数据主要来管理用户的订单。如果用户想要取消所有的订单，不需要一个个调用 `cancelOrder()` ，只需要调用 `incrementNonce()` 方法将 `nonces` 中存储的 nonce 值加 1 就行。

```solidity
    /**
     * @dev Cancel all current orders for a user, preventing them from being matched. Must be called by the trader of the order
     */
    function incrementNonce() external {
        nonces[msg.sender] += 1;
        emit NonceIncremented(msg.sender, nonces[msg.sender]);
    }
```

这是因为所有订单的 hash 都是通过订单数据和订单 `trader` 的 nonce 来生成的。而如果 nonce 的值改变了之后，订单的 hash 就会发生改变。这时候再去校验用户的签名的时候就会失败。从而使用户所有以之前 nonce 签名的的订单全部失效。具体校验逻辑可以看下面的 Signature Authentication。

```solidity
function _hashOrder(Order calldata order, uint256 nonce)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            bytes.concat(
                abi.encode(
                      ORDER_TYPEHASH,
                      order.trader,
                      order.side,
                      order.matchingPolicy,
                      order.collection,
                      order.tokenId,
                      order.amount,
                      order.paymentToken,
                      order.price,
                      order.listingTime,
                      order.expirationTime,
                      _packFees(order.fees),
                      order.salt,
                      keccak256(order.extraParams)
                ),
                abi.encode(nonce)
            )
        );
    }
```

##### 2.3.1.4 其他一些成员变量

```solidity
    // ExecutionDelegate 合约的地址，用于执行代币转移
    IExecutionDelegate public executionDelegate;
    // PolicyManager 合约的地址，用于管理交易策略
    IPolicyManager public policyManager;
    // oracle 的地址，用于 oracle 签名交易的校验
    address public oracle;
    // 订单发起到成交时区块高度的最大范围，用于 Oracle Signature 类型的订单。
    uint256 public blockRange;

    // 收费比率
    uint256 public feeRate;
    // 费用接收地址
    address public feeRecipient;
    // 官方地址，设置费用比率的时候必须是这个官方地址发起的调用
    address public governor;
```

#### 2.3.2 Execute

订单的匹配通过 `execute()` 和 `bulkExecute()` 进行匹配。他们一个是单个订单匹配，一个是多个订单匹配。最终都会调用 `_execute()` 方法。

```solidity
function _execute(Input calldata sell, Input calldata buy)
        public
        payable
        internalCall
        reentrancyGuard 
    {
        require(sell.order.side == Side.Sell);

        // 计算订单 hash
        bytes32 sellHash = _hashOrder(sell.order, nonces[sell.order.trader]);
        bytes32 buyHash = _hashOrder(buy.order, nonces[buy.order.trader]);

        // 校验订单参数
        require(_validateOrderParameters(sell.order, sellHash), "Sell has invalid parameters");
        require(_validateOrderParameters(buy.order, buyHash), "Buy has invalid parameters");

        // 校验签名，order.trader == msg.sender 则不去校验直接返回 true
        require(_validateSignatures(sell, sellHash), "Sell failed authorization");
        require(_validateSignatures(buy, buyHash), "Buy failed authorization");

        // 校验买卖订单是否能匹配
        (uint256 price, uint256 tokenId, uint256 amount, AssetType assetType) = _canMatchOrders(sell.order, buy.order);

        /* Mark orders as filled. */
        // 存储订单状态
        cancelledOrFilled[sellHash] = true;
        cancelledOrFilled[buyHash] = true;
        
        // 执行资产转移
        _executeFundsTransfer(
            sell.order.trader,
            buy.order.trader,
            sell.order.paymentToken,
            sell.order.fees,
            price
        );

        // 执行 NFT 转移
        _executeTokenTransfer(
            sell.order.collection,
            sell.order.trader,
            buy.order.trader,
            tokenId,
            amount,
            assetType
        );

        // 发出事件
        emit OrdersMatched(
            // 买单时间大，表明此次是由买家触发，事件中的 maker 是买家。相反的 maker 是卖家表明是有卖家触发的订单。
            sell.order.listingTime <= buy.order.listingTime ? sell.order.trader : buy.order.trader, 
            sell.order.listingTime > buy.order.listingTime ? sell.order.trader : buy.order.trader,
            sell.order,
            sellHash,
            buy.order,
            buyHash
        );
    }
```

订单完成后发出 `OrdersMatched` 事件。

```solidity
    event OrdersMatched(
        address indexed maker,
        address indexed taker,
        Order sell,
        bytes32 sellHash,
        Order buy,
        bytes32 buyHash
    );
```

#### 2.3.3 canMatchOrders

在上面撮合订单的方法中会进行校验买卖单能否成交。具体的 matchingPolicy 分析见下文。

```solidity
function _canMatchOrders(Order calldata sell, Order calldata buy)
        internal
        view
        returns (uint256 price, uint256 tokenId, uint256 amount, AssetType assetType)
    {
        bool canMatch;
        if (sell.listingTime <= buy.listingTime) {
            /* Seller is maker. */
            // 校验订单的成交策略是否在白名单中
            require(policyManager.isPolicyWhitelisted(sell.matchingPolicy), "Policy is not whitelisted");
            // 调用具体的校验方法进行校验
            (canMatch, price, tokenId, amount, assetType) = IMatchingPolicy(sell.matchingPolicy).canMatchMakerAsk(sell, buy);
        } else {
            /* Buyer is maker. */
            require(policyManager.isPolicyWhitelisted(buy.matchingPolicy), "Policy is not whitelisted");
            (canMatch, price, tokenId, amount, assetType) = IMatchingPolicy(buy.matchingPolicy).canMatchMakerBid(buy, sell);
        }
        require(canMatch, "Orders cannot be matched");

        return (price, tokenId, amount, assetType);
    }
```

#### 2.3.4 Signature Authentication

由于采用链下中心化订单簿的交易模型，用户首先将 NFT 授权给 Blur，然后 Blur 在撮合成交的时候将 NFT 转移给买家。为了确保交易按照卖家的要求成交，因此需要卖家对订单信息进行签名。然后在成交的时候对签名进行校验，以此来保证交易的安全。

在 BlurExchange 中，可以一次签名一个订单，也可以一次签名多个订单。而且除了 User Authorization，还有 Oracle Authorization。下面会详细介绍。

所有的签名校验都通过 `_validateSignatures()` 方法进行。

```solidity
 function _validateSignatures(Input calldata order, bytes32 orderHash)
        internal
        view
        returns (bool)
    {   
        // 如果订单的 extraParams 中有数据，且第一个元素是 1 表示需要进行 Oracle Authorization
        if (order.order.extraParams.length > 0 && order.order.extraParams[0] == 0x01) {
            /* Check oracle authorization. */
            // 订单的挂单区块高度与当前成单时的区块高度的差值要小于 blockRange
            require(block.number - order.blockNumber < blockRange, "Signed block number out of range");
            if (
                !_validateOracleAuthorization(
                    orderHash,
                    order.signatureVersion,
                    order.extraSignature,
                    order.blockNumber
                )
            ) {
                return false;
            }
        }

        // 交易方与调用者相同的时候不用校验，因为这个交易是调用者自己触发的。
        if (order.order.trader == msg.sender) {
          return true;
        }

        /* Check user authorization. */
        if (
            !_validateUserAuthorization(
                orderHash,
                order.order.trader,
                order.v,
                order.r,
                order.s,
                order.signatureVersion,
                order.extraSignature
            )
        ) {
            return false;
        }

        return true;
    }
```

##### 2.3.4.1 User Authorization

订单中的 SignatureVersion 参数确定了两种类型的签名类型: 单一（Single）和批量（Bulk）。单个校验通过订单哈希的签名信息进行身份验证。批量则更为复杂一些。

###### Bulk SignatureVersion

批量校验签名用到了大家都很熟悉的 Merkle Tree。

要进行批量校验签名的时候，用户需要根据要签署的多个订单信息生成订单 hash。然后利用订单 hash 生成 Merkle Tree，并得到 Merkle Tree Root。最后将订单 hash 各自的 path 打包在订单数据的 extraSignature 中。这样在成交的时候利用订单 hash 和 proof 数据生成Merkle Tree Root，然后再验证签名信息。

```solidity
function _validateUserAuthorization(
        bytes32 orderHash,
        address trader,
        uint8 v,
        bytes32 r,
        bytes32 s,
        SignatureVersion signatureVersion,
        bytes calldata extraSignature
    ) internal view returns (bool) {
        bytes32 hashToSign;
        if (signatureVersion == SignatureVersion.Single) { // 单个签名
            /* Single-listing authentication: Order signed by trader */
            hashToSign = _hashToSign(orderHash);
        } else if (signatureVersion == SignatureVersion.Bulk) { // 批量签名
            /* Bulk-listing authentication: Merkle root of orders signed by trader */
            // 从 extraSignature 中解出 merkle tree 的路径
            (bytes32[] memory merklePath) = abi.decode(extraSignature, (bytes32[]));
            // 计算 merkle tree 的 root 节点
            bytes32 computedRoot = MerkleVerifier._computeRoot(orderHash, merklePath);
            hashToSign = _hashToSignRoot(computedRoot);
        }
        // 校验签名
        return _recover(hashToSign, v, r, s) == trader;
    }
```

##### 2.3.4.2 Oracle Authorization

这里的 Oracle 跟 Chainlink 那样的预言机没有什么关系，反而跟 NFT Mint 阶段进行签名校验的逻辑相似。

上面我们提到过 BlurExchange 合约中有一个 oracle 的成员变量。他是一个地址类型的变量。

```solidity
address public oracle;
```

如果要使用 Oracle Authorization 这项功能，用户需要选择授权 Oracle 这个地址对订单进行签名。然后将 Oracle 的签名信息放到订单的 extraSignature 这一参数中去。最后订单校验的时候会对这一签名信息进行校验，如果校验通过就可以进行接下来的校验。

Oracle Authorization 需要注意以下几点：

###### 1. Oracle Authorization 是可选的

Oracle Authorization 是可选的，User Authorization 是每次成单都必须进行的。

###### 2. Oracle Authorization 实现了链下取消订单的方法

因为 Oracle 这一账户对订单进行签名是在链下 Blur 中心化服务器上进行的。如果用户想要取消某个使用了 Oracle Authorization 方式的订单，只需要告诉 Blur 的服务器不再对其进行生成签名就可以了。

###### 3. blockNumber 和 blockRange

进行这种形式校验的订单需要提供订单创建时的区块高度信息（blockNumber）。并且在校验的时候，订单创建时候的区块高度与当前成单时候的区块高度的差值必须小于 `blockRange` 这一成员变量。

```solidity
/* Check oracle authorization. */
require(block.number - order.blockNumber < blockRange, "Signed block number out of range");
```

这样做的目的应该是是安全上面的考量。减少了签名的有效时间，防止签名的滥用。

###### 4. extraSignature 存储了批量订单校验和 Oracle 校验使用的额外数据

订单信息中的 `extraSignature` 是一个 `bytes` 类型的参数。

如果当前订单是一个单个校验订单，则 `extraSignature` 存储的只有 Oracle 校验使用的额外数据。为空则表示该单个校验订单不支持 Oracle Authorization。

如果当前订单是一个批量校验订单，则 `extraSignature` 存储的既有批量订单校验需要用到的Merkle Path 数据，也有 Oracle 校验使用的签名数据。

其中前 32 个字节是批量订单校验的 Merkle Path 数据，接着后面每 32 个字节都是一个签名数据。

##### _validateOracleAuthorization()

```solidity
function _validateOracleAuthorization(
        bytes32 orderHash,
        SignatureVersion signatureVersion,
        bytes calldata extraSignature,
        uint256 blockNumber
    ) internal view returns (bool) {
        bytes32 oracleHash = _hashToSignOracle(orderHash, blockNumber);

        uint8 v; bytes32 r; bytes32 s;
        if (signatureVersion == SignatureVersion.Single) {
            assembly {
                v := calldataload(extraSignature.offset)
                r := calldataload(add(extraSignature.offset, 0x20))
                s := calldataload(add(extraSignature.offset, 0x40))
            }
            /*
            REFERENCE
            (v, r, s) = abi.decode(extraSignature, (uint8, bytes32, bytes32));
            */
        } else if (signatureVersion == SignatureVersion.Bulk) {
            /* If the signature was a bulk listing the merkle path must be unpacked before the oracle signature. */
            assembly {
                v := calldataload(add(extraSignature.offset, 0x20))
                r := calldataload(add(extraSignature.offset, 0x40))
                s := calldataload(add(extraSignature.offset, 0x60))
            }
            /*
            REFERENCE
            uint8 _v, bytes32 _r, bytes32 _s;
            (bytes32[] memory merklePath, uint8 _v, bytes32 _r, bytes32 _s) = abi.decode(extraSignature, (bytes32[], uint8, bytes32, bytes32));
            v = _v; r = _r; s = _s;
            */
        }

        return _verify(oracle, oracleHash, v, r, s);
    }
```

#### 2.3.5 Token Transfer

买卖双方在授权代币的时候会向 ExecutionDelegate 授权。然后在订单成交的时候由 ExecutionDelegate 负责具体的转移代币的逻辑。

##### 2.3.5.1 货币的转移

通过下面的代码可以发现 Blur 只支持 ETH、WETH 和 BlurPool 作为支付货币。 其他的 ERC20 代币还不支持作为支付代币。

BlurPool 比较特殊，可以简单理解为 WETH。下面会详细介绍。

```solidity
// ETH or WETH or BlurPool 
function _transferTo(
        address paymentToken,
        address from,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0) {
            return;
        }

        if (paymentToken == address(0)) {
            /* Transfer funds in ETH. */
            require(to != address(0), "Transfer to zero address");
            (bool success,) = payable(to).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else if (paymentToken == POOL) {
            /* Transfer Pool funds. */
            bool success = IBlurPool(POOL).transferFrom(from, to, amount);
            require(success, "Pool transfer failed");
        } else if (paymentToken == WETH) {
            /* Transfer funds in WETH. */
            executionDelegate.transferERC20(WETH, from, to, amount);
        } else {
            revert("Invalid payment token");
        }
    }
```

##### 2.3.5.2 资产的转移

```solidity
// NFT 的转移
function _executeTokenTransfer(
        address collection,
        address from,
        address to,
        uint256 tokenId,
        uint256 amount,
        AssetType assetType
    ) internal {
        /* Call execution delegate. */
        if (assetType == AssetType.ERC721) {
            executionDelegate.transferERC721(collection, from, to, tokenId);
        } else if (assetType == AssetType.ERC1155) {
            executionDelegate.transferERC1155(collection, from, to, tokenId, amount);
        }
    }
```

## 3. PolicyManager

<https://etherscan.io/address/0x3a35A3102b5c6bD1e4d3237248Be071EF53C8331>

用于管理所有的交易策略。

包括交易策略的添加，移除和查看等功能。

### 3.1 MatchingPolicy

结合 PolicyManager 的 Event 信息，可以找到目前 PolicyManager 白名单中有三种交易策略：

1. StandardPolicyERC721（normal）: <https://etherscan.io/address/0x00000000006411739DA1c40B106F8511de5D1FAC>
2. StandardPolicyERC721（oracle）: <https://etherscan.io/address/0x0000000000daB4A563819e8fd93dbA3b25BC3495>
3. SafeCollectionBidPolicyERC721: <https://etherscan.io/address/0x0000000000b92D5d043FaF7CECf7E2EE6aaeD232>

注意前两个是不同的合约，具体的策略也有一些区别。

其中 StandardPolicyERC721（normal）和 StandardPolicyERC721（oracle）基本逻辑差不多，不同的是 oracle 类型的策略要求必须用于支持 Oracle Authorization 的订单。

SafeCollectionBidPolicyERC721 策略中不对 token id 进行校验而且调用 canMatchMakerAsk 方法直接 revert。这说明使用这种策略的订单只能进行接受出价（bid），不能直接 listing。这跟 Blur 中的 bid 功能有关。

## 4. BlurPool

BlurPool 可以简单看成 WETH 的一个特殊版本。他们的代码有很多地方都是一样的。

BlurPool 特殊之处有以下两点。

1. BlurPool 的 `transferFrom()` 函数，只能被 BlurExchange 和 BlurSwap 这两个合约外部调用。
2. BlurPool 中没有 approve 相关的逻辑。

这些特性看起来很奇怪，其实这都是为 Blur Bid 功能来服务的。我们接下来详细看看 Bid 这一功能。

## 5. Blur Bid

Blur 的 Bid 功能是一个设计相当巧妙的功能，甚至可以说 Blur 就是靠着这个功能完成了对 Opensea 的超越的。下面我们来看看具体的实现方法。

### 5.1 出价

首先我们先要明确一下 NFT 交易中存在的两个交易方向。

一个是挂单，也就是将自己拥有的 NFT 挂到交易市场。然后等待买家来购买。这种交易方向 Opensea 和 Blur 都称之为 Listing。

另一个是出价，也就是自己看上了某个 NFT，然后对这个 NFT 的拥有者发出一个购买请求。如果 NFT 的拥有者觉得价格合适就可以选择接受该出价。这种交易方向在 Opensea 上称之为 Offer，Blur 上称为 Bid。

### 5.2 Opensea Offer

在 Opensea 上对某个 NFT 进行 Offer 需要以下几个步骤:

1. 查询 WETH 余额，如果没有余额需要将 ETH 转换成 WETH。
2. 授权 WETH (只需要一次)。
3. 对 Offer 订单进行签名。

如果要取消 Offer 则需要调用 Seaport 合约的 `cancle()` 方法，将 Offer 对应的这个订单的取消状态写入到 Seaport 的成员变量 `_orderStatus` 中，来确保这个订单无法成交。这一步是必须的。具体原因可以看看 上面 BlurExchange 中的 `cancelledOrFilled` 成员变量的解释。由于涉及到修改合约中的数据，因此这一步是需要支付 gas 的。

这里还要解释一下 Opensea 的 Offer 为什么必须使用 WETH，而不是使用 ETH。

我们都知道 WETH 原本作用是为了 ETH 包装成 ERC20 代币。然后就可以使用 ERC20 的一些功能。比如授权和转移。

如果在 Offer 订单中使用 ETH 的话，由于 ETH 无法进行授权操作，因此需要将 ETH 先转移到 Seaport 合约之中，然后再在成交的时候将 ETH 转移给 NFT 拥有者。如果用户想对多个 NFT 进行 Offer 的话就需要先提供出去足额的 ETH。这种方法显然占用了太多的用户的资金。

而使用 WETH 的话，用户只需要将 WETH 授权给 Seaport 合约，而不占用户的资金。用户可以对多个 NFT 进行 Offer。这无疑提高了用户的体验。

### 5.3 Blur Bid

在 Blur 上对 NFT 进行 Bid 需要以下几个步骤:

1. Blur 不能对单个 NFT 进行 Bid，而是要对该 NFT 整个 collection 进行 bid。
2. 查询 BlurPool 的余额，如果余额为空需要将 ETH 存入 BlurPool 中。
3. 对 Bid 订单进行签名。

如果想要取消 Bid 订单不需要支付 gas 就能取消。

其实我刚看到这些的时候，对 BlurPool 不需要授权这点很容易立即，但是取消 Bid 订单不需要 gas 就很让人费解了。其实我们只需要将上面内容中的 Oracle Authorization 和 SafeCollectionBidPolicyERC721 串起来就好理解了。

我们通过一个例子来了解具体的实现方法。

https://etherscan.io/tx/0xdd0058f2bfd06bfe6c265cfa01d8082333966a1c7d6a7bd430cfcf7c1ac9f223

#### 5.3.1 解析参数

通过解析交易的数据我们可以了解到调用了这个交易是地址为0x56a6ff5eca020a8ffc67fe7682887ccae12ac2d3 的 EOA 账号调用 BlurExchange（0x000000000000ad05ccc4f10045630fb830b95127） 的 `execute()` 方法。

输入的参数如下

```json
{
  "sell": {
    "order": {
      "trader": "0x56a6ff5eca020a8ffc67fe7682887ccae12ac2d3",
      "side": 1,
      "matchingPolicy": "0x0000000000b92d5d043faf7cecf7e2ee6aaed232",
      "collection": "0x39ee2c7b3cb80254225884ca001f57118c8f21b6",
      "tokenId": "3960",
      "amount": "1",
      "paymentToken": "0x0000000000a39bb272e79075ade125fd351887ac",
      "price": "2130000000000000000",
      "listingTime": "1677644849",
      "expirationTime": "1677652366",
      "fees": [
        {
          "rate": 333,
          "recipient": "0xf3b985336fd574a0aa6e02cbe61c609861e923d6"
        }
      ],
      "salt": "114616841359518544842066950455752933050",
      "extraParams": "0x01"
    },
    "v": 0,
    "r": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "s": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "extraSignature": "0x000000000000000000000000000000000000000000000000000000000000001bc9f1fde1f59a56a5343044a91c595b42f451bf8b13ba1fff391dda90221229f37912e2977ccca951de1612270e3acdb865103f9f44acd807c0f22792a9c07f4d",
    "signatureVersion": 0,
    "blockNumber": "16731714"
  },
  "buy": {
    "order": {
      "trader": "0x14b6e5f84da2febd85d92dd9c2d4aa633cc65e30",
      "side": 0,
      "matchingPolicy": "0x0000000000b92d5d043faf7cecf7e2ee6aaed232",
      "collection": "0x39ee2c7b3cb80254225884ca001f57118c8f21b6",
      "tokenId": "0",
      "amount": "1",
      "paymentToken": "0x0000000000a39bb272e79075ade125fd351887ac",
      "price": "2130000000000000000",
      "listingTime": "1677644848",
      "expirationTime": "1709180849",
      "fees": [],
      "salt": "71987771138744249662594339974857147058",
      "extraParams": "0x01"
    },
    "v": 27,
    "r": "0xc63f4bca4a5fb3802f7f956ad1358e5cf312646d1569f9b16543840444a12e68",
    "s": "0x1b95f680e148e81ce067764c48d25e68a9df2e2cda9b5c1ffe0e714fb1d126ec",
    "extraSignature": "0x000000000000000000000000000000000000000000000000000000000000001ca531657f4514cdffa5eff876ba26c236805c48116a9e9b4befc7c0ee8bf190c757ee01dace8d955ccda3dcee4e58c650dc0b3e29b8e9d3caa5a401144874530e",
    "signatureVersion": 0,
    "blockNumber": "16731714"
  }
}
```

#### 5.3.2 分析交易方向

sell 订单中 trader 地址与发起这笔交易的地址是一样的，因此这是一笔通过 Blur Bid 的交易。

因为这说明 buy 这个订单是首先生成的，也就是说先有地址为 0x14b6e5f84da2febd85d92dd9c2d4aa633cc65e30 的账户提出了一个报价，然后才有 0x56a6ff5eca020a8ffc67fe7682887ccae12ac2d3 的账户接受了这个报价，然后 0x56a6ff5eca020a8ffc67fe7682887ccae12ac2d3 这个账户调用 BlurExchange 进行成单的。

因此 Bid 订单就是 buy 这个参数中的订单。

#### 5.3.3 分析 Bid 订单

Bid 订单的参数中有两个方面需要特殊注意。

##### 5.3.3.1 MatchingPolicy

该订单中的 matchingPolicy 地址为 0x0000000000b92d5d043faf7cecf7e2ee6aaed232，是 SafeCollectionBidPolicyERC721 的交易策略。

我们上面了解过，这种交易策略不对 token id 进行校验而且调用该策略的 canMatchMakerAsk 方法直接 revert。这也正好应对了 Blur Bid 的交易要求。

因此该订单中的 tokenId 为 0，不是表示要购买 token id 为 0 的订单。

##### 5.3.3.1 Oracle Authentication

该订单中 extraParams 是 0x01，正好满足 Oracle Authorization 的条件。因此该订单需要进行 Oracle Authorization。

```solidity
// 如果订单的 extraParams 中有数据，且第一个元素是 1 表示需要进行 Oracle Authorization
if (order.order.extraParams.length > 0 && order.order.extraParams[0] == 0x01) {
    ...
}
```

我们在上面提到过 Oracle Authentication 这一步骤中校验的签名是通过链下 Blur 中心化服务器上生成的。如果提交 Bid 订单的用户在该订单成交之前告诉 Blur 取消该订单，则 Blur 就不再生成签名。这样一来这个 Bid 订单就无法在进行成交了。这也是为什么 Blur Bid 能不消耗 gas 进行取消的原因。

## 6. Opensea 和 版税

提到 Opensea 和 Blur 的版税，那可是一个相当精彩的故事。我们先来梳理一下事情的来龙去脉。

1. 2022 年 11 月，OpenSea 实施了一项新政策：如果项目方想要收取版税必须集成 Opensea 的链上版税强制执行工具。这个工具的本质是一个黑名单。集成该工具的 NFT 无法在一些零版税或者低版税的交易平台上交易。Blur 当时实行的是 0 版税 0 手续费的政策，因此也在这个黑名单中。（这个工具的具体实现可以参考我之前写过的这篇[文章](https://github.com/cryptochou/opensea-creator-fees))。
2. Opensea 实时这一策略的目的是司马昭之心路人皆知了，摆明了是针对 Blur 的。不过这一策略被证明是有效的。比如 Yuga 的 Sewer Pass 等新系列都选择与 OpenSea 结盟并阻止在 Blur 上的交易。
3. 这时候 Blur 承诺对新的 NFT 项目收取版税，并要求 Opensea 将他们从黑名单中移出。
4. 然而，OpenSea 回复说，其政策要求对所有 NFT项目征收版税，而不仅仅是实施黑名单的新 NFT项目。Blur 突围失败。
5. 这时候大多数的创作者都站队了 Opensea。
6. 本以为事情就这样下去了，然而精彩的来了。Blur 直接利用 Opensea 的 Seaport 合约创建了一个新的交易系统。对于集成了黑名单工具并且将 Blur 拉黑的 NFT 项目，Blur 直接通过 Seaport 进行交易。其他的 NFT项目则继续走 BlurExchange 进行交易(具体逻辑见下图)。你 Opensea 总不能把 Seaport 也拉进黑名单吧。Blur 突围成功。
7. Blur 的反击。随着 Blur 的空投，Blur 上的交易量大幅超过了 Opensea。这时候如果一个新的 NFT 项目把 Blur 加入黑名单的话就无法在 BlurExchange 上进行 Bid 了。而 Bid 在空投中计算积分的很重要的一步。这时候越来越多的 NFT 项目取消了 Blur 的黑名单。
8. Blur 的进一步反击。Blur 发出声明如果将 OpenSea 加入到黑名单中则可以在 Blur 上收取全部版税。同时可以增加空投奖励。与此同时，呼吁大家不要将 OpenSea 和 Blur 放到黑名单中。并向 Opensea 喊话取消 Blur 的黑名单。
9. Opensea 妥协了，将 Blur 移出了黑名单。并宣布限时 0 手续费的活动。
10. Blur win！

![source: https://twitter.com/pandajackson42/status/1620081586237767680/photo/1](FnuuanrXEAAYQch.jpeg)

Twitter 上的 Panda Jackson 的几个配图很生动了描述了 Opensea 当前的处境。

![](FnutRuVWAAAOaVY.jpeg)
![](FnuuepzWAAE4Hx4.png)
![](FnuunmuXkAAS-bssq.jpeg)

## 7. 总结

整体看来 Blur 给人的感觉还是挺简洁的。

批量签名、预言机签名这些新功能会有有很大的应用空间。

目前 Blur 应该还是在很早期的阶段，毕竟他只支持了 ERC721 的限价单的交易方式。不支持 ERC1155 的交易，也不支持拍卖功能。当然这些应该都在他们的开发计划中。通过 MatchingPolicy 可以很方便的添加新的交易策略。这一点跟 BendDao 的 Execution Strategy 很像。猜测大概率是借鉴过来的。（关于 BendDao 更多的信息可以查看我的另一篇文章：[BendDAO-analysis](https://github.com/cryptochou/BendDAO-analysis#execution-strategy%E6%89%A7%E8%A1%8C%E7%AD%96%E7%95%A5)）

虽然是很早起的阶段，但是 Blur 目前的交易量大有赶超 Opensea 之势。应该是明确的空投预期起到了很大的作用。毕竟天下苦 Opensea 久矣。🤣

---

2023 03-03 Updata

5 个月过去了，Blur 的合约添加了一些新的功能，我这里重新梳理了一下 BlurExchange 合约。之前没怎么在意的 Oracle Authorization 没想到被 Blur 玩出了这么个玩法。

从目前来看可以说 Blur 是超越 Opensea 了，不论是从热度还是交易量来看。这期间他突破 Opensea 构筑的马奇诺防线的骚操作也让人直呼厉害。同时 Blur Bid 的功能也为 NFT 交易市场注入了大量的流动性。应该来说 Blur 为 NFT 交易市场带来了新的活力。

当然 Opensea 也并非一无是处。首先 Opensea 的界面相对 Blur 来说还是更容易让 NFT 新手的接受的。其次 Seaport 合约也可以称为是 NFT 基础建设级别的工具，支撑起了 ensvision 等一众垂直领域的 NFT 交易市场。这点也是很值得称道的。

## 8. 参考

1. https://twitter.com/pandajackson42/status/1620081518575235073
2. https://mirror.xyz/blurdao.eth/vYOjzk4cQCQ7AtuJWWiZPoNZ04YKQmTMsos0NNq_hYs

如果感觉本文对您有帮助的话，欢迎打赏：0x1E1eFeb696Bc8F3336852D9FB2487FE6590362BF。







