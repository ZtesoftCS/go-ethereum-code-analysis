// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./lib/ReentrancyGuarded.sol";
import "./lib/EIP712.sol";
import "./lib/MerkleVerifier.sol";
import "./interfaces/IBlurExchange.sol";
import "./interfaces/IExecutionDelegate.sol";
import "./interfaces/IPolicyManager.sol";
import "./interfaces/IMatchingPolicy.sol";
import {
  Side,
  SignatureVersion,
  AssetType,
  Fee,
  Order,
  Input
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
    string public constant name = "Blur Exchange";
    string public constant version = "1.0";
    uint256 public constant INVERSE_BASIS_POINT = 10000;


    /* Variables */
    address public weth;
    IExecutionDelegate public executionDelegate;
    IPolicyManager public policyManager;
    address public oracle;
    uint256 public blockRange;


    /* Storage */
    mapping(bytes32 => bool) public cancelledOrFilled;
    mapping(address => uint256) public nonces;


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
    event NonceIncremented(address trader, uint256 newNonce);

    event NewExecutionDelegate(IExecutionDelegate executionDelegate);
    event NewPolicyManager(IPolicyManager policyManager);
    event NewOracle(address oracle);
    event NewBlockRange(uint256 blockRange);


    /* Constructor (for ERC1967) */
    function initialize(
        uint chainId,
        address _weth,
        IExecutionDelegate _executionDelegate,
        IPolicyManager _policyManager,
        address _oracle,
        uint _blockRange
    ) public initializer {
        __Ownable_init();
        isOpen = 1;

        DOMAIN_SEPARATOR = _hashDomain(EIP712Domain({
            name              : name,
            version           : version,
            chainId           : chainId,
            verifyingContract : address(this)
        }));

        weth = _weth;
        executionDelegate = _executionDelegate;
        policyManager = _policyManager;
        oracle = _oracle;
        blockRange = _blockRange;
    }


    /* External Functions */

    /**
     * @dev Match two orders, ensuring validity of the match, and execute all associated state transitions. Protected against reentrancy by a contract-global lock.
     * @param sell Sell input
     * @param buy Buy input
     */
    function execute(Input calldata sell, Input calldata buy)
        external
        payable
        reentrancyGuard
        whenOpen
    {
        require(sell.order.side == Side.Sell);

        bytes32 sellHash = _hashOrder(sell.order, nonces[sell.order.trader]);
        bytes32 buyHash = _hashOrder(buy.order, nonces[buy.order.trader]);

        require(_validateOrderParameters(sell.order, sellHash), "Sell has invalid parameters");
        require(_validateOrderParameters(buy.order, buyHash), "Buy has invalid parameters");

        require(_validateSignatures(sell, sellHash), "Sell failed authorization");
        require(_validateSignatures(buy, buyHash), "Buy failed authorization");

        (uint256 price, uint256 tokenId, uint256 amount, AssetType assetType) = _canMatchOrders(sell.order, buy.order);

        _executeFundsTransfer(
            sell.order.trader,
            buy.order.trader,
            sell.order.paymentToken,
            sell.order.fees,
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

        /* Mark orders as filled. */
        cancelledOrFilled[sellHash] = true;
        cancelledOrFilled[buyHash] = true;

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
        require(msg.sender == order.trader);

        bytes32 hash = _hashOrder(order, nonces[order.trader]);

        if (!cancelledOrFilled[hash]) {
            /* Mark order as cancelled, preventing it from being matched. */
            cancelledOrFilled[hash] = true;
            emit OrderCancelled(hash);
        }
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
            (cancelledOrFilled[orderHash] == false) &&
            /* Order must be settleable. */
            _canSettleOrder(order.listingTime, order.expirationTime)
        );
    }

    /**
     * @dev Check if the order can be settled at the current timestamp
     * @param listingTime order listing time
     * @param expirationTime order expiration time
     */
    function _canSettleOrder(uint256 listingTime, uint256 expirationTime)
        view
        internal
        returns (bool)
    {
        return (listingTime < block.timestamp) && (expirationTime == 0 || block.timestamp < expirationTime);
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

        if (order.order.expirationTime == 0) {
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

        return _recover(hashToSign, v, r, s) == trader;
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
            (v, r, s) = abi.decode(extraSignature, (uint8, bytes32, bytes32));
        } else if (signatureVersion == SignatureVersion.Bulk) {
            /* If the signature was a bulk listing the merkle path musted be unpacked before the oracle signature. */
            (bytes32[] memory merklePath, uint8 _v, bytes32 _r, bytes32 _s) = abi.decode(extraSignature, (bytes32[], uint8, bytes32, bytes32));
            v = _v; r = _r; s = _s;
        }

        return _recover(oracleHash, v, r, s) == oracle;
    }

    /**
     * @dev Wrapped ecrecover with safety check for v parameter
     * @param v v
     * @param r r
     * @param s s
     */
    function _recover(
        bytes32 digest,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address) {
        require(v == 27 || v == 28, "Invalid v parameter");
        return ecrecover(digest, v, r, s);
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
     * @param fees fees
     * @param price price
     */
    function _executeFundsTransfer(
        address seller,
        address buyer,
        address paymentToken,
        Fee[] calldata fees,
        uint256 price
    ) internal {
        if (paymentToken == address(0)) {
            require(msg.value == price);
        }

        /* Take fee. */
        uint256 receiveAmount = _transferFees(fees, paymentToken, buyer, price);

        /* Transfer remainder to seller. */
        _transferTo(paymentToken, buyer, seller, receiveAmount);
    }

    /**
     * @dev Charge a fee in ETH or WETH
     * @param fees fees to distribute
     * @param paymentToken address of token to pay in
     * @param from address to charge fees
     * @param price price of token
     */
    function _transferFees(
        Fee[] calldata fees,
        address paymentToken,
        address from,
        uint256 price
    ) internal returns (uint256) {
        uint256 totalFee = 0;
        for (uint8 i = 0; i < fees.length; i++) {
            uint256 fee = (price * fees[i].rate) / INVERSE_BASIS_POINT;
            _transferTo(paymentToken, from, fees[i].recipient, fee);
            totalFee += fee;
        }

        require(totalFee <= price, "Total amount of fees are more than the price");

        /* Amount that will be received by seller. */
        uint256 receiveAmount = price - totalFee;
        return (receiveAmount);
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
            payable(to).transfer(amount);
        } else if (paymentToken == weth) {
            /* Transfer funds in WETH. */
            executionDelegate.transferERC20(weth, from, to, amount);
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
        /* Assert collection exists. */
        require(_exists(collection), "Collection does not exist");

        /* Call execution delegate. */
        if (assetType == AssetType.ERC721) {
            executionDelegate.transferERC721(collection, from, to, tokenId);
        } else if (assetType == AssetType.ERC1155) {
            executionDelegate.transferERC1155(collection, from, to, tokenId, amount);
        }
    }

    /**
     * @dev Determine if the given address exists
     * @param what address to check
     */
    function _exists(address what)
        internal
        view
        returns (bool)
    {
        uint size;
        assembly {
            size := extcodesize(what)
        }
        return size > 0;
    }
}
