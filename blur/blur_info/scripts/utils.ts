import {
  getContract as _getContract,
  updateAddresses as _updateAddresses,
  getAddress as _getAddress,
} from './web3-utils';

const repo = 'BlurExchange';

const contracts = {
  BlurExchange: 'BLUR_EXCHANGE',
  ExecutionDelegate: 'EXECUTION_DELEGATE',
  PolicyManager: 'POLICY_MANAGER',
  StandardPolicyERC721: 'STANDARD_POLICY_ERC721',
  StandardPolicyERC1155: 'STANDARD_POLICY_ERC1155',
  MerkleVerifier: 'MERKLE_VERIFIER',
};

export function getAddress(contract: string, network: string): string {
  return _getAddress(repo, contract, contracts, network);
}

export function getContract(hre: any, contract: string, options?: any) {
  return _getContract(hre, repo, contract, contracts, options);
}

export function updateAddresses(
  network: string,
  addresses = Object.keys(contracts),
) {
  _updateAddresses(repo, addresses, contracts, network);
}
