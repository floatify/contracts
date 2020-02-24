const { GSNDevProvider } = require('@openzeppelin/gsn-provider');
const { fundRecipient } = require('@openzeppelin/gsn-helpers');

const Web3 = require('web3'); // used to create web3gsn instance

const {
  constants,
  send,
  ether,
  expectEvent,
  expectRevert,
} = require('@openzeppelin/test-helpers');

const { expect } = require('chai');
const swapperAbi = require('../build/contracts/Swapper.json').abi; // used to create SwapperGsnInstance

const Swapper = artifacts.require('Swapper');
const Factory = artifacts.require('ForwarderFactory');

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
//                                    GSN Helper Functions / Setup
// =================================================================================================

// const web3gsn = new Web3(new GSNProvider('http://localhost:8545')); // for production
const web3gsn = new Web3(new GSNDevProvider('http://localhost:8545', {
  ownerAddress: process.env.FLOATIFY_ADDRESS,
  relayerAddress: process.env.EXCHANGE_ADDRESS,
}));

let SwapperGsnInstance; // same as SwapperInstance, but configured with a GSN provider

/**
 * @notice Create instance of contract for GSN use and ensure relay is funded
 * @param {Object} abi Contract ABI
 * @param {*} address Address of contract ABI was provided for
 * @returns {GSNContract} Instance of the contract with GSN support
 */
async function instantiateAndFundContract(abi, address) {
  await fundRecipient(web3, {
    recipient: address,
    amount: ether('1'),
    from: process.env.FLOATIFY_ADDRESS,
  });
  const GsnInstance = new web3gsn.eth.Contract(abi, address);
  return GsnInstance;
}

/**
 * @notice Permit swapper contract to spend user's Chai
 * @dev Because a new swapper instance is deployed for each test, we call this
 * function in each test where the GSN is used
 * @param {String} holder address to the user holding Chai
 * @param {String} spender address to the spending contract
 * Remaining inputs are the inputs to the permit() function
 */
async function permitSwapperToSpendChai(holder, spender, nonce, expiry, allowed, v, r, s) {
  // Make sure initial allowance is zero
  const initialAllowance = await checkTokenAllowance('chai', holder, spender);
  expect(initialAllowance).to.equal('0');

  // Call permit function to approve Swapper contract to spend user's Chai
  // (this is required for any swaps/transfers)
  await ChaiContract.methods
    .permit(holder, spender, nonce, expiry, allowed, v, r, s)
    .send({ from: process.env.FLOATIFY_ADDRESS });

  // Make sure allowance increased
  const finalAllowance = parseFloat((await checkTokenAllowance('chai', holder, spender)).toString());
  expect(finalAllowance).to.be.above(0);
}

/**
 * @notice Sleep function to wait until v, r, s are obtained in beforeEach() hook
 * @dev TODO update v,r,s steps to be more robust and eliminate the need for this function
 */
async function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}


// =================================================================================================
//                                            Swapper Tests
// =================================================================================================

