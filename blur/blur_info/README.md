# Blur Exchange contest details
- $47,500 USDC main award pot
- $2,500 USDC gas optimization award pot
- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form](https://code4rena.com/contests/2022-10-blur-exchange-contest/submit)
- [Read our guidelines for more details](https://docs.code4rena.com/roles/wardens)
- Starts October 5, 2022 20:00 UTC
- Ends October 10, 2022 20:00 UTC

## Scoping details answers
```
- How many contracts are in scope?   10
- Total SLoC for these contracts?   around 1100
- How many external imports are there?   11
- How many separate interfaces and struct definitions are there for the contracts within scope?   5
- Does most of your code generally use composition or inheritance?   more composition
- How many external calls?   only erc20, erc721, and erc1155 transfers
- What is the overall line coverage percentage provided by your tests?   90%
- Is there a need to understand a separate part of the codebase / get context in order to audit this part of the protocol?   false
- Does it use an oracle?   true
- If yes, please describe what kind? e.g. chainlink or ..?   Optional feature requires an oracle signature in order to fulfill an order. We will maintain the oracle that creates signatures unless the user requests us to stop.
- Does the token conform to the ERC20 standard?   No token is involved.
- Are there any novel or unique curve logic or mathematical models?   No
- Does it use a timelock function?   Only the listingTime and expirationTime on orders
- Is it an NFT?   No
- Does it have an AMM?   No
- Is it a fork of a popular project?   false
- Does it use rollups?   false
- Is it multi-chain?   false
- Does it use a side-chain?   false
- Do you have a preferred timezone for communication?   PDT
```

# Blur Exchange

## Overview
The Blur Exchange is a single token exchange enabling transfers of ERC721/ERC1155 for ETH/WETH. It uses a ERC1967 proxy pattern and consists of three main components (1) [BlurExchange](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/BlurExchange.sol), (2) [MatchingPolicy](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/MatchingPolicy.sol), (3) [ExecutionDelegate](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/ExecutionDelegate.sol).

### Architecture
![Exchange Architecture](https://github.com/code-423n4/2022-10-blur/blob/main/docs/exchange_architecture.png?raw=true)

### Signature Authentication

#### User Signatures
The exchange accepts two types of signature authentication determined by a `signatureVersion` parameter - single or bulk. Single listings are authenticated via a signature of the order hash.
  
##### Bulk Listing
To bulk list, the user will produce a merkle tree from the order hashes and sign the root. To verify, the respective merkle path for the order will be packed in `extraSignature`, the merkle root will be reconstructed from the order and merkle path, and the signature will be validated.


#### Oracle Signatures
This feature allows a user to opt-in to require an authorized oracle signature of the order with a recent block number. This enables an off-chain cancellation method where the oracle can continue to provide signatures to potential takers, until the user requests the oracle to stop. After some period of time, the old oracle signatures will expire.

To opt-in, the user has to set the `expirationTime` to 0. In order to fulfill the order, the oracle signature has to be packed in `extraSignature` and the `blockNumber` set to what was signed by the oracle.


### Order matching - [PolicyManager](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/PolicyManager.sol)
In order to maintain flexibility with the types of orders and methods of matching that the exchange is able to execute, the order matching logic is separated to a set of whitelisted matching policies. The responsibility of each policy is to assert the criteria for a valid match are met and return the parameters for proper execution -
  - `price` - matching price
  - `tokenId` - NFT token id to transfer
  - `amount` - (for erc1155) amount of the token to transfer
  - `assetType` - `ERC721` or `ERC1155`


### Transfer approvals - [ExecutionDelegate](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/ExecutionDelegate.sol)
Ultimately, token approval is only needed for calling transfer functions on `ERC721`, `ERC1155`, or `ERC20`. The `ExecutionDelegate` is a shared transfer proxy that can only call these transfer functions. There are additional safety features to ensure the proxy approval cannot be used maliciously.

#### Safety features
  - The calling contract must be approved on the `ExecutionDelegate`
  - Users have the ability to revoke approval from the `ExecutionDelegate` without having to individually calling every token contract.


### Cancellations
**On-chain methods**
  - `cancelOrder(Order order)` - must be called from `trader`; records order hash in `cancelledOrFilled` mapping that's checked when validating orders
  - `cancelOrders(Order[] orders)` - must be called from `trader`; calls `cancelOrder` for each order
  - `incrementNonce()` - increments the nonce of the `msg.sender`; all orders signed with the previous nonce are invalid

**Off-chain methods**
  - Oracle cancellations - if the order is signed with an `expirationTime` of 0, a user can request an oracle to stop producing authorization signatures; without a recent signature, the order will not be able to be matched


## Smart Contracts
All the contracts in this section are to be reviewed. Any contracts not in this list are to be ignored for this contest.

### Files in scope
|File|[SLOC](#nowhere "(nSLOC, SLOC, Lines)")|[Coverage](#nowhere "(Lines hit / Total)")|
|:-|:-:|:-:|
|_Contracts (8)_|
|[contracts/lib/ReentrancyGuarded.sol](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/lib/ReentrancyGuarded.sol)|[10](#nowhere "(nSLOC:10, SLOC:10, Lines:20)")|[100.00%](#nowhere "(Hit:4 / Total:4)")|
|[contracts/lib/ERC1967Proxy.sol](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/lib/ERC1967Proxy.sol) [💰](#nowhere "Payable Functions") [🧮](#nowhere "Uses Hash-Functions")|[12](#nowhere "(nSLOC:12, SLOC:12, Lines:32)")|[100.00%](#nowhere "(Hit:3 / Total:3)")|
|[contracts/PolicyManager.sol](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/PolicyManager.sol)|[42](#nowhere "(nSLOC:37, SLOC:42, Lines:83)")|[26.67%](#nowhere "(Hit:4 / Total:15)")|
|[contracts/matchingPolicies/StandardPolicyERC1155.sol](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/matchingPolicies/StandardPolicyERC1155.sol)|[55](#nowhere "(nSLOC:33, SLOC:55, Lines:64)")|[100.00%](#nowhere "(Hit:2 / Total:2)")|
|[contracts/matchingPolicies/StandardPolicyERC721.sol](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/matchingPolicies/StandardPolicyERC721.sol)|[55](#nowhere "(nSLOC:33, SLOC:55, Lines:64)")|[100.00%](#nowhere "(Hit:2 / Total:2)")|
|[contracts/ExecutionDelegate.sol](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/ExecutionDelegate.sol)|[64](#nowhere "(nSLOC:51, SLOC:64, Lines:127)")|[88.89%](#nowhere "(Hit:16 / Total:18)")|
|[contracts/lib/EIP712.sol](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/lib/EIP712.sol) [🧮](#nowhere "Uses Hash-Functions")|[134](#nowhere "(nSLOC:106, SLOC:134, Lines:154)")|[100.00%](#nowhere "(Hit:10 / Total:10)")|
|[contracts/BlurExchange.sol](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/BlurExchange.sol) [🖥](#nowhere "Uses Assembly") [💰](#nowhere "Payable Functions") [📤](#nowhere "Initiates ETH Value Transfer") [🔖](#nowhere "Handles Signatures: ecrecover")|[359](#nowhere "(nSLOC:274, SLOC:359, Lines:559)")|[99.05%](#nowhere "(Hit:104 / Total:105)")|
|_Libraries (1)_|
|[contracts/lib/MerkleVerifier.sol](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/lib/MerkleVerifier.sol) [🖥](#nowhere "Uses Assembly")|[38](#nowhere "(nSLOC:28, SLOC:38, Lines:59)")|[70.00%](#nowhere "(Hit:7 / Total:10)")|
|_Structs (1)_|
|[contracts/lib/OrderStructs.sol](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/lib/OrderStructs.sol)|[32](#nowhere "(nSLOC:32, SLOC:32, Lines:38)")|-|
|Total (over 10 files):| [801](#nowhere "(nSLOC:616, SLOC:801, Lines:1200)")| [89.94%](#nowhere "Hit:152 / Total:169")|


### All other source contracts (not in scope)
|File|[SLOC](#nowhere "(nSLOC, SLOC, Lines)")|[Coverage](#nowhere "(Lines hit / Total)")|
|:-|:-:|:-:|
|_Interfaces (4)_|
|[contracts/interfaces/IPolicyManager.sol](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/interfaces/IPolicyManager.sol)|[8](#nowhere "(nSLOC:8, SLOC:8, Lines:14)")|-|
|[contracts/interfaces/IExecutionDelegate.sol](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/interfaces/IExecutionDelegate.sol)|[13](#nowhere "(nSLOC:11, SLOC:13, Lines:20)")|-|
|[contracts/interfaces/IMatchingPolicy.sol](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/interfaces/IMatchingPolicy.sol)|[24](#nowhere "(nSLOC:6, SLOC:24, Lines:28)")|-|
|[contracts/interfaces/IBlurExchange.sol](https://github.com/code-423n4/2022-10-blur/blob/main/contracts/interfaces/IBlurExchange.sol) [💰](#nowhere "Payable Functions")|[27](#nowhere "(nSLOC:18, SLOC:27, Lines:39)")|-|
|Total (over 4 files):| [72](#nowhere "(nSLOC:43, SLOC:72, Lines:101)")| -|

### BlurExchange.sol (359 sloc)
Core exchange contract responsible for coordinating the matching of orders and execution of the transfers.

It calls 3 external contracts
  - `PolicyManager`
  - `ExecutionDelegate`
  - Matching Policy

It uses 1 library
  - `MerkleVerifier`

It inherits the following contracts

#### EIP712.sol (134 sloc)
Contract containing all EIP712 compliant order hashing functions

#### ERC1967Proxy.sol (12 sloc)
Standard ERC1967 Proxy implementation

#### OrderStructs.sol (32 sloc)
Contains all necessary structs and enums for the Blur Exchange

#### ReentrancyGuarded.sol (10 sloc)
Modifier for reentrancy protection

#### MerkleVerifier.sol (38 sloc)
Library for Merkle tree computations

### ExecutionDelegate.sol (64 sloc)
Approved proxy to execute ERC721, ERC1155, and ERC20 transfers

Includes safety functions to allow for easy management of approvals by users

It calls 3 external contract interfaces
  - ERC721
  - ERC20
  - ERC1155

### PolicyManager.sol (42 sloc)
Contract reponsible for maintaining a whitelist for matching policies

### StandardPolicyERC721.sol (55 sloc)
Matching policy for standard fixed price sale of an ERC721 token

### StandardPolicyERC1155.sol (55 sloc)
Matching policy for standard fixed price sale of an ERC1155 token

## Development Documentation
Node version v16

- Setup - `yarn setup`
- Install packages - `yarn`
- Compile contracts - `yarn compile`
- Test coverage - `yarn coverage`
- Run tests - `yarn test`

Or use this all-in-one build command to run the tests
```
rm -Rf 2022-10-blur || true && git clone https://github.com/code-423n4/2022-10-blur.git && cd 2022-10-blur && yarn setup && nvm install 16.0 && yarn && yarn compile && REPORT_GAS=true yarn test
```
