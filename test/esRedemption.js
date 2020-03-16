const {
  BN, constants, ether, send,
} = require('@openzeppelin/test-helpers');

const { expect } = require('chai');

const ESRedemption = artifacts.require('ESRedemption');

const {
  sendToken,
  getTokenBalance,
  daiAddress,
  chaiAddress,
  DaiContract,
  ChaiContract,
} = require('../helpers.js');

const MAX_UINT256_STRING = constants.MAX_UINT256.toString();

// =================================================================================================
//                                            Swapper Tests
// =================================================================================================

contract('ESRedemption', async (accounts) => {
  const floatify = process.env.FLOATIFY_ADDRESS; // contract deployer
  const exchange = process.env.EXCHANGE_ADDRESS; // used to obtain Dai and Chai for testing
  const alice = accounts[0];
  const liquidation = accounts[2]; // address to send alice's ETH to so it's liquidated to their bank

  const dai = daiAddress;
  const chai = chaiAddress;

  let ESRedemptionInstance; // contract instance
  let esRedemption; // address

  beforeEach(async () => {
    // 1. Deploy ESRedemption instance
    ESRedemptionInstance = await ESRedemption.new({ from: floatify });
    esRedemption = ESRedemptionInstance.address;
    await ESRedemptionInstance.initializeEsRedemption({ from: floatify });

    // 2. Chai and Dai approvals
    await send.ether(exchange, alice, ether('1'));
    await ChaiContract.methods.approve(esRedemption, MAX_UINT256_STRING).send({ from: alice });
    await DaiContract.methods.approve(esRedemption, MAX_UINT256_STRING).send({ from: alice });
  });

  // ======================================= Initialization ========================================
  it('deploys properly', async () => {
    expect(esRedemption.startsWith('0x')).to.be.true;
  });

  it('has proper owner', async () => {
    expect(await ESRedemptionInstance.owner()).to.equal(floatify);
  });

  it("should have approval to spend alice's Dai and Chai", async () => {
    const chaiAllowance = await ChaiContract.methods.allowance(alice, esRedemption).call();
    expect(chaiAllowance).to.equal(MAX_UINT256_STRING);
    const daiAllowance = await DaiContract.methods.allowance(alice, esRedemption).call();
    expect(daiAllowance).to.equal(MAX_UINT256_STRING);
  });

  // ======================================== Functionality ========================================
  // NOTE: The private functions must be set to public for these tests to pass
  it('lets USDC in the contract be sent to caller', async () => {
    // Send USDC to the contract
    const amount = '100000000'; // 100 USDC, since it has 6 decimal places
    await sendToken('usdc', exchange, esRedemption, amount);
    expect(await getTokenBalance('usdc', esRedemption)).to.equal(amount);
    expect(await getTokenBalance('usdc', alice)).to.equal('0');
    // Transfer them out
    await ESRedemptionInstance.sendUsdcToCaller({ from: alice });
    expect(await getTokenBalance('usdc', esRedemption)).to.equal('0');
    expect(await getTokenBalance('usdc', alice)).to.equal(amount);
    // Burn tokens to reset balances (zero address reverts)
    await sendToken('usdc', alice, '0x0000000000000000000000000000000000000001', amount);
  });

  it('lets ETH in the contract be swapped for USDC', async () => {
    // Send ETH to the contract
    await send.ether(exchange, esRedemption, ether('1'));
    expect(await getTokenBalance('eth', alice)).to.be.bignumber.above('0'); // Ether balance
    expect(await getTokenBalance('usdc', esRedemption)).to.equal('0');
    expect(await getTokenBalance('usdc', alice)).to.equal('0');
    // Convert ETH to USDC
    await ESRedemptionInstance.swapEtherForUsdc({ from: alice });
    expect(parseInt(await getTokenBalance('usdc', esRedemption), 10)).to.be.above(0);
    expect(await getTokenBalance('usdc', alice)).to.equal('0');
  });

  it('lets BAT in the contract be swapped for USDC', async () => {
    // Send BAT to the contract
    const amount = '100000000000000000000'; // 100 BAT
    await sendToken('bat', exchange, esRedemption, amount);
    expect(await getTokenBalance('bat', esRedemption)).to.equal(amount);
    expect(await getTokenBalance('bat', alice)).to.equal('0');
    // Convert BAT to USDC
    await ESRedemptionInstance.swapBatForUsdc({ from: alice });
    expect(parseInt(await getTokenBalance('usdc', esRedemption), 10)).to.be.above(0);
    expect(await getTokenBalance('usdc', alice)).to.equal('0');
  });

  it.skip('lets DAI be redeemed for collateral', async () => {
    // TODO
  });

  it('lets alice\'s Chai be swapped for Dai', async () => {
    // Use exchange account to mint Chai and send it to Alice
    const amount = '100000000000000000000'; // 100 Chai
    await DaiContract.methods
      .approve(chai, MAX_UINT256_STRING)
      .send({ from: exchange, gas: '2000000' });
    await ChaiContract.methods.join(alice, amount).send({ from: exchange, gas: '2000000' });
    expect(new BN(await getTokenBalance('chai', alice))).to.be.bignumber.below(amount);
    expect(new BN(await getTokenBalance('chai', alice))).to.be.bignumber.above('0');
    expect(await getTokenBalance('dai', esRedemption)).to.be.equal('0');
    // Swap Dai for Chai
    await ESRedemptionInstance.swapChaiForDai(MAX_UINT256_STRING, { from: alice });
    expect(new BN(await getTokenBalance('dai', esRedemption))).to.be.bignumber.above('0');
    expect(await getTokenBalance('chai', alice)).to.be.equal('0');
  });
});
