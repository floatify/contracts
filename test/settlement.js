const { constants, send, ether } = require('@openzeppelin/test-helpers');

const { expect } = require('chai');

const Settlement = artifacts.require('Settlement');

const {
  sendToken,
  getTokenBalance,
  checkTokenAllowance,
  daiAddress,
  chaiAddress,
  makerAddress,
  kyberAddress,
  saiAddress,
  cdaiAddress,
  DaiContract,
  SaiContract,
  ChaiContract,
  CdaiContract,
} = require('../helpers.js');

const MAX_UINT256_STRING = constants.MAX_UINT256.toString();

// =================================================================================================
//                                            Swapper Tests
// =================================================================================================

contract('Settlement', async (accounts) => {
  const floatify = process.env.FLOATIFY_ADDRESS; // contract deployer
  const exchange = process.env.EXCHANGE_ADDRESS; // used to obtain Dai and Chai for testing
  const alice = accounts[0];
  const liquidation = accounts[2]; // address to send alice's ETH to so it's liquidated to their bank

  const dai = daiAddress;
  const chai = chaiAddress;

  let SettlementInstance; // contract instance
  let settlement; // address

  beforeEach(async () => {
    // 1. Deploy Settlement instance
    SettlementInstance = await Settlement.new({ from: floatify });
    settlement = SettlementInstance.address;
    await SettlementInstance.initializeSettlement({ from: floatify });

    // 2. Chai and Dai approvals
    await send.ether(exchange, alice, ether('1'));
    await ChaiContract.methods.approve(settlement, MAX_UINT256_STRING).send({ from: alice });
    await DaiContract.methods.approve(settlement, MAX_UINT256_STRING).send({ from: alice });
  });

  // ======================================= Initialization ========================================
  it('deploys properly', async () => {
    expect(settlement.startsWith('0x')).to.be.true;
  });

  it('has proper owner', async () => {
    expect(await SettlementInstance.owner()).to.equal(floatify);
  });

  it("should have approval to spend alice's Dai and Chai", async () => {
    const chaiAllowance = await ChaiContract.methods.allowance(alice, settlement).call();
    expect(chaiAllowance).to.equal(MAX_UINT256_STRING);
    const daiAllowance = await DaiContract.methods.allowance(alice, settlement).call();
    expect(daiAllowance).to.equal(MAX_UINT256_STRING);
  });

  // ======================================== Functionality ========================================
  // TODO
});
