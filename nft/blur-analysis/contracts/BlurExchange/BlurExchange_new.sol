// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./lib/ReentrancyGuarded.sol";
import "./lib/EIP712.sol";
import "./lib/MerkleVerifier.sol";
import "./interfaces/IBlurExchange.sol";
import "./interfaces/IBlurPool.sol";
import "./interfaces/IExecutionDelegate.sol";
import "./interfaces/IPolicyManager.sol";
import "./interfaces/IMatchingPolicy.sol";
import {
  Side,
  SignatureVersion,
  AssetType,
  Fee,
  Order,
  Input,
  Execution
} from "./lib/OrderStructs.sol";

/**
 * @title BlurExchange
 * @dev Core Blur exchange contract
 */
contract BlurExchange is IBlurExchange, ReentrancyGuarded, EIP712, OwnableUpgradeable, UUPSUpgradeable {

    /* Auth */
    uint256 public isOpen;

    modifier whenOpen() {
        require(isOpen == 1, "Closed");
        _;
    }

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

    // required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}


    /* Constants */
    string public constant NAME = "Blur Exchange";
    string public constant VERSION = "1.0";
    uint256 public constant INVERSE_BASIS_POINT = 10_000;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant POOL = 0x0000000000A39bb272e79075ade125fd351887Ac;
    uint256 private constant MAX_FEE_RATE = 250;


    /* Variables */
    IExecutionDelegate public executionDelegate;
    IPolicyManager public policyManager;
    address public oracle;
    uint256 public blockRange;

    /* Storage */
    mapping(bytes32 => bool) public cancelledOrFilled;
    mapping(address => uint256) public nonces;

    bool public isInternal = false;
    uint256 public remainingETH = 0;


    /* Governance Variables */
    uint256 public feeRate;
    address public feeRecipient;

    address public governor;


    /* Events */
    event OrdersMatched(
        address indexed maker,
        address indexed taker,
        Order sell,
        bytes32 sellHash,
        Order buy,
        bytes32 buyHash
    );

    event OrderCancelled(bytes32 hash);
    event NonceIncremented(address indexed trader, uint256 newNonce);

    event NewExecutionDelegate(IExecutionDelegate indexed executionDelegate);
    event NewPolicyManager(IPolicyManager indexed policyManager);
    event NewOracle(address indexed oracle);
    event NewBlockRange(uint256 blockRange);
    event NewFeeRate(uint256 feeRate);
    event NewFeeRecipient(address feeRecipient);
    event NewGovernor(address governor);

    constructor() {
      _disableInitializers();
    }

    /* Constructor (for ERC1967) */
    function initialize(
        IExecutionDelegate _executionDelegate,
        IPolicyManager _policyManager,
        address _oracle,
        uint _blockRange
    ) external initializer {
        __Ownable_init();
        isOpen = 1;

        DOMAIN_SEPARATOR = _hashDomain(EIP712Domain({
            name              : NAME,
            version           : VERSION,
            chainId           : block.chainid,
            verifyingContract : address(this)
        }));

        executionDelegate = _executionDelegate;
        policyManager = _policyManager;
        oracle = _oracle;
        blockRange = _blockRange;
    }

    /* External Functions */
    /**
     * @dev _execute wrapper
     * @param sell Sell input
     * @param buy Buy input
     */
    function execute(Input calldata sell, Input calldata buy)
        external
        payable
        whenOpen
        setupExecution
    {
        _execute(sell, buy);
        _returnDust();
    }

    /**
     * @dev Bulk execute multiple matches
     * @param executions Potential buy/sell matches
     */
    function bulkExecute(Execution[] calldata executions)
        external
        payable
        whenOpen
        setupExecution
    {
        /*
        REFERENCE
        uint256 executionsLength = executions.length;
        for (uint8 i=0; i < executionsLength; i++) {
            bytes memory data = abi.encodeWithSelector(this._execute.selector, executions[i].sell, executions[i].buy);
            (bool success,) = address(this).delegatecall(data);
        }
        _returnDust(remainingETH);
        */
        uint256 executionsLength = executions.length;

        if (executionsLength == 0) {
          revert("No orders to execute");
        }
        for (uint8 i = 0; i < executionsLength; i++) {
            assembly {
                let memPointer := mload(0x40)

                let order_location := calldataload(add(executions.offset, mul(i, 0x20)))
                let order_pointer := add(executions.offset, order_location)

                let size
                switch eq(add(i, 0x01), executionsLength)
                case 1 {
                    size := sub(calldatasize(), order_pointer)
                }
                default {
                    let next_order_location := calldataload(add(executions.offset, mul(add(i, 0x01), 0x20)))
                    let next_order_pointer := add(executions.offset, next_order_location)
                    size := sub(next_order_pointer, order_pointer)
                }

                mstore(memPointer, 0xe04d94ae00000000000000000000000000000000000000000000000000000000) // _execute
                calldatacopy(add(0x04, memPointer), order_pointer, size)
                // must be put in separate transaction to bypass failed executions
                // must be put in delegatecall to maintain the authorization from the caller
                let result := delegatecall(gas(), address(), memPointer, add(size, 0x04), 0, 0)
            }
        }
        _returnDust();
    }

    /**
     * @dev Match two orders, ensuring validity of the match, and execute all associated state transitions. Must be called internally.
     * @param sell Sell input
     * @param buy Buy input
     */
    function _execute(Input calldata sell, Input calldata buy)
        public
        payable
        internalCall
        reentrancyGuard // move re-entrancy check for clarity
    {
        require(sell.order.side == Side.Sell);

        bytes32 sellHash = _hashOrder(sell.order, nonces[sell.order.trader]);
        bytes32 buyHash = _hashOrder(buy.order, nonces[buy.order.trader]);

        require(_validateOrderParameters(sell.order, sellHash), "Sell has invalid parameters");
        require(_validateOrderParameters(buy.order, buyHash), "Buy has invalid parameters");

        require(_validateSignatures(sell, sellHash), "Sell failed authorization");
        require(_validateSignatures(buy, buyHash), "Buy failed authorization");

        (uint256 price, uint256 tokenId, uint256 amount, AssetType assetType) = _canMatchOrders(sell.order, buy.order);

        /* Mark orders as filled. */
        cancelledOrFilled[sellHash] = true;
        cancelledOrFilled[buyHash] = true;

        _executeFundsTransfer(
            sell.order.trader,
            buy.order.trader,
            sell.order.paymentToken,
            sell.order.fees,
            buy.order.fees,
            price
        );
        _executeTokenTransfer(
            sell.order.collection,
            sell.order.trader,
            buy.order.trader,
            tokenId,
            amount,
            assetType
        );

        emit OrdersMatched(
            sell.order.listingTime <= buy.order.listingTime ? sell.order.trader : buy.order.trader,
            sell.order.listingTime > buy.order.listingTime ? sell.order.trader : buy.order.trader,
            sell.order,
            sellHash,
            buy.order,
            buyHash
        );
    }

    /**
     * @dev Cancel an order, preventing it from being matched. Must be called by the trader of the order
     * @param order Order to cancel
     */
    function cancelOrder(Order calldata order) public {
        /* Assert sender is authorized to cancel order. */
        require(msg.sender == order.trader, "Not sent by trader");

        bytes32 hash = _hashOrder(order, nonces[order.trader]);

        require(!cancelledOrFilled[hash], "Order cancelled or filled");

        /* Mark order as cancelled, preventing it from being matched. */
        cancelledOrFilled[hash] = true;
        emit OrderCancelled(hash);
    }

    /**
     * @dev Cancel multiple orders
     * @param orders Orders to cancel
     */
    function cancelOrders(Order[] calldata orders) external {
        for (uint8 i = 0; i < orders.length; i++) {
            cancelOrder(orders[i]);
        }
    }

    /**
     * @dev Cancel all current orders for a user, preventing them from being matched. Must be called by the trader of the order
     */
    function incrementNonce() external {
        nonces[msg.sender] += 1;
        emit NonceIncremented(msg.sender, nonces[msg.sender]);
    }


    /* Setters */

    function setExecutionDelegate(IExecutionDelegate _executionDelegate)
        external
        onlyOwner
    {
        require(address(_executionDelegate) != address(0), "Address cannot be zero");
        executionDelegate = _executionDelegate;
        emit NewExecutionDelegate(executionDelegate);
    }

    function setPolicyManager(IPolicyManager _policyManager)
        external
        onlyOwner
    {
        require(address(_policyManager) != address(0), "Address cannot be zero");
        policyManager = _policyManager;
        emit NewPolicyManager(policyManager);
    }

    function setOracle(address _oracle)
        external
        onlyOwner
    {
        require(_oracle != address(0), "Address cannot be zero");
        oracle = _oracle;
        emit NewOracle(oracle);
    }

    function setBlockRange(uint256 _blockRange)
        external
        onlyOwner
    {
        blockRange = _blockRange;
        emit NewBlockRange(blockRange);
    }

    function setGovernor(address _governor)
        external
        onlyOwner
    {
        governor = _governor;
        emit NewGovernor(governor);
    }

    function setFeeRate(uint256 _feeRate)
        external
    {
        require(msg.sender == governor, "Fee rate can only be set by governor");
        require(_feeRate <= MAX_FEE_RATE, "Fee cannot be more than 2.5%");
        feeRate = _feeRate;
        emit NewFeeRate(feeRate);
    }

    function setFeeRecipient(address _feeRecipient)
        external
        onlyOwner
    {
        feeRecipient = _feeRecipient;
        emit NewFeeRecipient(feeRecipient);
    }


    /* Internal Functions */

    /**
     * @dev Verify the validity of the order parameters
     * @param order order
     * @param orderHash hash of order
     */
    function _validateOrderParameters(Order calldata order, bytes32 orderHash)
        internal
        view
        returns (bool)
    {
        return (
            /* Order must have a trader. */
            (order.trader != address(0)) &&
            /* Order must not be cancelled or filled. */
            (!cancelledOrFilled[orderHash]) &&
            /* Order must be settleable. */
            (order.listingTime < block.timestamp) &&
            (block.timestamp < order.expirationTime)
        );
    }

    /**
     * @dev Verify the validity of the signatures
     * @param order order
     * @param orderHash hash of order
     */
    function _validateSignatures(Input calldata order, bytes32 orderHash)
        internal
        view
        returns (bool)
    {

        if (order.order.extraParams.length > 0 && order.order.extraParams[0] == 0x01) {
            /* Check oracle authorization. */
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

    /**
     * @dev Verify the validity of the user signature
     * @param orderHash hash of the order
     * @param trader order trader who should be the signer
     * @param v v
     * @param r r
     * @param s s
     * @param signatureVersion signature version
     * @param extraSignature packed merkle path
     */
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
        if (signatureVersion == SignatureVersion.Single) {
            /* Single-listing authentication: Order signed by trader */
            hashToSign = _hashToSign(orderHash);
        } else if (signatureVersion == SignatureVersion.Bulk) {
            /* Bulk-listing authentication: Merkle root of orders signed by trader */
            (bytes32[] memory merklePath) = abi.decode(extraSignature, (bytes32[]));

            bytes32 computedRoot = MerkleVerifier._computeRoot(orderHash, merklePath);
            hashToSign = _hashToSignRoot(computedRoot);
        }

        return _verify(trader, hashToSign, v, r, s);
    }

    /**
     * @dev Verify the validity of oracle signature
     * @param orderHash hash of the order
     * @param signatureVersion signature version
     * @param extraSignature packed oracle signature
     * @param blockNumber block number used in oracle signature
     */
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

    /**
     * @dev Verify ECDSA signature
     * @param signer Expected signer
     * @param digest Signature preimage
     * @param v v
     * @param r r
     * @param s s
     */
    function _verify(
        address signer,
        bytes32 digest,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (bool) {
        require(v == 27 || v == 28, "Invalid v parameter");
        address recoveredSigner = ecrecover(digest, v, r, s);
        if (recoveredSigner == address(0)) {
          return false;
        } else {
          return signer == recoveredSigner;
        }
    }

    /**
     * @dev Call the matching policy to check orders can be matched and get execution parameters
     * @param sell sell order
     * @param buy buy order
     */
    function _canMatchOrders(Order calldata sell, Order calldata buy)
        internal
        view
        returns (uint256 price, uint256 tokenId, uint256 amount, AssetType assetType)
    {
        bool canMatch;
        if (sell.listingTime <= buy.listingTime) {
            /* Seller is maker. */
            require(policyManager.isPolicyWhitelisted(sell.matchingPolicy), "Policy is not whitelisted");
            (canMatch, price, tokenId, amount, assetType) = IMatchingPolicy(sell.matchingPolicy).canMatchMakerAsk(sell, buy);
        } else {
            /* Buyer is maker. */
            require(policyManager.isPolicyWhitelisted(buy.matchingPolicy), "Policy is not whitelisted");
            (canMatch, price, tokenId, amount, assetType) = IMatchingPolicy(buy.matchingPolicy).canMatchMakerBid(buy, sell);
        }
        require(canMatch, "Orders cannot be matched");

        return (price, tokenId, amount, assetType);
    }

    /**
     * @dev Execute all ERC20 token / ETH transfers associated with an order match (fees and buyer => seller transfer)
     * @param seller seller
     * @param buyer buyer
     * @param paymentToken payment token
     * @param sellerFees seller fees
     * @param buyerFees buyer fees
     * @param price price
     */
    function _executeFundsTransfer(
        address seller,
        address buyer,
        address paymentToken,
        Fee[] calldata sellerFees,
        Fee[] calldata buyerFees,
        uint256 price
    ) internal {
        if (paymentToken == address(0)) {
            require(msg.sender == buyer, "Cannot use ETH");
            require(remainingETH >= price, "Insufficient value");
            remainingETH -= price;
        }

        /* Take fee. */
        uint256 sellerFeesPaid = _transferFees(sellerFees, paymentToken, buyer, price, true);
        uint256 buyerFeesPaid = _transferFees(buyerFees, paymentToken, buyer, price, false);
        if (paymentToken == address(0)) {
          /* Need to account for buyer fees paid on top of the price. */
          remainingETH -= buyerFeesPaid;
        }

        /* Transfer remainder to seller. */
        _transferTo(paymentToken, buyer, seller, price - sellerFeesPaid);
    }

    /**
     * @dev Charge a fee in ETH or WETH
     * @param fees fees to distribute
     * @param paymentToken address of token to pay in
     * @param from address to charge fees
     * @param price price of token
     * @return total fees paid
     */
    function _transferFees(
        Fee[] calldata fees,
        address paymentToken,
        address from,
        uint256 price,
        bool protocolFee
    ) internal returns (uint256) {
        uint256 totalFee = 0;

        /* Take protocol fee if enabled. */
        if (feeRate > 0 && protocolFee) {
            uint256 fee = (price * feeRate) / INVERSE_BASIS_POINT;
            _transferTo(paymentToken, from, feeRecipient, fee);
            totalFee += fee;
        }

        /* Take order fees. */
        for (uint8 i = 0; i < fees.length; i++) {
            uint256 fee = (price * fees[i].rate) / INVERSE_BASIS_POINT;
            _transferTo(paymentToken, from, fees[i].recipient, fee);
            totalFee += fee;
        }

        require(totalFee <= price, "Fees are more than the price");

        return totalFee;
    }

    /**
     * @dev Transfer amount in ETH or WETH
     * @param paymentToken address of token to pay in
     * @param from token sender
     * @param to token recipient
     * @param amount amount to transfer
     */
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

    /**
     * @dev Execute call through delegate proxy
     * @param collection collection contract address
     * @param from seller address
     * @param to buyer address
     * @param tokenId tokenId
     * @param assetType asset type of the token
     */
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

    /**
     * @dev Return remaining ETH sent to bulkExecute or execute
     */
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
}
