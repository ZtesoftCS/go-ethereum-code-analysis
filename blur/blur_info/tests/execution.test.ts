import { expect } from 'chai';
import { Wallet, Contract, BigNumber } from 'ethers';

import type { CheckBalances, GenerateOrder } from './exchange';
import { eth, Order } from './exchange';
import { Side, ZERO_ADDRESS } from './exchange/utils';
import { waitForTx } from '../scripts/web3-utils';

export function runExecuteTests(setupTest: any) {
  return async () => {
    const INVERSE_BASIS_POINT = 10000;
    const price: BigNumber = eth('1');
    const feeRate = 300;

    let exchange: Contract;
    let executionDelegate: Contract;
    let matchingPolicies: Record<string, Contract>;

    let admin: Wallet;
    let alice: Wallet;
    let bob: Wallet;
    let thirdParty: Wallet;

    let weth: Contract;
    let mockERC721: Contract;
    let mockERC1155: Contract;

    let generateOrder: GenerateOrder;
    let checkBalances: CheckBalances;

    let sell: Order;
    let sellInput: any;
    let buy: Order;
    let buyInput: any;
    let otherOrders: Order[];
    let fee: BigNumber;
    let priceMinusFee: BigNumber;
    let tokenId: number;

    let aliceBalance: BigNumber;
    let aliceBalanceWeth: BigNumber;
    let bobBalance: BigNumber;
    let bobBalanceWeth: BigNumber;
    let feeRecipientBalance: BigNumber;
    let feeRecipientBalanceWeth: BigNumber;

    const updateBalances = async () => {
      aliceBalance = await alice.getBalance();
      aliceBalanceWeth = await weth.balanceOf(alice.address);
      bobBalance = await bob.getBalance();
      bobBalanceWeth = await weth.balanceOf(bob.address);
      feeRecipientBalance = await admin.provider.getBalance(thirdParty.address);
      feeRecipientBalanceWeth = await weth.balanceOf(thirdParty.address);
    };

    before(async () => {
      ({
        admin,
        alice,
        bob,
        thirdParty,
        weth,
        matchingPolicies,
        mockERC721,
        mockERC1155,
        tokenId,
        exchange,
        executionDelegate,
        generateOrder,
        checkBalances,
      } = await setupTest());
    });

    beforeEach(async () => {
      await updateBalances();
      tokenId += 1;
      await mockERC721.mint(alice.address, tokenId);

      fee = price.mul(feeRate).div(INVERSE_BASIS_POINT);
      priceMinusFee = price.sub(fee);

      sell = generateOrder(alice, {
        side: Side.Sell,
        tokenId,
      });

      buy = generateOrder(bob, { side: Side.Buy, tokenId });

      otherOrders = [
        generateOrder(alice, { salt: 1 }),
        generateOrder(alice, { salt: 2 }),
        generateOrder(alice, { salt: 3 }),
      ];

      sellInput = await sell.pack();
      buyInput = await buy.pack();
    });

    it('can transfer ERC1155', async () => {
      await mockERC1155.mint(alice.address, tokenId, 1);
      sell = generateOrder(alice, {
        side: Side.Sell,
        tokenId,
        amount: 1,
        collection: mockERC1155.address,
        matchingPolicy: matchingPolicies.standardPolicyERC1155.address,
      });
      buy = generateOrder(bob, {
        side: Side.Buy,
        tokenId,
        amount: 1,
        collection: mockERC1155.address,
        matchingPolicy: matchingPolicies.standardPolicyERC1155.address,
      });
      sellInput = await sell.pack();
      buyInput = await buy.pack();

      await waitForTx(exchange.execute(sellInput, buyInput));

      expect(await mockERC1155.balanceOf(bob.address, tokenId)).to.be.equal(1);
      await checkBalances(
        aliceBalance,
        aliceBalanceWeth.add(priceMinusFee),
        bobBalance,
        bobBalanceWeth.sub(price),
        feeRecipientBalance,
        feeRecipientBalanceWeth.add(fee),
      );
    });
    it('should revert with ERC20 not WETH', async () => {
      sell.parameters.paymentToken = mockERC721.address;
      buy.parameters.paymentToken = mockERC721.address;
      sellInput = await sell.pack();
      buyInput = await buy.packNoSigs();

      await expect(
        exchange.connect(bob).execute(sellInput, buyInput),
      ).to.be.revertedWith('Invalid payment token');
    });
    it('should revert if Exchange is not approved by ExecutionDelegate', async () => {
      await executionDelegate.denyContract(exchange.address);

      buyInput = await buy.packNoSigs();

      await expect(
        exchange.connect(bob).execute(sellInput, buyInput),
      ).to.be.revertedWith('Contract is not approved to make transfers');
      await executionDelegate.approveContract(exchange.address);
    });
    it('should succeed is approval is given', async () => {
      await executionDelegate.approveContract(exchange.address);
      buyInput = await buy.packNoSigs();
      const tx = await waitForTx(
        exchange.connect(bob).execute(sellInput, buyInput),
      );
      const gasFee = tx.gasUsed.mul(tx.effectiveGasPrice);

      expect(await mockERC721.ownerOf(tokenId)).to.be.equal(bob.address);
      await checkBalances(
        aliceBalance,
        aliceBalanceWeth.add(priceMinusFee),
        bobBalance.sub(gasFee),
        bobBalanceWeth.sub(price),
        feeRecipientBalance,
        feeRecipientBalanceWeth.add(fee),
      );
    });
    it('should revert if user revokes approval from ExecutionDelegate', async () => {
      await executionDelegate.connect(alice).revokeApproval();
      await expect(
        exchange.connect(bob).execute(sellInput, buyInput),
      ).to.be.revertedWith('User has revoked approval');
      await executionDelegate.approveContract(exchange.address);
    });
    it('should succeed if user grants approval to ExecutionDelegate', async () => {
      await executionDelegate.connect(alice).grantApproval();
      await updateBalances();
      const tx = await waitForTx(
        exchange.connect(bob).execute(sellInput, buyInput),
      );
      const gasFee = tx.gasUsed.mul(tx.effectiveGasPrice);

      expect(await mockERC721.ownerOf(tokenId)).to.be.equal(bob.address);
      await checkBalances(
        aliceBalance,
        aliceBalanceWeth.add(priceMinusFee),
        bobBalance.sub(gasFee),
        bobBalanceWeth.sub(price),
        feeRecipientBalance,
        feeRecipientBalanceWeth.add(fee),
      );
    });
    it('buyer sends tx with ETH', async () => {
      sell.parameters.paymentToken = ZERO_ADDRESS;
      buy.parameters.paymentToken = ZERO_ADDRESS;
      sellInput = await sell.pack();
      buyInput = await buy.packNoSigs();

      const tx = await waitForTx(
        exchange.connect(bob).execute(sellInput, buyInput, { value: price }),
      );
      const gasFee = tx.gasUsed.mul(tx.effectiveGasPrice);

      expect(await mockERC721.ownerOf(tokenId)).to.be.equal(bob.address);
      await checkBalances(
        aliceBalance.add(priceMinusFee),
        aliceBalanceWeth,
        bobBalance.sub(price).sub(gasFee),
        bobBalanceWeth,
        feeRecipientBalance.add(fee),
        feeRecipientBalanceWeth,
      );
    });
    it('buyer sends tx with WETH', async () => {
      buyInput = await buy.packNoSigs();
      const tx = await waitForTx(
        exchange.connect(bob).execute(sellInput, buyInput),
      );
      const gasFee = tx.gasUsed.mul(tx.effectiveGasPrice);

      expect(await mockERC721.ownerOf(tokenId)).to.be.equal(bob.address);
      await checkBalances(
        aliceBalance,
        aliceBalanceWeth.add(priceMinusFee),
        bobBalance.sub(gasFee),
        bobBalanceWeth.sub(price),
        feeRecipientBalance,
        feeRecipientBalanceWeth.add(fee),
      );
    });
    it('seller tx fails with ETH', async () => {
      sell.parameters.paymentToken = ZERO_ADDRESS;
      buy.parameters.paymentToken = ZERO_ADDRESS;
      sellInput = await sell.packNoSigs();
      buyInput = await buy.pack();

      await expect(exchange.connect(alice).execute(sellInput, buyInput)).to.be
        .reverted;
    });
    it('seller sends tx with WETH', async () => {
      sellInput = await sell.packNoSigs();

      const tx = await waitForTx(
        exchange.connect(alice).execute(sellInput, buyInput),
      );
      const gasFee = tx.gasUsed.mul(tx.effectiveGasPrice);

      expect(await mockERC721.ownerOf(tokenId)).to.be.equal(bob.address);
      await checkBalances(
        aliceBalance.sub(gasFee),
        aliceBalanceWeth.add(priceMinusFee),
        bobBalance,
        bobBalanceWeth.sub(price),
        feeRecipientBalance,
        feeRecipientBalanceWeth.add(fee),
      );
    });
    it('random tx fails with ETH', async () => {
      sell.parameters.paymentToken = ZERO_ADDRESS;
      buy.parameters.paymentToken = ZERO_ADDRESS;
      sellInput = await sell.pack();
      buyInput = await buy.pack();

      await expect(exchange.execute(sellInput, buyInput)).to.be.reverted;
    });
    it('random sends tx with WETH', async () => {
      await exchange.execute(sellInput, buyInput);

      expect(await mockERC721.ownerOf(tokenId)).to.be.equal(bob.address);
      await checkBalances(
        aliceBalance,
        aliceBalanceWeth.add(priceMinusFee),
        bobBalance,
        bobBalanceWeth.sub(price),
        feeRecipientBalance,
        feeRecipientBalanceWeth.add(fee),
      );
    });
    it("should revert if seller doesn't own token", async () => {
      await mockERC721
        .connect(alice)
        .transferFrom(alice.address, bob.address, tokenId);
      await expect(exchange.execute(sellInput, buyInput)).to.be.reverted;
    });
    it('can cancel order', async () => {
      await exchange.connect(bob).cancelOrder(buy.parameters);
      await expect(exchange.execute(sellInput, buyInput)).to.be.revertedWith(
        'Buy has invalid parameters',
      );
    });
    it('can cancel bulk listing', async () => {
      sellInput = await sell.packBulk(otherOrders);
      await exchange.connect(alice).cancelOrder(sell.parameters);
      await expect(exchange.execute(sellInput, buyInput)).to.be.revertedWith(
        'Sell has invalid parameters',
      );
    });
    it('can cancel multiple orders', async () => {
      const buy2 = generateOrder(bob, { side: Side.Buy, tokenId });
      const buyInput2 = await buy2.pack();
      await exchange
        .connect(bob)
        .cancelOrders([buy.parameters, buy2.parameters]);
      await expect(exchange.execute(sellInput, buyInput)).to.be.revertedWith(
        'Buy has invalid parameters',
      );
      await expect(exchange.execute(sellInput, buyInput2)).to.be.revertedWith(
        'Buy has invalid parameters',
      );
    });
    it('should not cancel if not user', async () => {
      await expect(exchange.connect(alice).cancelOrder(buy.parameters)).to.be
        .reverted;
    });
    it('should not match with invalid parameters sell', async () => {
      await exchange.connect(bob).cancelOrder(buy.parameters);
      await expect(exchange.execute(sellInput, buyInput)).to.be.revertedWith(
        'Buy has invalid parameters',
      );
    });
    it('should not match with invalid parameters buy', async () => {
      await exchange.connect(bob).cancelOrder(buy.parameters);
      await expect(exchange.execute(sellInput, buyInput)).to.be.revertedWith(
        'Buy has invalid parameters',
      );
    });
    it('should not match with invalid signatures sell', async () => {
      sellInput = await sell.pack({ signer: bob });
      await expect(exchange.execute(sellInput, buyInput)).to.be.revertedWith(
        'Sell failed authorization',
      );
    });
    it('should not match with invalid signatures buy', async () => {
      buyInput = await buy.pack({ signer: alice });
      await expect(exchange.execute(sellInput, buyInput)).to.be.revertedWith(
        'Buy failed authorization',
      );
    });
    it('should revert if orders cannot be matched', async () => {
      sell.parameters.price = BigNumber.from('1');
      sellInput = await sell.pack();

      await expect(
        exchange.connect(bob).execute(sellInput, buyInput),
      ).to.be.revertedWith('Orders cannot be matched');
    });
    it('should revert policy is not whitelisted', async () => {
      sell.parameters.matchingPolicy = ZERO_ADDRESS;
      buy.parameters.matchingPolicy = ZERO_ADDRESS;
      sellInput = await sell.pack();
      buyInput = await buy.packNoSigs();

      await expect(
        exchange.connect(bob).execute(sellInput, buyInput),
      ).to.be.revertedWith('Policy is not whitelisted');
    });
    it('should revert if buyer has insufficient funds ETH', async () => {
      sell.parameters.paymentToken = ZERO_ADDRESS;
      buy.parameters.paymentToken = ZERO_ADDRESS;
      sellInput = await sell.pack();
      buyInput = await buy.packNoSigs();

      await expect(exchange.connect(bob).execute(sellInput, buyInput)).to.be
        .reverted;
    });
    it('should revert if buyer has insufficient funds WETH', async () => {
      sell.parameters.price = BigNumber.from('10000000000000000000000000000');
      buy.parameters.price = BigNumber.from('10000000000000000000000000000');
      sellInput = await sell.pack();
      buyInput = await buy.packNoSigs();

      await expect(exchange.connect(bob).execute(sellInput, buyInput)).to.be
        .reverted;
    });
    it('should revert if fee rates exceed 10000', async () => {
      sell.parameters.fees.push({ rate: 9701, recipient: thirdParty.address });
      sellInput = await sell.pack();

      await expect(exchange.connect(bob).execute(sellInput, buyInput)).to.be
        .reverted;
    });
    it('cancel all previous orders and match with new nonce', async () => {
      await exchange.connect(alice).incrementNonce();
      await exchange.connect(bob).incrementNonce();
      sellInput = await sell.pack();
      buyInput = await buy.pack();

      await updateBalances();

      await exchange.execute(sellInput, buyInput);

      expect(await mockERC721.ownerOf(tokenId)).to.be.equal(bob.address);
      await checkBalances(
        aliceBalance,
        aliceBalanceWeth.add(priceMinusFee),
        bobBalance,
        bobBalanceWeth.sub(price),
        feeRecipientBalance,
        feeRecipientBalanceWeth.add(fee),
      );
    });
    it('should not match with wrong order nonce sell', async () => {
      await exchange.connect(alice).incrementNonce();
      await expect(exchange.execute(sellInput, buyInput)).to.be.revertedWith(
        'Sell failed authorization',
      );
    });
    it('should not match with wrong order nonce buy', async () => {
      await exchange.connect(bob).incrementNonce();
      await expect(exchange.execute(sellInput, buyInput)).to.be.revertedWith(
        'Buy failed authorization',
      );
    });
    it('should not match filled order sell', async () => {
      await waitForTx(exchange.execute(sellInput, buyInput));
      await expect(exchange.execute(sellInput, buyInput)).to.be.revertedWith(
        'Sell has invalid parameters',
      );
    });
    it('should not match filled order buy', async () => {
      await waitForTx(exchange.execute(sellInput, buyInput));
      sell = generateOrder(alice, {
        side: Side.Sell,
        tokenId,
        salt: 1,
      });
      sellInput = await sell.pack();
      await expect(exchange.execute(sellInput, buyInput)).to.be.revertedWith(
        'Buy has invalid parameters',
      );
    });
    it('should revert if closed', async () => {
      await exchange.close();
      await expect(exchange.execute(sellInput, buyInput)).to.be.revertedWith(
        'Closed',
      );
    });
    it('should succeed if reopened', async () => {
      await exchange.open();

      buyInput = await buy.packNoSigs();
      const tx = await waitForTx(
        exchange.connect(bob).execute(sellInput, buyInput),
      );
      const gasFee = tx.gasUsed.mul(tx.effectiveGasPrice);

      expect(await mockERC721.ownerOf(tokenId)).to.be.equal(bob.address);
      await checkBalances(
        aliceBalance,
        aliceBalanceWeth.add(priceMinusFee),
        bobBalance.sub(gasFee),
        bobBalanceWeth.sub(price),
        feeRecipientBalance,
        feeRecipientBalanceWeth.add(fee),
      );
    });
  };
}
