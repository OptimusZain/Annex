const {
  bnbGasCost,
  bnbMantissa,
  bnbUnsigned,
  sendFallback
} = require('./Utils/BSC');

const {
  makeToken,
  balanceOf
} = require('./Utils/Annex');

const transferAmount = bnbMantissa(1000);

async function makeTreasury(opts = {}) {
  const {
    root = saddle.account,
    kind = 'aTreasury'
  } = opts || {};

  if (kind == 'aTreasury') {
    return await deploy('ATreasury', []);
  }
}

async function withdrawTreausry(aTreasury, tokenAddress, withdrawAmount, withdrawAddress, caller) {
  return send(aTreasury, 'withdrawTreasury', 
    [
      tokenAddress,
      withdrawAmount,
      withdrawAddress,      
    ], { from: caller });
}

describe('ATreasury', function () {
  let root, minter, redeemer, accounts;
  let aTreasury
  let bep20Token;

  beforeEach(async () => {
    [root, minter, redeemer, ...accounts] = saddle.accounts;
    // Create New Bep20 Token
    bep20Token = await makeToken();
    // Create New aTreasury
    aTreasury = await makeTreasury();
    // Transfer to aTreasury Contract
    send(bep20Token, 'transfer', [aTreasury._address, transferAmount]);
  });

  it ('Check Owner', async() => {
    const treasuryOwner = await call(aTreasury, 'owner', []);
    expect(treasuryOwner).toEqual(root);
  });

  it ('Check Change Owner', async() => {
    await send(aTreasury, 'transferOwnership', [accounts[0]], { from: root });
    const newTreasuryOwner = await call(aTreasury, 'owner', []);
    expect(newTreasuryOwner).toEqual(accounts[0]);
  })


  it ('Check Wrong Owner', async() => {
    // Call withdrawTreausry with wrong owner
    await expect(withdrawTreausry(aTreasury, bep20Token._address, transferAmount, accounts[0], accounts[1]))
      .rejects
      .toRevert("revert Ownable: caller is not the owner");
  });

  it ('Check Wrong Withdraw Amount', async() => {
    const wrongWithdrawAmount = bnbMantissa(1001);
    // Call withdrawTreasury with wrong amount
    await expect(withdrawTreausry(aTreasury, bep20Token._address, wrongWithdrawAmount, accounts[0], root))
      .rejects
      .toRevert("revert The withdraw amount should be less than balance of treasury");
  });

  it ('Check withdrawTreasury', async() => {
    // Check Before Balance
    expect(bnbUnsigned(await call(bep20Token, 'balanceOf', [aTreasury._address]))).toEqual(transferAmount);

    // Call withdrawTreasury
    await withdrawTreausry(
      aTreasury,
      bep20Token._address,
      transferAmount,
      accounts[0],
      root
    );

    // Check After Balance
    expect(await call(bep20Token, 'balanceOf', [aTreasury._address])).toEqual('0');
    // Check withdrawAddress Balance
    expect(bnbUnsigned(await call(bep20Token, 'balanceOf', [accounts[0]]))).toEqual(transferAmount);
  })
});
