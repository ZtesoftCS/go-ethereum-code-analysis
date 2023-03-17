import { Contract, ethers, Wallet, Signature } from 'ethers';
import { MerkleTree } from 'merkletreejs';
import { TypedDataUtils, SignTypedDataVersion } from '@metamask/eth-sig-util';
const { eip712Hash, hashStruct } = TypedDataUtils;

import { OrderParameters, OrderWithNonce, TypedData } from './utils';

const eip712Fee = {
  name: 'Fee',
  fields: [
    { name: 'rate', type: 'uint16' },
    { name: 'recipient', type: 'address' },
  ],
};

const eip712Order = {
  name: 'Order',
  fields: [
    { name: 'trader', type: 'address' },
    { name: 'side', type: 'uint8' },
    { name: 'matchingPolicy', type: 'address' },
    { name: 'collection', type: 'address' },
    { name: 'tokenId', type: 'uint256' },
    { name: 'amount', type: 'uint256' },
    { name: 'paymentToken', type: 'address' },
    { name: 'price', type: 'uint256' },
    { name: 'listingTime', type: 'uint256' },
    { name: 'expirationTime', type: 'uint256' },
    { name: 'fees', type: 'Fee[]' },
    { name: 'salt', type: 'uint256' },
    { name: 'extraParams', type: 'bytes' },
    { name: 'nonce', type: 'uint256' },
  ],
};

const eip712OracleOrder = {
  name: 'OracleOrder',
  fields: [
    { name: 'order', type: 'Order' },
    { name: 'blockNumber', type: 'uint256' },
  ],
};

function structToSign(order: OrderWithNonce, exchange: string): TypedData {
  return {
    name: eip712Order.name,
    fields: eip712Order.fields,
    domain: {
      name: 'Blur Exchange',
      version: '1.0',
      chainId: 1,
      verifyingContract: exchange,
    },
    data: order,
  };
}

export async function oracleSign(
  order: OrderParameters,
  account: Wallet,
  exchange: Contract,
  blockNumber: number,
): Promise<Signature> {
  const nonce = await exchange.nonces(order.trader);
  const str = structToSign({ ...order, nonce }, exchange.address);
  return account
    ._signTypedData(
      str.domain,
      {
        [eip712Fee.name]: eip712Fee.fields,
        [eip712Order.name]: eip712Order.fields,
        [eip712OracleOrder.name]: eip712OracleOrder.fields,
      },
      { order: str.data, blockNumber },
    )
    .then((sigBytes) => {
      const sig = ethers.utils.splitSignature(sigBytes);
      return sig;
    });
}

export async function sign(
  order: OrderParameters,
  account: Wallet,
  exchange: Contract,
): Promise<Signature> {
  const nonce = await exchange.nonces(order.trader);
  const str = structToSign({ ...order, nonce }, exchange.address);

  return account
    ._signTypedData(
      str.domain,
      {
        [eip712Fee.name]: eip712Fee.fields,
        [eip712Order.name]: eip712Order.fields,
      },
      str.data,
    )
    .then(async (sigBytes) => {
      const sig = ethers.utils.splitSignature(sigBytes);
      return sig;
    });
}

export function packSignature(signature: Signature): string {
  return ethers.utils.defaultAbiCoder.encode(
    ['uint8', 'bytes32', 'bytes32'],
    [signature.v, signature.r, signature.s],
  );
}

export function packSignatures(signatures: Signature[]): string {
  return ethers.utils.defaultAbiCoder.encode(
    signatures.map(() => 'bytes'),
    signatures.map(packSignature),
  );
}

export function getMerkleProof(leaves: string[]) {
  const tree = new MerkleTree(leaves, ethers.utils.keccak256, { sort: true });
  const root = tree.getHexRoot();
  return { root, tree };
}

export async function signBulk(
  orders: OrderParameters[],
  account: Wallet,
  exchange: Contract,
) {
  const { tree, root } = await getOrderTreeRoot(orders, exchange);
  const nonce = await exchange.nonces(orders[0].trader);
  const _order = hashWithoutDomain({ ...orders[0], nonce });
  const signature = await account
    ._signTypedData(
      {
        name: 'Blur Exchange',
        version: '1.0',
        chainId: 1,
        verifyingContract: exchange.address,
      },
      {
        Root: [{ name: 'root', type: 'bytes32' }],
      },
      { root },
    )
    .then((sigBytes) => {
      const sig = ethers.utils.splitSignature(sigBytes);
      return sig;
    });
  return {
    path: ethers.utils.defaultAbiCoder.encode(
      ['bytes32[]'],
      [tree.getHexProof(_order)],
    ),
    r: signature.r,
    v: signature.v,
    s: signature.s,
  };
}

async function getOrderTreeRoot(orders: OrderParameters[], exchange: Contract) {
  const leaves = await Promise.all(
    orders.map(async (order) => {
      const nonce = await exchange.nonces(order.trader);
      return hashWithoutDomain({ ...order, nonce });
    }),
  );
  return getMerkleProof(leaves);
}

export function hash(parameters: any, exchange: Contract): string {
  parameters.nonce = parameters.nonce.toHexString();
  parameters.price = parameters.price.toHexString();
  return `0x${eip712Hash(
    {
      types: {
        EIP712Domain: [
          { name: 'name', type: 'string' },
          { name: 'version', type: 'string' },
          { name: 'chainId', type: 'uint256' },
          { name: 'verifyingContract', type: 'address' },
        ],
        [eip712Fee.name]: eip712Fee.fields,
        [eip712Order.name]: eip712Order.fields,
      },
      primaryType: 'Order',
      domain: {
        name: 'Blur Exchange',
        version: '1.0',
        chainId: 1,
        verifyingContract: exchange.address,
      },
      message: parameters,
    },
    SignTypedDataVersion.V4,
  ).toString('hex')}`;
}

export function hashWithoutDomain(parameters: any): string {
  parameters.nonce = parameters.nonce.toHexString();
  parameters.price = parameters.price.toHexString();
  return `0x${hashStruct(
    'Order',
    parameters,
    {
      [eip712Fee.name]: eip712Fee.fields,
      [eip712Order.name]: eip712Order.fields,
    },
    SignTypedDataVersion.V4,
  ).toString('hex')}`;
}
