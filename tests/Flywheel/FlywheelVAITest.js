const {
  makeComptroller,
  makeVAI,
  balanceOf,
  fastForward,
  pretendVAIMint,
  quickMint,
  quickMintVAI
} = require('../Utils/Annex');
const {
  bnbExp,
  bnbDouble,
  bnbUnsigned
} = require('../Utils/BSC');

const annexVAIRate = bnbUnsigned(5e17);

async function annexAccrued(comptroller, user) {
  return bnbUnsigned(await call(comptroller, 'annexAccrued', [user]));
}

async function annBalance(comptroller, user) {
  return bnbUnsigned(await call(comptroller.ann, 'balanceOf', [user]))
}

async function totalAnnexAccrued(comptroller, user) {
  return (await annexAccrued(comptroller, user)).add(await annBalance(comptroller, user));
}

describe('Flywheel', () => {
  let root, a1, a2, a3, accounts;
  let comptroller, vaicontroller, vai;
  beforeEach(async () => {
    [root, a1, a2, a3, ...accounts] = saddle.accounts;
    comptroller = await makeComptroller();
    vai = comptroller.vai;
    vaicontroller = comptroller.vaiunitroller;
  });

  describe('updateAnnexVAIMintIndex()', () => {
    it('should calculate ann vai minter index correctly', async () => {
      await send(vaicontroller, 'setBlockNumber', [100]);
      await send(vai, 'harnessSetTotalSupply', [bnbUnsigned(10e18)]);
      await send(comptroller, '_setAnnexVAIRate', [bnbExp(0.5)]);
      await send(vaicontroller, 'harnessUpdateAnnexVAIMintIndex');
      /*
        vaiTokens = 10e18
        annexAccrued = deltaBlocks * setAnnexVAIRate
                    = 100 * 0.5e18 = 50e18
        newIndex   += annexAccrued * 1e36 / vaiTokens
                    = 1e36 + 50e18 * 1e36 / 10e18 = 6e36
      */

      const {index, block} = await call(vaicontroller, 'annexVAIState');
      expect(index).toEqualNumber(6e36);
      expect(block).toEqualNumber(100);
    });

    it('should not update index if no blocks passed since last accrual', async () => {
      await send(vaicontroller, 'harnessUpdateAnnexVAIMintIndex');

      const {index, block} = await call(vaicontroller, 'annexVAIState');
      expect(index).toEqualNumber(1e36);
      expect(block).toEqualNumber(0);
    });
  });

  describe('distributeVAIMinterAnnex()', () => {
    it('should update vai minter index checkpoint but not annexAccrued for first time user', async () => {
      await send(vaicontroller, "setAnnexVAIState", [bnbDouble(6), 10]);
      await send(vaicontroller, "setAnnexVAIMinterIndex", [root, bnbUnsigned(0)]);

      await send(comptroller, "harnessDistributeVAIMinterAnnex", [root]);
      expect(await call(comptroller, "annexAccrued", [root])).toEqualNumber(0);
      expect(await call(vaicontroller, "annexVAIMinterIndex", [root])).toEqualNumber(6e36);
    });

    it('should transfer ann and update vai minter index checkpoint correctly for repeat time user', async () => {
      await send(comptroller.ann, 'transfer', [comptroller._address, bnbUnsigned(50e18)], {from: root});
      await send(vai, "harnessSetBalanceOf", [a1, bnbUnsigned(5e18)]);
      await send(comptroller, "harnessSetMintedVAIs", [a1, bnbUnsigned(5e18)]);
      await send(vaicontroller, "setAnnexVAIState", [bnbDouble(6), 10]);
      await send(vaicontroller, "setAnnexVAIMinterIndex", [a1, bnbDouble(1)]);

      /*
      * 100 delta blocks, 10e18 origin total vai mint, 0.5e18 vaiMinterSpeed => 6e18 annexVAIMintIndex
      * this tests that an acct with half the total vai mint over that time gets 25e18 ANN
        vaiMinterAmount = vaiBalance * 1e18
                       = 5e18 * 1e18 = 5e18
        deltaIndex     = marketStoredIndex - userStoredIndex
                       = 6e36 - 1e36 = 5e36
        vaiMinterAccrued= vaiMinterAmount * deltaIndex / 1e36
                       = 5e18 * 5e36 / 1e36 = 25e18
      */
      const tx = await send(comptroller, "harnessDistributeVAIMinterAnnex", [a1]);
      expect(await annexAccrued(comptroller, a1)).toEqualNumber(25e18);
      expect(await annBalance(comptroller, a1)).toEqualNumber(0);
      expect(tx).toHaveLog('DistributedVAIMinterAnnex', {
        vaiMinter: a1,
        annexDelta: bnbUnsigned(25e18).toString(),
        annexVAIMintIndex: bnbDouble(6).toString()
      });
    });

    it('should not transfer if below ann claim threshold', async () => {
      await send(comptroller.ann, 'transfer', [comptroller._address, bnbUnsigned(50e18)], {from: root});

      await send(vai, "harnessSetBalanceOf", [a1, bnbUnsigned(5e17)]);
      await send(comptroller, "harnessSetMintedVAIs", [a1, bnbUnsigned(5e17)]);
      await send(vaicontroller, "setAnnexVAIState", [bnbDouble(1.0019), 10]);
      /*
        vaiMinterAmount  = 5e17
        deltaIndex      = marketStoredIndex - userStoredIndex
                        = 1.0019e36 - 1e36 = 0.0019e36
        vaiMintedAccrued+= vaiMinterTokens * deltaIndex / 1e36
                        = 5e17 * 0.0019e36 / 1e36 = 0.00095e18
      */

      await send(comptroller, "harnessDistributeVAIMinterAnnex", [a1]);
      expect(await annexAccrued(comptroller, a1)).toEqualNumber(0.00095e18);
      expect(await annBalance(comptroller, a1)).toEqualNumber(0);
    });
  });

  describe('claimAnnex', () => {
    it('should accrue ann and then transfer ann accrued', async () => {
      const annRemaining = annexVAIRate.mul(100), mintAmount = bnbUnsigned(12e18), deltaBlocks = 10;
      await send(comptroller.ann, 'transfer', [comptroller._address, annRemaining], {from: root});
      //await pretendVAIMint(vai, a1, 1, 1, 100);
      const speed = await call(comptroller, 'annexVAIRate');
      const a2AccruedPre = await annexAccrued(comptroller, a2);
      const annBalancePre = await annBalance(comptroller, a2);
      await quickMintVAI(comptroller, vai, a2, mintAmount);
      await fastForward(vaicontroller, deltaBlocks);
      const tx = await send(comptroller, 'claimAnnex', [a2]);
      const a2AccruedPost = await annexAccrued(comptroller, a2);
      const annBalancePost = await annBalance(comptroller, a2);
      expect(tx.gasUsed).toBeLessThan(400000);
      expect(speed).toEqualNumber(annexVAIRate);
      expect(a2AccruedPre).toEqualNumber(0);
      expect(a2AccruedPost).toEqualNumber(0);
      expect(annBalancePre).toEqualNumber(0);
      expect(annBalancePost).toEqualNumber(annexVAIRate.mul(deltaBlocks).sub(1)); // index is 8333...
    });

    it('should claim when ann accrued is below threshold', async () => {
      const annRemaining = bnbExp(1), accruedAmt = bnbUnsigned(0.0009e18)
      await send(comptroller.ann, 'transfer', [comptroller._address, annRemaining], {from: root});
      await send(comptroller, 'setAnnexAccrued', [a1, accruedAmt]);
      await send(comptroller, 'claimAnnex', [a1]);
      expect(await annexAccrued(comptroller, a1)).toEqualNumber(0);
      expect(await annBalance(comptroller, a1)).toEqualNumber(accruedAmt);
    });
  });

  describe('claimAnnex batch', () => {
    it('should claim the expected amount when holders and arg is duplicated', async () => {
      const annRemaining = annexVAIRate.mul(100), deltaBlocks = 10, mintAmount = bnbExp(10);
      await send(comptroller.ann, 'transfer', [comptroller._address, annRemaining], {from: root});
      let [_, __, ...claimAccts] = saddle.accounts;
      for(let from of claimAccts) {
        await send(vai, 'harnessIncrementTotalSupply', [mintAmount]);
        expect(await send(vai, 'harnessSetBalanceOf', [from, mintAmount], { from })).toSucceed();
        expect(await await send(comptroller, 'harnessSetMintedVAIs', [from, mintAmount], { from })).toSucceed();
      }
      await fastForward(vaicontroller, deltaBlocks);

      const tx = await send(comptroller, 'claimAnnex', [[...claimAccts, ...claimAccts], [], false, false]);
      // ann distributed => 10e18
      for(let acct of claimAccts) {
        expect(await call(vaicontroller, 'annexVAIMinterIndex', [acct])).toEqualNumber(bnbDouble(1.0625));
        expect(await annBalance(comptroller, acct)).toEqualNumber(bnbExp(0.625));
      }
    });

    it('claims ann for multiple vai minters only, primes uninitiated', async () => {
      const annRemaining = annexVAIRate.mul(100), deltaBlocks = 10, mintAmount = bnbExp(10), vaiAmt = bnbExp(1), vaiMintIdx = bnbExp(1)
      await send(comptroller.ann, 'transfer', [comptroller._address, annRemaining], {from: root});
      let [_,__, ...claimAccts] = saddle.accounts;

      for(let acct of claimAccts) {
        await send(vai, 'harnessIncrementTotalSupply', [vaiAmt]);
        await send(vai, 'harnessSetBalanceOf', [acct, vaiAmt]);
        await send(comptroller, 'harnessSetMintedVAIs', [acct, vaiAmt]);
      }

      await send(vaicontroller, 'harnessFastForward', [10]);

      const tx = await send(comptroller, 'claimAnnex', [claimAccts, [], false, false]);
      for(let acct of claimAccts) {
        expect(await call(vaicontroller, 'annexVAIMinterIndex', [acct])).toEqualNumber(bnbDouble(1.625));
      }
    });
  });

  describe('_setAnnexVAIRate', () => {
    it('should correctly change annex vai rate if called by admin', async () => {
      expect(await call(comptroller, 'annexVAIRate')).toEqualNumber(annexVAIRate);
      const tx1 = await send(comptroller, '_setAnnexVAIRate', [bnbUnsigned(3e18)]);
      expect(await call(comptroller, 'annexVAIRate')).toEqualNumber(bnbUnsigned(3e18));
      const tx2 = await send(comptroller, '_setAnnexVAIRate', [bnbUnsigned(2e18)]);
      expect(await call(comptroller, 'annexVAIRate')).toEqualNumber(bnbUnsigned(2e18));
      expect(tx2).toHaveLog('NewAnnexVAIRate', {
        oldAnnexVAIRate: bnbUnsigned(3e18),
        newAnnexVAIRate: bnbUnsigned(2e18)
      });
    });

    it('should not change annex vai rate unless called by admin', async () => {
      await expect(
        send(comptroller, '_setAnnexVAIRate', [bnbUnsigned(1e18)], {from: a1})
      ).rejects.toRevert('revert only admin can');
    });
  });
});
