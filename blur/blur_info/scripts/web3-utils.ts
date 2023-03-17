import assert from 'assert';
import { ContractReceipt, Signer } from 'ethers';
import { getContractAddress } from 'ethers/lib/utils';
import fs from 'fs';

const DEPLOYMENTS_DIR = `../deployments`;

export function getRequiredEnv(key: string): string {
  const value = process.env[key];
  assert(value, `Please provide ${key} in .env file`);

  return value;
}

export function getOptionalEnv(key: string): string | undefined {
  return process.env[key];
}

export function getAddressEnv(key: string, NETWORK: string): string {
  return getRequiredEnv(`${NETWORK}_${key}_ADDRESS`);
}

export function getAddress(
  repo: string,
  contract: string,
  contractVariables: Record<string, string>,
  network: string,
): string {
  try {
    const addresses = JSON.parse(
      fs.readFileSync(`${DEPLOYMENTS_DIR}/${network}.json`).toString(),
    );
    const contractVariable = contractVariables[contract];
    return addresses[repo][contractVariable];
  } catch (err) {
    throw Error(`${contract} deployment on ${network} not found`);
  }
}

export async function getContractAt(
  hre: any,
  name: string,
  address: string,
  options: any = {},
) {
  console.log(`Using existing contract: ${name} at: ${address}`);
  const contractFactory = await hre.ethers.getContractFactory(name, options);
  return contractFactory.attach(address);
}

export async function getContract(
  hre: any,
  repo: string,
  name: string,
  contractVariables: any,
  options: any = {},
) {
  const { network } = getNetwork(hre);
  const address = await getAddress(repo, name, contractVariables, network);
  const contractFactory = await hre.ethers.getContractFactory(name, options);
  return contractFactory.attach(address);
}

export function getExchange(version: string): string {
  return `contracts/ExchangeV${version}/Exchange.sol:Exchange`;
}

export function getNetwork(hre: any): {
  network: string;
  NETWORK: string;
  chainId: string;
} {
  return {
    network: hre.network.name,
    NETWORK: hre.network.name.toUpperCase(),
    chainId: hre.network.config.chainId,
  };
}

export async function getAddressOfNextDeployedContract(
  signer: Signer,
  offset = 0,
): Promise<string> {
  return getContractAddress({
    from: await signer.getAddress(),
    nonce: (await signer.getTransactionCount()) + offset,
  });
}

export function save(name: string, contract: any, network: string) {
  if (!fs.existsSync(`${DEPLOYMENTS_DIR}/${network}`)) {
    fs.mkdirSync(`${DEPLOYMENTS_DIR}/${network}`, { recursive: true });
  }
  fs.writeFileSync(
    `${DEPLOYMENTS_DIR}/${network}/${name}.json`,
    JSON.stringify(
      {
        address: contract.address,
      },
      null,
      4,
    ),
  );
}

export function load(name: string, network: string) {
  const { address } = JSON.parse(
    fs.readFileSync(`${DEPLOYMENTS_DIR}/${network}/${name}.json`).toString(),
  );
  return address;
}

export function asDec(address: string): string {
  return BigInt(address).toString();
}

export async function deploy(
  hre: any,
  name: string,
  calldata: any = [],
  options: any = {},
  saveName = '',
) {
  console.log(`Deploying: ${name}...`);
  const contractFactory = await hre.ethers.getContractFactory(name, options);
  const contract = await contractFactory.deploy(...calldata);
  save(saveName || name, contract, hre.network.name);

  console.log(`Deployed: ${name} to: ${contract.address}`);
  await contract.deployed();
  return contract;
}

export async function waitForTx(tx: Promise<any>): Promise<ContractReceipt> {
  const resolvedTx = await tx;
  return await resolvedTx.wait();
}

export function updateAddresses(
  repo: string,
  contracts: string[],
  contractVariables: Record<string, string>,
  network: string,
) {
  const contractAddresses: Record<string, string> = {};
  contracts.forEach((contract) => {
    const variable = contractVariables[contract];
    contractAddresses[variable] = load(contract, network);
  });

  let addresses: Record<string, Record<string, string>> = {};
  if (fs.existsSync(`${DEPLOYMENTS_DIR}/${network}.json`)) {
    addresses = JSON.parse(
      fs.readFileSync(`${DEPLOYMENTS_DIR}/${network}.json`).toString(),
    );
  }
  addresses[repo] = {
    ...addresses[repo],
    ...contractAddresses,
  };

  console.log('\nAddresses:');
  Object.entries(contractAddresses).forEach(([key, value]) => {
    console.log(` ${key}: ${value}`);
  });
  fs.writeFileSync(
    `${DEPLOYMENTS_DIR}/${network}.json`,
    JSON.stringify(addresses, null, 4),
  );
}
