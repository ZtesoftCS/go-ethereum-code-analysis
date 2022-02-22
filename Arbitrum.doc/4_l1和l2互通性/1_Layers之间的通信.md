# 1_Layers之间的通信
[Messaging Between Layers · Offchain Labs Dev Center](https://developer.offchainlabs.com/docs/l1_l2_messages)


## 标准Arbitrum交易：来自客户端的调用
Arbitrum上标准的客户端调用的交易是通过EthBridge中Inbox.sendL2Message来实现的：
`*function* sendL2Message(address chain, bytes calldata messageData) external;`

正如在[Tx call生命周期](../7_杂项/3_Tx call生命周期.md)中描述的那样，通常大部分调用都会走聚合器并被批量处理。

不过，Arbitrum协议也支持在L1和L2之间传递信息。

最常见的跨链通信的目的是充值和提现；不过这只是Arbitrum支持的通用型跨链合约调用中的特定的一种。本章描述了这些通用协议；深入解释请见[洞悉Arbitrum: 桥接](../2_深入理解协议/1_洞悉Arbitrum.md#桥接)。

## 以太坊到Arbitrum：Retryable Tickets
### 解释
Arbitrum为以太坊到Arbitrum通信提供了几种方式；不过对L1到L2的通信我们一般只推荐retryable tickets，可重试票据。

该方式工作机理如下：一条L1交易提交到了收件箱中，其内容为向L2进行一笔转账（包含了calldata，callvalue，以及gas info）。如果该交易第一次没有执行成功，在L2上会进入一个『retry buffer重试缓存』。这意味着在一段时间内（与该链的挑战期有关，大约为一周），任何人都可以通过再次执行来尝试赎回该L2交易票据。

注意，如果有提供任意数量的gas，L2上的交易会自动执行。在乐观的/正常的情况下，L2上的交易会立即成功。因此，用户一般只需要签名并发布单笔交易。

而Retryable Tickets的合理性在于：如果我们想向L2充值一些代币，代币会进入L1合约中，然后再在L2上铸造等量的代币。假设L1交易成功了L2交易却因为燃气费突然飙升而失败了，在不成熟的实现中，将会带来严重后果——用户转移了代币但在L2上什么也没有；这些代币永远卡在了L1的合约里。不过在使用Retryable Tickets的情况下，用户（或任何人）都可有一周的时间窗口来再次执行该L2信息。

另外，Retryable Tickets系统也周密地考虑到了用户为L2上ArbGas多支付的情况，也避免了用户在某个合约地址的执行中笨拙地支付燃气的情况。如果用户多付了ArbGas，多余的ETH会返回给用户指定的特定地址；如果用户需要在L2上再次执行该交易，可以通过任何外部所有账户EOA来执行，EOA支付本次执行的费用。但合约地址自身仍要支付retryable交易的ArbGas。

### Retryable Tickets API
在`Inbox.createRetryableTicket`中有一个便捷的方法创建retryable ticket：

```
    /**
    @notice Put an message in the L2 inbox that can be re-executed for some fixed amount of time if it reverts
    * @dev all msg.value will deposited to callValueRefundAddress on L2
    * @param destAddr destination L2 contract address
    * @param l2CallValue call value for retryable L2 message
    * @param  maxSubmissionCost Max gas deducted from user's L2 balance to cover base submission fee
    * @param excessFeeRefundAddress maxGas x gasprice - execution cost gets credited here on L2 balance
    * @param callValueRefundAddress l2Callvalue gets credited here on L2 if retryable txn times out or gets cancelled
    * @param maxGas Max gas deducted from user's L2 balance to cover L2 execution
    * @param gasPriceBid price bid for L2 execution
    * @param data ABI encoded data of L2 message
    * @return unique id for retryable transaction (keccak256(requestID, uint(0) )
     */
    function createRetryableTicket(
        address destAddr,
        uint256 l2CallValue,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 maxGas,
        uint256 gasPriceBid,
        bytes calldata data
    ) external payable override returns (uint256)
```

另外，在位于地址`0x000000000000000000000000000000000000006E`上的预编译合约`ArbRetryableTx`中也有一些retryable交易的相关方法：

```
pragma solidity >=0.4.21 <0.7.0;

/**
* @title precompiled contract in every Arbitrum chain for retryable transaction related data retrieval and interactions. Exists at 0x000000000000000000000000000000000000006E
*/
interface ArbRetryableTx {

    /**
    * @notice Redeem a redeemable tx.
    * Revert if called by an L2 contract, or if txId does not exist, or if txId reverts.
    * If this returns, txId has been completed and is no longer available for redemption.
    * If this reverts, txId is still available for redemption (until it times out or is canceled).
    @param txId unique identifier of retryabale message: keccak256(requestID, uint(0) )
     */
    function redeem(bytes32 txId) external;

    /**
    * @notice Return the minimum lifetime of redeemable txn.
    * @return lifetime in seconds
    */
    function getLifetime() external view returns(uint);

    /**
    * @notice Return the timestamp when txId will age out, or zero if txId does not exist.
    * The timestamp could be in the past, because aged-out txs might not be discarded immediately.
    * @param txId unique identifier of retryabale message: keccak256(requestID, uint(0) )
    * @return timestamp for txn's deadline
    */
    function getTimeout(bytes32 txId) external view returns(uint);

    /**
    * @notice Return the price, in wei, of submitting a new retryable tx with a given calldata size.
    * @param calldataSize call data size to get price of (in wei)
    * @return (price, nextUpdateTimestamp). Price is guaranteed not to change until nextUpdateTimestamp.
    */
    function getSubmissionPrice(uint calldataSize) external view returns (uint, uint);

    /**
     * @notice Return the price, in wei, of extending the lifetime of txId by an additional lifetime period. Revert if txId doesn't exist.
     * @param txId  unique identifier of retryabale message: keccak256(requestID, uint(0) )
     * @return (price, nextUpdateTimestamp). Price is guaranteed not to change until nextUpdateTimestamp.
    */
    function getKeepalivePrice(bytes32 txId) external view returns(uint, uint);

    /**
    @notice Deposits callvalue into the sender's L2 account, then adds one lifetime period to the life of txId.
    * If successful, emits LifetimeExtended event.
    * Revert if txId does not exist, or if the timeout of txId is already at least one lifetime in the future, or if the sender has insufficient funds (after the deposit).
    * @param txId unique identifier of retryabale message: keccak256(requestID, uint(0) )
    * @return New timeout of txId.
    */
    function keepalive(bytes32 txId) external payable returns(uint);

    /**
    * @notice Return the beneficiary of txId.
    * Revert if txId doesn't exist.
    * @param txId unique identifier of retryabale message: keccak256(requestID, uint(0) )
    * @return address of beneficiary for transaction
    */
    function getBeneficiary(bytes32 txId) external view returns (address);

    /**
    @notice Cancel txId and refund its callvalue to its beneficiary.
    * Revert if txId doesn't exist, or if called by anyone other than txId's beneficiary.
    @param txId unique identifier of retryabale message: keccak256(requestID, uint(0) )
    */
    function cancel(bytes32 txId) external;

    event LifetimeExtended(bytes32 indexed txId, uint newTimeout);
    event Redeemed(bytes32 indexed txId);
    event Canceled(bytes32 indexed txId);
}
```

在 [arb-ts](https://arb-ts-docs.netlify.app/) 中，ArbRetryableTx接口由`bridge`类实例化并暴露出来：
```
myBridge.ArbRetryableTx.redeem('mytxid')
```

## Arbitrum到以太坊
### 解释
L2到L1消息和L1到L2消息工作机制类似，但是是反向的：L2交易与编码过的L1信息数据一通发布，稍后执行。

一个关键不同在于，从L2到L1方向，用户必须等挑战期结束后才能在L1上执行该消息；这是有乐观式rollup的特性决定的（见[最终性](3_确认与最终性.md)）。另外，不像retryable ticket，L2到L1信息没有时间上限；一旦挑战期过后，可以在任意时间点执行，无需着急。

### L2到L1信息的生命周期
L2到L1信息的生命周期大致可以分为四步，只有两部（最多！）需要用户发布交易。

1. **发布L2到L1交易（Arbitrum交易）**
客户端通过调用L2上的`ArbSys.sendTxToL1`来发布信息
2. **创建发件箱**
在Arbitrum链状态前进一段时间后，ArbOS会搜集所有的外出信息，将其梅克尔化，然后将梅克尔树根发布在收件箱的[OutboxEntry](https://github.com/OffchainLabs/arbitrum/blob/master/packages/arb-bridge-eth/contracts/bridge/OutboxEntry.sol)中。请注意，该过程是自动的，不需要用户做什么。
3. **用户获取外出信息的梅克尔证明**
在Outbox Entry发布在L1上后，用户（任何人都行）可以通过`NodeInterface.lookupMessageBatchProof`计算其信息的梅克尔证明。
```

/** @title Interface for providing Outbox proof data
 *  @notice This contract doesn't exist on-chain. Instead it is a virtual interface accessible at 0x00000000000000000000000000000000000000C8
 * This is a cute trick to allow an Arbitrum node to provide data without us having to implement an additional RPC )
 */

interface NodeInterface {
    /**
    * @notice Returns the proof necessary to redeem a message
    * @param batchNum index of outbox entry (i.e., outgoing messages Merkle root) in array of outbox entries
    * @param index index of outgoing message in outbox entry
    * @return (
        * proof: Merkle proof of message inclusion in outbox entry
        * path: Index of message in outbox entry
        * l2Sender: sender if original message (i.e., caller of ArbSys.sendTxToL1)
        * l1Dest: destination address for L1 contract call
        * l2Block l2 block number at which sendTxToL1 call was made
        * l1Block l1 block number at which sendTxToL1 call was made
        * timestamp l2 Timestamp at which sendTxToL1 call was made
        * amouunt value in L1 message in wei
        * calldataForL1 abi-encoded L1 message data
        *
    */
    function lookupMessageBatchProof(uint256 batchNum, uint64 index)
        external
        view
        returns (
            bytes32[] memory proof,
            uint256 path,
            address l2Sender,
            address l1Dest,
            uint256 l2Block,
            uint256 l1Block,
            uint256 timestamp,
            uint256 amount,
            bytes memory calldataForL1
        );
}
```

4. **用户执行L1信息（以太坊交易）**
挑战期过后的任何时间，任何用户都可以通过`Outbox.executeTransaction`在L1上执行信息；如果被失败，可以尝试无限次，也没有任何时间上限：
```
 /**
    * @notice Executes a messages in an Outbox entry. Reverts if dispute period hasn't expired and
    * @param outboxIndex Index of OutboxEntry in outboxes array
    * @param proof Merkle proof of message inclusion in outbox entry
    * @param index Index of message in outbox entry
    * @param l2Sender sender if original message (i.e., caller of ArbSys.sendTxToL1)
    * @param destAddr destination address for L1 contract call
    * @param l2Block l2 block number at which sendTxToL1 call was made
    * @param l1Block l1 block number at which sendTxToL1 call was made
    * @param l2Timestamp l2 Timestamp at which sendTxToL1 call was made
    * @param amount value in L1 message in wei
    * @param calldataForL1 abi-encoded L1 message data
     */
    function executeTransaction(
        uint256 outboxIndex,
        bytes32[] calldata proof,
        uint256 index,
        address l2Sender,
        address destAddr,
        uint256 l2Block,
        uint256 l1Block,
        uint256 l2Timestamp,
        uint256 amount,
        bytes calldata calldataForL1
    )
```
请注意，上述步骤我们在[arb-ts](https://arb-ts-docs.netlify.app/)中提供了一些简便的方法。

相关用例请见[integration tests](https://github.com/OffchainLabs/arbitrum/blob/master/packages/arb-ts/integration_test/arb-bridge.test.ts.md)和[Token Bridge UI](https://github.com/OffchainLabs/arb-token-bridge)。



← [3_ArbSys预编译合约](../3_dapp基础/3_ArbSys预编译合约.md)
→ [2_代币桥接](2_代币桥接.md)