const {
  constants,
  send,
  ether,
  expectEvent,
  expectRevert,
} = require('@openzeppelin/test-helpers');

const { expect } = require('chai');

const Forwarder = artifacts.require('Forwarder');

const {
  sendToken,
  getTokenBalance,
  checkTokenAllowance,
  daiAddress,
  chaiAddress,
  makerAddress,
  kyberAddress,
  saiAddress,
  DaiContract,
  SaiContract,
} = require('../helpers.js');

// contract("Forwarder", async ([_, owner, ...otherAccounts]) => {
contract('Forwarder', async (accounts) => {
  // Define addresses of accounts
  //   - All user accounts start with zero balance
  //   - Exchange account has lots of Ether and all tokens
  //   - Floatify account is our server and only has Ether
  const alice = accounts[0]; // alice is the owner
  const bob = accounts[1]; // alice's friend, bob
  const exchange = process.env.EXCHANGE_ADDRESS;
  const floatify = process.env.FLOATIFY_ADDRESS;
  const dai = daiAddress;
  const chai = chaiAddress;
  const maker = makerAddress;
  const kyber = kyberAddress;
  const sai = saiAddress;
  let forwarder; // address of alice's Forwarder smart contract

  // Other setup
  let ForwarderInstance; // instance

  beforeEach(async () => {
    ForwarderInstance = await Forwarder.new({ from: floatify });
    forwarder = ForwarderInstance.address;
    // Multiple versions of initialize() exist, so we need to explicitly state which
    // one to call. See Truffle release notes on overloaded Solidity functions here:
    // https://github.com/trufflesuite/truffle/releases/tag/v5.0.0#user-content-what-s-new-in-truffle-v5-interacting-with-your-contracts-overloaded-solidity-functions
    //   old line: ForwarderInstance.initialize(value, { from: owner });
    await ForwarderInstance.methods['initialize(address,address)'](alice, floatify, { from: floatify });
  });

  // ======================================= Initialization ========================================

  it("gives Chai contract an allowance of 2**256-1 to spend Alice's Dai", async () => {
    const chaiAllowance = await checkTokenAllowance('dai', forwarder, chai);
    expect(chaiAllowance).to.equal(constants.MAX_UINT256.toString());
  });

  it('properly initializes all account balances for testing', async () => {
    // Alice
    expect(await getTokenBalance('dai', alice)).to.equal('0'); // Dai balance
    expect(await getTokenBalance('eth', alice)).to.be.bignumber.equal('0'); // Ether balance
    // Alice's contract
    expect(await getTokenBalance('dai', forwarder)).to.equal('0');
    expect(await getTokenBalance('eth', forwarder)).to.be.bignumber.equal('0');
    // Bob
    expect(await getTokenBalance('dai', bob)).to.equal('0');
    expect(await getTokenBalance('eth', bob)).to.be.bignumber.equal('0');
    // Exchange
    expect(await getTokenBalance('dai', exchange)).to.not.equal('0');
    expect(await getTokenBalance('eth', exchange)).to.be.bignumber.above('0');
    // Floatify
    expect(await getTokenBalance('dai', floatify)).to.equal('0');
    expect(await getTokenBalance('eth', floatify)).to.be.bignumber.above('0');
  });

  it('has the proper owner', async () => {
    const contractOwner = await ForwarderInstance.owner();
    expect(contractOwner).to.equal(alice);
  });

  it('sets the Floatify address', async () => {
    const floatifyAddress = await ForwarderInstance.floatify();
    expect(floatifyAddress).to.equal(floatify);
  });

  it('sets the version number', async () => {
    const version = (await ForwarderInstance.version()).toString();
    expect(version).to.equal('1');
  });

  // =========================================== Updates ===========================================

  // ------------------------------------------ Ownership ------------------------------------------
  it('lets the owner be changed once they have Ether', async () => {
    // Send Ether to Alice's wallet
    await send.ether(floatify, alice, ether('1')); // 1 ether
    // Update owner
    await ForwarderInstance.transferOwnership(bob, { from: alice });
    expect(bob).to.equal(await ForwarderInstance.owner());
  });

  it('only lets the user change the owner', async () => {
    await expectRevert(
      ForwarderInstance.transferOwnership(bob, { from: floatify }),
      'Ownable: caller is not the owner',
    );
  });

  // -------------------------------------- Floatify address ---------------------------------------
  it('lets the the floatify address be changed by Floatify', async () => {
    const { logs } = await ForwarderInstance.updateFloatifyAddress(alice, { from: floatify });
    expect(alice).to.equal(await ForwarderInstance.floatify());
    await expectEvent.inLogs(logs, 'FloatifyAddressChanged', {
      previousAddress: floatify,
      newAddress: alice,
    });
  });

  it('does not let the floatify address be changed by anyone else', async () => {
    await expectRevert(
      ForwarderInstance.updateFloatifyAddress(alice, { from: bob }),
      'Forwarder: caller is not the floatify address',
    );
  });

  // ---------------------------------------- Dai contract -----------------------------------------
  it('lets the address of the Dai contract be changed by Floatify', async () => {
    // For testing purposes, we change the address to the Sai address
    expect(await ForwarderInstance.daiContract()).to.equal(dai); // confirm initial address
    const { logs } = await ForwarderInstance.updateDaiAddress(sai, { from: floatify });
    await expectEvent.inLogs(logs, 'DaiAddressChanged', {
      previousAddress: dai,
      newAddress: sai,
    });
    expect(await ForwarderInstance.daiContract()).to.equal(sai);

    // Allowance for old address should be zero and for new address should be MAX_UINT256
    const oldAllowance = await DaiContract.methods
      .allowance(forwarder, chai)
      .call();
    expect(oldAllowance).to.equal('0');

    const newAllowance = await SaiContract.methods
      .allowance(forwarder, chai)
      .call();
    expect(newAllowance).to.equal(constants.MAX_UINT256.toString());
  });

  it('does not let the address of the Dai contract be changed by anyone else', async () => {
    await expectRevert(
      ForwarderInstance.updateDaiAddress(sai, { from: alice }),
      'Forwarder: caller is not the floatify address',
    );
  });

  // ---------------------------------------- Chai contract ----------------------------------------
  it('lets the address of the Chai contract be changed by Floatify', async () => {
    // For testing purposes, we change the address to the Sai address
    expect(await ForwarderInstance.chaiContract()).to.equal(chai); // confirm initial address
    const { logs } = await ForwarderInstance.updateChaiAddress(sai, { from: floatify });
    await expectEvent.inLogs(logs, 'ChaiAddressChanged', {
      previousAddress: chai,
      newAddress: sai,
    });
    expect(await ForwarderInstance.chaiContract()).to.equal(sai);

    // Allowance for old address should be zero and for new address should be MAX_UINT256
    const oldAllowance = await DaiContract.methods
      .allowance(forwarder, chai)
      .call();
    expect(oldAllowance).to.equal('0');

    const newAllowance = await DaiContract.methods
      .allowance(forwarder, sai)
      .call();
    expect(newAllowance).to.equal(constants.MAX_UINT256.toString());
  });

  it('does not let the address of the Chai contract be changed by anyone else', async () => {
    await expectRevert(
      ForwarderInstance.updateChaiAddress(sai, { from: alice }),
      'Forwarder: caller is not the floatify address',
    );
  });

  // ------------------------------------ Kyber proxy contract -------------------------------------
  it('lets the address of the Kyber proxy contract be changed by Floatify', async () => {
    // For testing purposes, we change the address to the Sai address
    expect(await ForwarderInstance.knpContract()).to.equal(kyber); // confirm initial address
    const { logs } = await ForwarderInstance.updateKyberAddress(sai, { from: floatify });
    await expectEvent.inLogs(logs, 'KyberAddressChanged', {
      previousAddress: kyber,
      newAddress: sai,
    });
    expect(await ForwarderInstance.knpContract()).to.equal(sai);
  });

  it('does not let the address of the Kyber proxy contract be changed by anyone else', async () => {
    await expectRevert(
      ForwarderInstance.updateKyberAddress(sai, { from: alice }),
      'Forwarder: caller is not the floatify address',
    );
  });

  // --------------------------------------- Escape Hatches ----------------------------------------
  it('only lets the owner or floatify withdraw stray tokens', async () => {
    // Send Ether for gas then test
    await send.ether(floatify, exchange, ether('0.1'));
    await expectRevert(
      ForwarderInstance.sendRawTokens(makerAddress, { from: exchange }),
      'Forwarder: caller must be owner or floatify',
    );
  });
  it('only lets the owner or floatify withdraw stray Ether', async () => {
    // Send Ether for gas then test
    await send.ether(floatify, exchange, ether('0.1'));
    await expectRevert(
      ForwarderInstance.sendRawEther({ from: exchange }),
      'Forwarder: caller must be owner or floatify',
    );
  });

  // ======================================== Functionality ========================================

  /**
   * Flows to support/test right now:
   *   1. Receive Dai -> Chai -> Send to owner ----------- DONE
   *   2. Receive Ether -> Chai -> Send to owner --------- DONE (worked on mainnet, tests here fail)
   *   3. Receive token -> Chai -> Send to owner --------- DONE (worked on mainnet, tests here fail)
   */

  it('converts received Dai to Chai, and send it to the owner', async () => {
    // Send DAI to the contract
    const daiAmount = '100000000';
    await sendToken('dai', exchange, forwarder, daiAmount);
    expect(await getTokenBalance('dai', forwarder)).to.equal(daiAmount);
    expect(await getTokenBalance('chai', forwarder)).to.equal('0');
    expect(await getTokenBalance('dai', alice)).to.equal('0');
    expect(await getTokenBalance('chai', alice)).to.equal('0');
    // Mint Chai and send it to Alice
    const { logs } = await ForwarderInstance.mintAndSendChai({ from: floatify });
    await expectEvent.inLogs(logs, 'ChaiSent', { amountInDai: daiAmount });
    expect(await getTokenBalance('dai', forwarder)).to.equal('0');
    expect(await getTokenBalance('chai', forwarder)).to.equal('0');
    expect(await getTokenBalance('dai', alice)).to.equal('0');
    expect(parseFloat(await getTokenBalance('chai', alice))).to.be.above(0);
  });

  it('can receive Ether', async () => {
    expect(await getTokenBalance('eth', forwarder)).to.be.bignumber.equal('0');
    await send.ether(floatify, forwarder, ether('0.1'));
    expect(await getTokenBalance('eth', forwarder)).to.be.bignumber.equal('100000000000000000');
  });

  it('converts received Ether to Chai and sends it to the owner', async () => {
    // Make sure Alice has no Ether
    const initialEtherBalace = await getTokenBalance('eth', alice);
    await send.ether(alice, constants.ZERO_ADDRESS, initialEtherBalace);
    // Get initial balances
    const initialChaiBalance = parseFloat(await getTokenBalance('chai', alice));
    expect(await getTokenBalance('eth', alice)).to.be.bignumber.equal('0');
    // Send Ether to the forwarder contract
    await send.ether(floatify, forwarder, ether('0.1'));
    // Call function to convert Ether
    await ForwarderInstance.convertAndSendEth({ from: floatify });
    // Alice's wallet should now have Chai
    const chaiBalance = await getTokenBalance('chai', alice);
    expect(parseFloat(chaiBalance)).to.be.above(initialChaiBalance);
  });

  it('converts any received tokens to Chai and sends them to the owner', async () => {
    // Confirm initial balances
    const initialChaiBalance = parseFloat(await getTokenBalance('chai', alice));
    expect(await getTokenBalance('maker', alice)).to.equal('0');
    // Send Maker to the forwarder contract
    const makerAmount = '100000000';
    await sendToken('maker', exchange, forwarder, makerAmount);
    expect(await getTokenBalance('maker', forwarder)).to.equal(makerAmount);
    // Go from Maker > Dai > Chai and send the Chai to Alice
    await ForwarderInstance.convertAndSendToken(maker, { from: floatify });
    // Alice's wallet should now have Chai
    const chaiBalance = await getTokenBalance('chai', alice);
    expect(parseFloat(chaiBalance)).to.be.above(initialChaiBalance);
  });

  it('allows stray ERC20 tokens to be withdrawn', async () => {
    // Confirm initial balances
    const initialAliceBalance = parseInt(await getTokenBalance('maker', alice), 10);
    const initialForwarderBalance = parseInt(await getTokenBalance('maker', forwarder), 10);
    // Send Maker to the forwarder contract
    const makerAmount = '100000000';
    await sendToken('maker', exchange, forwarder, makerAmount);
    expect(await getTokenBalance('maker', alice)).to.equal(initialAliceBalance.toString());
    expect(await getTokenBalance('maker', forwarder)).to.equal(
      (initialForwarderBalance + parseInt(makerAmount, 10)).toString(),
    );
    // Withdraw the Maker to Alice's wallet from Floatify account
    await ForwarderInstance.sendRawTokens(makerAddress, { from: floatify });
    // Alice's wallet should now have Maker
    expect(await getTokenBalance('maker', alice)).to.equal(
      String(initialAliceBalance + parseInt(makerAmount, 10)),
    );
    expect(await getTokenBalance('maker', forwarder)).to.equal('0');
    // Withdraw the Maker to Alice's wallet from owner account (zero value -- testing permissions)
    // (first send Ether for gas)
    await send.ether(floatify, alice, ether('1'));
    await ForwarderInstance.sendRawTokens(makerAddress, { from: alice });
  });

  it('allows stray Ether to be withdrawn', async () => {
    // Confirm initial balances
    const initialAliceBalance = parseInt(await getTokenBalance('eth', alice), 10);
    // Send Ether to the forwarder contract
    await send.ether(floatify, forwarder, ether('1'));
    expect(String(await getTokenBalance('eth', alice))).to.be.bignumber.equal(String(initialAliceBalance));
    expect(await getTokenBalance('eth', forwarder)).to.be.bignumber.equal(ether('1'));
    // Withdraw the Maker to Alice's wallet from Floatify account
    await ForwarderInstance.sendRawEther({ from: floatify });
    // Alice's wallet should now have Ether
    expect(await getTokenBalance('eth', alice)).to.be.bignumber.equal(
      String(initialAliceBalance + parseInt(ether('1'), 10)),
    );
    expect(await getTokenBalance('eth', forwarder)).to.be.bignumber.equal('0');
    // Withdraw the Maker to Alice's wallet from owner account (zero value -- testing permissions)
    // (first send Ether for gas)
    await send.ether(floatify, alice, ether('1'));
    await ForwarderInstance.sendRawEther({ from: alice });
  });
});
