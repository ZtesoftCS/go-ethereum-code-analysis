import hre from 'hardhat';

import { runExchangeTests } from './exchange.test';
import { SetupExchangeOpts, SetupExchangeResult } from './exchange';
import { deployFull } from '../scripts/deploy';

const order =
  '(address,uint8,address,address,uint256,uint256,address,uint256,uint256,uint256,(uint16,address)[],uint256,bytes)';
export const publicMutableMethods = [
  'initialize(uint256,address,address,address,address,uint256)',
  'transferOwnership(address)',
  'renounceOwnership()',
  'close()',
  'open()',
  'setOracle(address)',
  'setBlockRange(uint256)',
  'setExecutionDelegate(address)',
  'setPolicyManager(address)',
  `cancelOrder(${order})`,
  `cancelOrders(${order}[])`,
  `incrementNonce()`,
  `execute((${order},uint8,bytes32,bytes32,bytes,uint8,uint256),(${order},uint8,bytes32,bytes32,bytes,uint8,uint256))`,
  'upgradeTo(address)',
  'upgradeToAndCall(address,bytes)',
];

export async function setupExchange({
  admin,
  weth,
}: SetupExchangeOpts): Promise<SetupExchangeResult> {
  return deployFull(hre, 'TestBlurExchange', 1, weth.address, admin.address);
}

runExchangeTests(setupExchange, publicMutableMethods);
