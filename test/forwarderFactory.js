/**
 * DEVELOPER NOTES
 * To run these tests, follow the steps below:
 *   1. Start ganache-cli with `ganache-cli -d`
 *   2. Comment out the following section of Fowarder.sol
 *        // Set contract addresses and interfaces
 *        daiContract = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
 *        chaiContract = IChai(0x06AF07097C9Eeb7fD685c692751D5C66dB49c215);
 *        knpContract = IKyberNetworkProxy(0x818E6FECD516Ecc3849DAf6845e3EC868087B755);
 *
 *        // Approve the Chai contract to spend this contract's DAI balance
 *        approveChaiToSpendDai();
 *   3. Run tests with `npm run test`
 *   4. Uncomment out the above section
 *   5. See here for info on why: https://github.com/trufflesuite/ganache-core/issues/526
 *
 */

const {
  constants,
  send,
  ether,
  expectEvent,
  expectRevert,
} = require('@openzeppelin/test-helpers');

const { expect } = require('chai');

const Forwarder = artifacts.require('Forwarder');
const Factory = artifacts.require('ForwarderFactory');
const Swapper = artifacts.require('Swapper');

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


// contract("Factory", async ([_, owner, ...otherAccounts]) => {
contract('ForwarderFactory', async (accounts) => {
  // Define addresses of accounts
  //   - All user accounts start with zero balance
  //   - Exchange account has lots of Ether and all tokens
  //   - Floatify account is our server and only has Ether
  const alice = accounts[0]; // alice is the owner
  const bob = accounts[1];
  const charlie = accounts[2];
  const exchange = process.env.EXCHANGE_ADDRESS;
  const floatify = process.env.FLOATIFY_ADDRESS;
  const dai = daiAddress;
  const chai = chaiAddress;
  const maker = makerAddress;
  const kyber = kyberAddress;
  const sai = saiAddress;
  let factory; // address of ForwarderFactory contract
  let swapper; // address of Swapper contract

  // Other setup
  let ForwarderInstance;
  let FactoryInstance;
  let SwapperInstance;

  beforeEach(async () => {
    // Deploy and initialize factory
    FactoryInstance = await Factory.new({ from: floatify });
    factory = FactoryInstance.address;
    await FactoryInstance.methods['initialize()']({ from: floatify });

    // Deploy and initialize forwarder logic template
    ForwarderInstance = await Forwarder.new({ from: floatify });
    await ForwarderInstance.methods['initialize(address,address)'](
      floatify,
      floatify,
      { from: floatify },
    );

    // Deploy and initialize Swapper
    SwapperInstance = await Swapper.new({ from: floatify });
    swapper = SwapperInstance.address;
    await SwapperInstance.methods['initializeSwapper(address)'](factory, { from: floatify });
  });


  // ================================= Initialization and Updates ==================================

  it('should have proper owner', async () => {
    const contractOwner = await FactoryInstance.owner();
    expect(contractOwner).to.equal(floatify);
  });

  it('properly initializes an empty list of users', async () => {
    const users = await FactoryInstance.getUsers();
    expect(users).to.be.an('array').that.is.empty;
  });

  it('sets the version number', async () => {
    const version = (await FactoryInstance.version()).toString();
    expect(version).to.equal('1');
  });

  // ------------------------------------------ Ownership ------------------------------------------
  it('lets the owner be changed', async () => {
    // Update owner
    await FactoryInstance.transferOwnership(bob, { from: floatify });
    expect(bob).to.equal(await FactoryInstance.owner());
  });

  it('only let the user change the owner', async () => {
    await expectRevert(
      FactoryInstance.transferOwnership(bob, { from: alice }),
      'Ownable: caller is not the owner',
    );
  });

  // ======================================== Functionality ========================================
  it('deploys and initialize a proxy forwarder and marks the user as valid in Swapper', async () => {
    // Create proxy forwarder and ensure user (alice) is added as valid user to Swapper
    expect(await SwapperInstance.isValidUser(alice)).to.be.false;
    const { logs } = await FactoryInstance.createForwarder(
      ForwarderInstance.address,
      alice,
      swapper,
      { from: floatify },
    );
    expect(await SwapperInstance.isValidUser(alice)).to.be.true;

    // Confirm events are emitted
    const userAddress = await FactoryInstance.users(0);
    const forwarderAddress = await FactoryInstance.getForwarder(userAddress);
    await expectEvent.inLogs(logs, 'ProxyCreated', { proxy: forwarderAddress });
    await expectEvent.inLogs(logs, 'ForwarderCreated', { user: alice, forwarder: forwarderAddress });

    // Make sure it really is a clone
    const isClone = await FactoryInstance.isClone(ForwarderInstance.address, forwarderAddress);
    expect(isClone).to.be.true;

    // Get instance of it and check parameters
    const forwarder = await Forwarder.at(forwarderAddress);
    expect(await forwarder.version()).to.be.bignumber.equal('1');
    expect(await forwarder.owner()).to.equal(alice);
  });

  it('only lets the owner create a new forwarder', async () => {
    await expectRevert(
      FactoryInstance.createForwarder(ForwarderInstance.address, alice, swapper, { from: alice }),
      'Ownable: caller is not the owner',
    );
  });

  it('returns an array of all user addresses', async () => {
    await FactoryInstance.createForwarder(ForwarderInstance.address, alice, swapper, { from: floatify });
    await FactoryInstance.createForwarder(ForwarderInstance.address, bob, swapper, { from: floatify });
    await FactoryInstance.createForwarder(ForwarderInstance.address, charlie, swapper, { from: floatify });
    const users = await FactoryInstance.getUsers();
    // see here for why we need to use deep.equal: https://github.com/chaijs/deep-eql
    expect(users).to.deep.equal([alice, bob, charlie]);
  });
});
