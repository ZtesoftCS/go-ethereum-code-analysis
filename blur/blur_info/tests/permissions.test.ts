import { expect } from 'chai';
import { Wallet, Contract } from 'ethers';

import { assertPublicMutableMethods } from './exchange';
import { ZERO_ADDRESS } from './exchange/utils';

export function runPermissionsTests(
  setupTest: any,
  publicMutableMethods: string[],
) {
  return async () => {
    let admin: Wallet;
    let alice: Wallet;

    let exchange: Contract;

    before(async () => {
      ({ admin, alice, exchange } = await setupTest());
    });

    it('has correct public interface', async () => {
      await assertPublicMutableMethods(exchange, publicMutableMethods);
    });

    const setAddress = async (fnName: string) => {
      it('can be called by owner', async () => {
        await exchange[fnName](admin.address);
      });
      it('reverts when not called by owner', async () => {
        await expect(
          exchange.connect(alice)[fnName](admin.address),
        ).to.be.revertedWith('Ownable: caller is not the owner');
      });
      it('reverts when address is 0', async () => {
        await expect(exchange[fnName](ZERO_ADDRESS)).to.be.revertedWith(
          'Address cannot be zero',
        );
      });
    };

    describe('setOracle', async () => setAddress('setOracle'));
    describe('setExecutionDelegate', async () =>
      setAddress('setExecutionDelegate'));
    describe('setPolicyManager', async () => setAddress('setPolicyManager'));

    describe('setBlockRange', async () => {
      it('can be called by owner', async () => {
        await exchange.setBlockRange(5);
      });
      it('reverts when not called by owner', async () => {
        await expect(
          exchange.connect(alice).setBlockRange(5),
        ).to.be.revertedWith('Ownable: caller is not the owner');
      });
    });

    describe('close', async () => {
      it('can be called by owner', async () => {
        await exchange.close();
      });
      it('reverts when not called by owner', async () => {
        await expect(exchange.connect(alice).close()).to.be.revertedWith(
          'Ownable: caller is not the owner',
        );
      });
    });
    describe('open', async () => {
      it('can be called by owner', async () => {
        await exchange.open();
      });
      it('reverts when not called by owner', async () => {
        await expect(exchange.connect(alice).open()).to.be.revertedWith(
          'Ownable: caller is not the owner',
        );
      });
    });
  };
}
