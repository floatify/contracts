const { balance } = require('@openzeppelin/test-helpers');

// const FloatifyAccount = artifacts.require('FloatifyAccount');

// Configure details for interacting with Dai
const daiAbi = require('./externalAbis/DAI.json').abi;
const cdaiAbi = require('./externalAbis/cDAI.json').abi;
const chaiAbi = require('./externalAbis/chai.json').abi;
const makerAbi = require('./externalAbis/maker.json').abi;
const usdcAbi = require('./externalAbis/usdc.json').abi;
const saiAbi = require('./externalAbis/sai.json').abi;
const potAbi = require('./externalAbis/pot.json').abi;
const endAbi = require('./externalAbis/end.json').abi;

const daiAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
const cdaiAddress = '0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643';
const chaiAddress = '0x06AF07097C9Eeb7fD685c692751D5C66dB49c215';
const makerAddress = '0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2';
const usdcAddress = '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48';
const kyberAddress = '0x818E6FECD516Ecc3849DAf6845e3EC868087B755'; // Kyber Network Proxy address
const saiAddress = '0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359';
const potAddress = '0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7';
const endAddress = '0xaB14d3CE3F733CACB76eC2AbE7d2fcb00c99F3d5';
// const exchangeAddress = process.env.EXCHANGE_ADDRESS; // random address to get DAI from

// Instantiate contract instances
const DaiContract = new web3.eth.Contract(daiAbi, daiAddress);
const CdaiContract = new web3.eth.Contract(cdaiAbi, cdaiAddress);
const ChaiContract = new web3.eth.Contract(chaiAbi, chaiAddress);
const MakerContract = new web3.eth.Contract(makerAbi, makerAddress);
const UsdcContract = new web3.eth.Contract(usdcAbi, usdcAddress);
const SaiContract = new web3.eth.Contract(saiAbi, saiAddress);
const PotContract = new web3.eth.Contract(potAbi, potAddress);
const EndContract = new web3.eth.Contract(endAbi, endAddress);

// Define variables we need. Values are assigned in the global beforeEach() hook
// let FloatifyInstance; // instance of FloatifyAccount contract
// let floatifyAddress; // address of FloatifyInstance

// Functions =======================================================================================

/**
 * Get the token contract instance for the specified ERC20 token
 * @param {string} token token name
 */
const getTokenContract = function getTokenContract(token) {
  switch (token.toLowerCase()) {
    case 'dai':
      return DaiContract;
    case 'cdai':
      return CdaiContract;
    case 'chai':
      return ChaiContract;
    case 'maker':
      return MakerContract;
    default:
      throw Error('Invalid token specified');
  }
};

/**
 * Check allowance for a given scenario. For example, the following
 * two calls are equivalent
 *   const allowance = await checkTokenAllowance('dai', floatify, cdai);
 *   const cdaiAllowance = await DaiContract.methods.allowance(floatifyAddress, cdaiAddress).call();
 * @param {string} token token name to check allowance for
 * @param {string} holder address of the account holding the tokens
 * @param {string} spender address of the account spending tokens for holder
 */
const checkTokenAllowance = async function checkTokenAllowance(token, holder, spender) {
  const TokenContract = getTokenContract(token);
  const allowance = await TokenContract.methods.allowance(holder, spender).call();
  return allowance;
};

/**
 *
 * @param {String} token name of token to send
 * @param {String} from address to send token from
 * @param {String} to  address to send token to
 * @param {String, BigNumber} amount amount to send, in EVM units
 */
const sendToken = async function sendToken(token, from, to, amount) {
  const TokenContract = getTokenContract(token);
  const result = TokenContract.methods.transfer(to, amount).send({ from });
  return result;
};

/**
 * Get DAI or cDAI balance of a given contract.
 * @param {token} string 'DAI' or 'cDAI'
 * @param {string} address account address to get balance of
 * @returns {number} human-readable balance
 */
const getTokenBalance = async function getTokenBalance(token, address) {
  if (token.slice(0, 3) === 'eth') {
    return balance.current(address);
  }
  const TokenContract = getTokenContract(token);
  const tokenBalance = await TokenContract.methods.balanceOf(address).call();
  return tokenBalance;
};


/**
 * Mint DAI from msg.sender and receive Chai
 * @param {String} amount amount of DAI to send
 * @param {String} dest address that will receive the Chai
 * @param {String} sendFrom address of account that should send transaction
 */
const mintChai = async function mintChai(amount, dest, sendFrom) {
  return ChaiContract.methods.join(dest, amount).send({ from: sendFrom });
};

/**
 * Redeem Chai for DAI, based on allowance of msg.sender to move funds for `source`
 * @param {String} amount underlying amount of DAI to redeem
 * @param {String} source address holding the Chai to be redeemed
 * @param {String} sendFrom address of account that should send transaction
 */
const redeemChai = async function redeemDai(amount, source, sendFrom) {
  // draw() lets you specify the amount in DAI, whereas exit() needs the amount in Chai
  return ChaiContract.methods.draw(source, amount).send({ from: sendFrom });
};

module.exports = {
  // Contracts
  DaiContract,
  CdaiContract,
  ChaiContract,
  SaiContract,
  UsdcContract,
  PotContract,
  EndContract,
  // Addresses
  daiAddress,
  cdaiAddress,
  chaiAddress,
  makerAddress,
  usdcAddress,
  kyberAddress,
  potAddress,
  saiAddress,
  // Functions
  sendToken,
  getTokenBalance,
  checkTokenAllowance,
  mintChai,
  redeemChai,
};
