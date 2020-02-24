module.exports = {
  skipFiles: ['contracts/SwapperV2.sol'],
  providerOptions: {
    network_id: 999,
    default_balance_ether: 0,
    fork: `https://mainnet.infura.io/v3/${process.env.INFURA_ID}`,
    unlocked_accounts: [process.env.EXCHANGE_ADDRESS, process.env.FLOATIFY_ADDRESS],
  }
};