// contract("Swapper", async ([_, owner, ...otherAccounts]) => {
contract('Swapper', async (accounts) => {
  // Define addresses of accounts
  //   - All user accounts start with zero balance
  //   - Exchange account has lots of Ether and all tokens
  //   - Floatify account is our server and only has Ether
  const alice = accounts[0]; // alice is the user
  const bob = accounts[1];
  const liquidation = accounts[2]; // address to send user's Dai to so it's liquidated to their bank
  const exchange = process.env.EXCHANGE_ADDRESS;
  const floatify = process.env.FLOATIFY_ADDRESS; // contract owner
  const dai = daiAddress;
  const chai = chaiAddress;
  const maker = makerAddress;
  const kyber = kyberAddress;
  const sai = saiAddress;
  const cdai = cdaiAddress;
  let swapper; // address of Swapper contract
  let forwarderFactory; // address of Swapper contract
  let SwapperInstance; // instance of Swapper contract
  let FactoryInstance; // instance of Swapper contract

  // Other setup
  let nonce;
  const expiry = 7200 + Math.floor(Date.now() / 1000); // expire 2 hours after now;
  const allowed = true;
  let r;
  let s;
  let v;

  beforeEach(async () => {
    // 0. Deploy ForwarderFactory instance
    FactoryInstance = await Factory.new({ from: floatify });
    forwarderFactory = FactoryInstance.address;
    await FactoryInstance.methods['initialize()']({ from: floatify });

    // 1. Deploy Swapper instance
    SwapperInstance = await Swapper.new({ from: floatify });
    swapper = SwapperInstance.address;
    await SwapperInstance.methods['initializeSwapper(address)'](forwarderFactory, { from: floatify });

    // 2. Use exchange account to mint Chai and send it to Alice
    await DaiContract.methods
      .approve(chai, MAX_UINT256_STRING)
      .send({ from: exchange, gas: '2000000' });
    await ChaiContract.methods.join(alice, '1000000').send({ from: exchange, gas: '2000000' });

    // 3. ERC20 Approvals
    // Using EIP712 standard for typed message signing to call permit() function
    // References:
    //   https://medium.com/metamask/eip712-is-coming-what-to-expect-and-how-to-use-it-bb92fd1a7a26
    //   https://medium.com/@yaoshiang/ethereums-ecrecover-openzeppelin-s-ecdsa-and-web3-s-sign-8ff8d16595e1
    //   https://github.com/mosendo/gasless/blob/master/app/src/utils/relayer.js
    //   https://medium.com/@yaoshiang/ethereums-ecrecover-openzeppelin-s-ecdsa-and-web3-s-sign-8ff8d16595e1
    // Contract examples:
    //   https://github.com/dapphub/ds-dach/blob/master/src/dach.sol
    //   https://github.com/mosendo/gasless/blob/master/contracts/Gasless.sol

    // Define data types
    const permit = [
      { name: 'holder', type: 'address' },
      { name: 'spender', type: 'address' },
      { name: 'nonce', type: 'uint256' },
      { name: 'expiry', type: 'uint256' },
      { name: 'allowed', type: 'bool' },
    ];

    const domain = [
      { name: 'name', type: 'string' },
      { name: 'version', type: 'string' },
      { name: 'chainId', type: 'uint256' },
      { name: 'verifyingContract', type: 'address' },
      // { name: 'salt', type: 'bytes32' }, // not used
    ];

    // Define data
    nonce = await ChaiContract.methods.nonces(alice).call();
    const permitData = {
      holder: alice,
      spender: swapper,
      nonce,
      expiry,
      allowed,
    };

    // const chainId = parseInt(await web3.eth.net.getId(), 10);
    const domainData = {
      name: 'Chai',
      version: '1',
      chainId: 1, // hardcode since we set ganache chainId to 999
      verifyingContract: chai,
      // salt: '0x', // not used
    };

    // Layout the variables
    const dataObject = {
      types: {
        EIP712Domain: domain,
        Permit: permit,
      },
      domain: domainData,
      primaryType: 'Permit',
      message: permitData,
    };
    const data = JSON.stringify(dataObject);


    // Send the data
    await web3.currentProvider.send(
      {
        method: 'eth_signTypedData',
        params: [alice, dataObject],
        from: alice,
        id: 1,
      },
      async (err, result) => {
        if (err) {
          // eslint-disable-next-line no-console
          return console.error(err);
        }
        const signature = result.result.substring(2);
        r = `0x${signature.substring(0, 64)}`;
        s = `0x${signature.substring(64, 128)}`;
        v = parseInt(signature.substring(128, 130), 16);
      },
    );
  });

  it('lets users sign to permit swapper to have an allowance', async () => {
    await sleep(500);
    await permitSwapperToSpendChai(alice, swapper, nonce, expiry, allowed, v, r, s);
  });


  // ======================================= Initialization ========================================

  it('properly initializes all account balances for testing', async () => {
    // Alice
    expect(parseFloat(await getTokenBalance('chai', alice))).to.be.above(0); // Chai balance
    expect(await getTokenBalance('eth', alice)).to.be.bignumber.equal('0'); // Ether balance
  });

  it('sets Floatify as the owner', async () => {
    const contractOwner = await SwapperInstance.owner();
    expect(contractOwner).to.equal(floatify);
  });

  it('sets the version number', async () => {
    const version = (await SwapperInstance.version()).toString();
    expect(version).to.equal('1');
  });


  // =========================================== Updates ===========================================

  // ------------------------------------------ Ownership ------------------------------------------
  it('lets the owner be changed', async () => {
    // Update owner
    await SwapperInstance.transferOwnership(alice, { from: floatify });
    expect(alice).to.equal(await SwapperInstance.owner());
  });

  it('only lets Floatify change the owner', async () => {
    await expectRevert(
      SwapperInstance.transferOwnership(alice, { from: alice }),
      'Ownable: caller is not the owner',
    );
  });

  // ---------------------------------- ForwarderFactory Contract ----------------------------------
  it('lets the address of the ForwarderFactory contract be changed by the owner', async () => {
    // For testing purposes, we change the address to the Sai address
    expect(await SwapperInstance.forwarderFactory()).to.equal(forwarderFactory); // confirm initial address
    const receipt = await SwapperInstance.updateForwarderFactoryAddress(sai, { from: floatify });
    await expectEvent(receipt, 'ForwarderFactoryAddressChanged', {
      previousAddress: forwarderFactory,
      newAddress: sai,
    });
    expect(await SwapperInstance.forwarderFactory()).to.equal(sai);
  });

  it('does not let the address of the ForwarderFactory contract be changed by anyone else', async () => {
    await expectRevert(
      SwapperInstance.updateForwarderFactoryAddress(sai, { from: alice }),
      'Ownable: caller is not the owner',
    );
  });

  it('only lets the owner (Floatify) or the ForwarderFactory contract add valid users', async () => {
    const receipt = await SwapperInstance.addUser(alice, { from: floatify });
    expect(await SwapperInstance.isValidUser(alice)).to.be.true;
    await expectEvent(receipt, 'NewUserAdded', { user: alice });

    // await SwapperInstance.addUser(bob, { from: forwarderFactory }); // can't do this -- tested in forwarderFactory.js

    await expectRevert(
      SwapperInstance.addUser(bob, { from: exchange }),
      'Swapper: caller is not owner or ForwarderFactory',
    );
  });

  // ---------------------------------------- Dai Contract -----------------------------------------
  it('lets the address of the Dai contract be changed by Floatify', async () => {
    // For testing purposes, we change the address to the Sai address
    expect(await SwapperInstance.daiContract()).to.equal(dai); // confirm initial address
    const receipt = await SwapperInstance.updateDaiAddress(sai, { from: floatify });
    await expectEvent(receipt, 'DaiAddressChanged', {
      previousAddress: dai,
      newAddress: sai,
    });
    expect(await SwapperInstance.daiContract()).to.equal(sai);
  });

  it('does not let the address of the Dai contract be changed by anyone else', async () => {
    await expectRevert(
      SwapperInstance.updateDaiAddress(sai, { from: alice }),
      'Ownable: caller is not the owner',
    );
  });


  // ---------------------------------------- Chai Contract ----------------------------------------
  it('lets the address of the Chai contract be changed by the owner', async () => {
    // For testing purposes, we change the address to the Sai address
    expect(await SwapperInstance.chaiContract()).to.equal(chai); // confirm initial address
    const receipt = await SwapperInstance.updateChaiAddress(sai, { from: floatify });
    await expectEvent(receipt, 'ChaiAddressChanged', {
      previousAddress: chai,
      newAddress: sai,
    });
    expect(await SwapperInstance.chaiContract()).to.equal(sai);
  });

  it('does not let the address of the Chai contract be changed by anyone else', async () => {
    await expectRevert(
      SwapperInstance.updateChaiAddress(sai, { from: alice }),
      'Ownable: caller is not the owner',
    );
  });


  // --------------------------------------- Kyber Contract ----------------------------------------
  it('lets the address of the Kyber contract be changed by the owner', async () => {
    // For testing purposes, we change the address to the Sai address
    expect(await SwapperInstance.knpContract()).to.equal(kyber); // confirm initial address
    const receipt = await SwapperInstance.updateKyberAddress(sai, { from: floatify });
    await expectEvent(receipt, 'KyberAddressChanged', {
      previousAddress: kyber,
      newAddress: sai,
    });
    expect(await SwapperInstance.knpContract()).to.equal(sai);
  });

  it('does not let the address of the Kyber contract be changed by anyone else', async () => {
    await expectRevert(
      SwapperInstance.updateKyberAddress(sai, { from: alice }),
      'Ownable: caller is not the owner',
    );
  });


  // ======================================== Functionality ========================================

  it('allows RelayHub deposits to be withdrawn', async () => {
    // Create instance of Swapper GSN and provide RelayHub with 1 ether for it
    SwapperGsnInstance = await instantiateAndFundContract(swapperAbi, swapper);

    // Use a random account and ensure balance is zero
    const recipient = accounts[8];
    expect(await getTokenBalance('eth', recipient)).to.be.bignumber.equal('0');
    const swapperBalance = (await SwapperInstance.getRecipientBalance()).toString();
    expect(swapperBalance).to.equal(ether('1').toString());

    // Withdraw 0.25 ether and check results
    await expectRevert(
      SwapperInstance.withdrawRelayHubFunds(ether('0.25'), recipient, { from: alice }),
      'Ownable: caller is not the owner',
    );
    await SwapperInstance.withdrawRelayHubFunds(ether('0.25'), recipient, { from: floatify });
    const swapperBalance2 = (await SwapperInstance.getRecipientBalance()).toString();
    expect(swapperBalance2).to.equal(ether('0.75').toString());
    const recipientBalance = (await getTokenBalance('eth', recipient)).toString();
    expect(recipientBalance).to.equal('250000000000000000');
  });

  it('uses the GSN to withdraw some Chai or all Chai as Dai to their bank account', async () => {
    // Add Alice as a valid Swapper user
    await SwapperInstance.addUser(alice, { from: floatify });

    // Check initial balances
    const initialChaiAlice = parseFloat(await getTokenBalance('chai', alice));
    const initialDaiLiquidation = parseFloat(await getTokenBalance('dai', liquidation));
    expect(initialChaiAlice).to.be.above(0);
    expect(initialDaiLiquidation).to.equal(0);

    // Get approval from user to spend Chai (because new swapper is deployed with each test)
    await sleep(500);
    await permitSwapperToSpendChai(alice, swapper, nonce, expiry, allowed, v, r, s);

    // Create instance of Swapper GSN and provide RelayHub with funds for it
    SwapperGsnInstance = await instantiateAndFundContract(swapperAbi, swapper);

    // Redeem some Chai
    const amountInDai = '5'; // for really small amounts, exchange rate is close enough to 1
    const receipt = await SwapperGsnInstance.methods.withdrawChaiAsDai(liquidation, amountInDai).send({ from: alice });
    const midChaiAlice = parseFloat(await getTokenBalance('chai', alice));
    const midDaiLiquidation = parseFloat(await getTokenBalance('dai', liquidation));
    expect(midChaiAlice).to.equal(initialChaiAlice - parseFloat(amountInDai)); // works since exchange rate is ~1 for small Dai
    expect(midDaiLiquidation).to.equal(parseFloat(amountInDai));
    await expectEvent(receipt, 'ChaiWithdrawnAsDai', {
      user: alice,
      daiAmount: amountInDai,
      destination: liquidation,
    });

    // Redeem all Chai
    const receipt2 = await SwapperGsnInstance.methods.withdrawChaiAsDai(liquidation, MAX_UINT256_STRING).send({ from: alice });
    const finalChaiAlice = parseFloat(await getTokenBalance('chai', alice));
    const finalDaiLiquidation = parseFloat(await getTokenBalance('dai', liquidation));
    expect(finalChaiAlice).to.equal(0);
    expect(finalDaiLiquidation).to.be.above(initialChaiAlice); // because of exchange rate
    await expectEvent(receipt2, 'ChaiWithdrawnAsDai', {
      user: alice,
      // daiAmount,
      destination: liquidation,
    });
  });

  it('uses the GSN to let some Chai or all Chai be transferred to another user', async () => {
    // Add Alice as a valid Swapper user
    await SwapperInstance.addUser(alice, { from: floatify });

    // Alice should have Chai and Bob should have none
    const initialBalanceAlice = parseFloat(await getTokenBalance('chai', alice));
    const initialBalanceBob = parseFloat(await getTokenBalance('chai', bob));
    expect(initialBalanceAlice).to.be.above(0);
    expect(initialBalanceBob).to.equal(0);

    // Get approval from user to spend Chai (because new swapper is deployed with each test)
    await sleep(500);
    await permitSwapperToSpendChai(alice, swapper, nonce, expiry, allowed, v, r, s);

    // Create instance of Swapper GSN and provide RelayHub with funds for it
    SwapperGsnInstance = await instantiateAndFundContract(swapperAbi, swapper);

    // Send some Chai from Alice to Bob
    const daiAmount = '5';
    const receipt = await SwapperGsnInstance.methods.transferChai(bob, daiAmount).send({ from: alice });
    await expectEvent(receipt, 'ChaiTransferred', {
      sender: alice,
      recipient: bob,
      daiAmount,
    });

    // Check balances again
    const midBalanceAlice = parseFloat(await getTokenBalance('chai', alice));
    const midBalanceBob = parseFloat(await getTokenBalance('chai', bob));
    expect(midBalanceAlice).to.be.equal(
      initialBalanceAlice - parseFloat(daiAmount),
    );
    expect(midBalanceBob).to.be.equal(parseFloat(daiAmount));

    // Send all Chai from Alice to Bob
    const receipt2 = await SwapperGsnInstance.methods.transferChai(bob, MAX_UINT256_STRING).send({ from: alice });
    expect(await getTokenBalance('chai', alice)).to.be.equal('0');
    expect(await getTokenBalance('chai', bob)).to.be.equal(String(initialBalanceAlice));
    await expectEvent(receipt2, 'ChaiTransferred', {
      sender: alice,
      recipient: bob,
      // daiAmount,
    });
  });

  it('only lets approved users make calls', async () => {
    // Get approval from user to spend Chai (because new swapper is deployed with each test)
    await sleep(500);
    await permitSwapperToSpendChai(alice, swapper, nonce, expiry, allowed, v, r, s);

    // Create instance of Swapper GSN and provide RelayHub with funds for it
    SwapperGsnInstance = await instantiateAndFundContract(swapperAbi, swapper);

    // Alice is not approved, so this should revert
    await expectRevert.unspecified(
      SwapperGsnInstance.methods.withdrawChaiAsDai(liquidation, '5').send({ from: alice }),
      // 'Ownable: caller is not the owner',
    );

    // Alice is now approved, so this should not revert
    await SwapperInstance.addUser(alice, { from: floatify });
    await SwapperGsnInstance.methods.withdrawChaiAsDai(liquidation, '5').send({ from: alice });
  });
});
