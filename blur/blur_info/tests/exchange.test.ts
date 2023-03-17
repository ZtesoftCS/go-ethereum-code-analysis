import { expect } from 'chai';
import { BigNumber, Wallet } from 'ethers';

import type { GenerateOrder, SetupExchangeFunction } from './exchange';
import { ZERO_ADDRESS } from './exchange/utils';
import { eth, Order, setupTest, Side } from './exchange';
import { runSignatureTests } from './signatures.test';
import { runMatchingPolicyTests } from './policy.test';
import { runExecuteTests } from './execution.test';
import { runPermissionsTests } from './permissions.test';

export function runExchangeTests(
  setupExchange: SetupExchangeFunction,
  publicMutableMethods: string[],
) {
  describe('Exchange', function () {
    const feeRate = 300;
    const price: BigNumber = eth('1');

    let alice: Wallet;
    let exchange: any;

    let generateOrder: GenerateOrder;

    describe(
      'permissions',
      runPermissionsTests(async () => {
        return setupTest({
          price,
          feeRate,
          setupExchange,
        });
      }, publicMutableMethods),
    );

    describe('validateOrderParameters', function () {
      let order: Order;
      let orderHash: string;

      before(async () => {
        ({ alice, exchange, generateOrder } = await setupTest({
          price,
          feeRate,
          setupExchange,
        }));
      });

      beforeEach(async () => {
        order = generateOrder(alice, { side: Side.Sell });
        orderHash = await order.hash();
      });

      it('trader is zero', async () => {
        order.parameters.trader = ZERO_ADDRESS;
        expect(
          await exchange.validateOrderParameters(order.parameters, orderHash),
        ).to.equal(false);
      });
      it('expiration time is 0 and listing time < now', async () => {
        expect(
          await exchange.validateOrderParameters(order.parameters, orderHash),
        ).to.equal(true);
      });
      it('expiration time is 0 and listing time > now', async () => {
        order.parameters.listingTime = '10000000000000000000000000000';
        expect(
          await exchange.validateOrderParameters(order.parameters, orderHash),
        ).to.equal(false);
      });
      it('expiration time > now and listing time < now', async () => {
        order.parameters.expirationTime = '10000000000000000000000000000';
        expect(
          await exchange.validateOrderParameters(order.parameters, orderHash),
        ).to.equal(true);
      });
      it('expiration time < now and listing time < now', async () => {
        order.parameters.expirationTime = '1';
        expect(
          await exchange.validateOrderParameters(order.parameters, orderHash),
        ).to.equal(false);
      });
      it('cancelled or filled', async () => {
        await exchange.connect(alice).cancelOrder(order.parameters);
        expect(
          await exchange.validateOrderParameters(order.parameters, orderHash),
        ).to.equal(false);
      });
    });

    describe(
      'validateSignatures',
      runSignatureTests(async () => {
        return setupTest({
          price,
          feeRate,
          setupExchange,
        });
      }),
    );

    describe(
      'matchingPolicies',
      runMatchingPolicyTests(async () => {
        return setupTest({
          price,
          feeRate,
          setupExchange,
        });
      }),
    );

    describe(
      'execute',
      runExecuteTests(async () => {
        return setupTest({
          price,
          feeRate,
          setupExchange,
        });
      }),
    );
  });
}
