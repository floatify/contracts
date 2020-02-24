# Floatify Contracts

- [Floatify Contracts](#floatify-contracts)
  - [Getting Started](#getting-started)
  - [Deployment](#deployment)
  - [Upgrading Contracts](#upgrading-contracts)
  - [Run Tests](#run-tests)
  - [Run Code Coverage](#run-code-coverage)
  - [Run Security Analysis](#run-security-analysis)
    - [MythX](#mythx)
    - [Slither](#slither)
  - [Development Notes](#development-notes)
    - [Package Versions](#package-versions)
    - [Know Test Issues](#know-test-issues)
      - [Summary](#summary)
      - [Forwarder Factory](#forwarder-factory)
      - [Forwarder](#forwarder)

## Getting Started

*Repository was originally initialized based on the
OpenZeppelin Gas Station Network (GSN) [starter kit](https://github.com/OpenZeppelin/starter-kit-gsn).*

First, install dependencies with `npm install`.

Next, create a file called `.env` that looks like this:

```text
export INFURA_ID=yourInfuraId
export EXCHANGE_ADDRESS=0x447a9652221f46471a2323B98B73911cda58FD8A
export FLOATIFY_ADDRESS=0xF6f9748308939416B758Ab3E656Db7ADd9928F06
export MYTHX_API_KEY=yourMythxApiKey
export MNEMONIC="your 12 word seed phrase"
```

Where:

- The exchange address should be an address that has various ERC20 tokens for testing
- The Floatify address should be an address that has plenty of ETH for sending transactions

The addresses shown above for each should be suitable. *The exchange address and floatify address
are environment variables (as opposed to simply being defined within the JS files) so they
can be accessed from the command line when deploying/testing with the OpenZeppelin CLI.*

**NOTE: Make sure you do not commit this file to a repository!**

## Deployment

Deployment steps below are based on the workflow from
[this guide](https://forum.openzeppelin.com/t/guide-full-start-to-finish-openzeppelin-workflow-for-cli-deployment-and-upgrades/2191)
on the OpenZeppelin forums.

*Note: When starting ganache-cli as a fork of the mainnet, make sure to manually
set the network ID with the `-i` flag. Otherwise, the OpenZeppelin cli
will overwrite the `.openzeppelin/mainnet.json` file since the local ganache
blockchain shares a network ID with the mainnet. See
[this issue](https://github.com/OpenZeppelin/openzeppelin-sdk/issues/1306) for details.*

```bash
# Compile contracts with proper solc version
npm run compile

# If deploying on a local development chain, start ganache in its own terminal window
npm run test-setup

# Make sure .env file is configured as shown above
source .env

# Create a session and select account to send transactions from
npx oz session --network main
# OR
npx oz session -n development -f $FLOATIFY_ADDRESS  --expires 7200 --timeout 600

# Confirm the proper account would get used for deployment, which
npx oz accounts

# Deploy ForwarderFactory contract, call initialize(), and verify
npx oz create ForwarderFactory
npx oz verify

# Deploy Forwarder contract logic, call initialize(address _recipient, address _floatify), and verify
# Values for _recipient and _floatify should be both be the cold storage floatify account
npx oz create Forwarder
npx oz verify

# Deploy Swapper contract, call initializeSwapper(address _forwarderFactory), and verify
npx oz create Swapper
npx oz verify

# Fund Swapper with 2 Ether for GSN
npx oz-gsn fund-recipient

# Change administrator to cold storage address
npx oz set-admin
```

## Upgrading Contracts

```bash
# Compile contracts with proper solc version
npm run compile

# Change admin to a standard EOA
npx oz set-admin

# Deploy upgrades using one of the two approaches below
npx oz upgrade # to upgrade a single contract
npx oz upgrade --all # to upgrade all contracts

# Call any new initialization functions here

# Change admin back to hardware wallet
npx oz set-admin
```

## Run Tests

1. Run `npm run test-setup` in a terminal window to start ganache-cli with the proper settings.
2. In a new terminal window, run `npm run test` to run tests.

## Run Code Coverage

A code coverage report can be generated with
[solidity-coverage](https://github.com/sc-forks/solidity-coverage) by running `npm run coverage`.
Please be patient as this can take quite a while.

## Run Security Analysis

### MythX

MythX will run in trial mode by default, which you may use. Alternatively, follow the
steps [here](https://docs.mythx.io/en/latest/tools/truffle/index.html#accounts-and-access)
for instructions on how to set up a full account.

Afterwards, analyze contracts using `source .env && truffle run verify`.

### Slither

Initial setup:

1. Create a Python virtual environment with `python3 -m venv venv`
2. Activate it with `source ./venv/bin/activate`
3. Install Slither with `pip3 install slither-analyzer`

Then run Slither on the project using `slither .`.

## Development Notes

### Package Versions

Truffle version must not be later than 5.0.43. See the [Skipped Tests](#skipped-tests)
section for details.

### Know Test Issues

#### Summary

After running tests, the below output indicates that all tests have passed and are
behaving as expected. Please see the following subsections for details.

```text
  50 passing (9m)
  1 pending
  1 failing

  1) Contract: ForwarderFactory
       deploys and initialize a proxy forwarder and marks the user as valid in Swapper:

      AssertionError: expected '0' to equal '1'
      + expected - actual

      -0
      +1

      at Context.it (test/forwarderFactory.js:147:55)
      at process._tickCallback (internal/process/next_tick.js:68:7)
```

#### Forwarder Factory

In `forwarderFactory.js`, we run the `it('deploys and initialize a proxy forwarder')` test, but
currentlythis test is expected to fail. The test requires mainnet contracts, but initialization of
the deployed proxy contract fails when testing with the ganache-cli `--fork` feature. See
[this issue](https://github.com/trufflesuite/ganache-core/issues/526)
for more details. Note that this test does pass in production even though it fails here.

#### Forwarder

In `forwarder.js`, we skip the `it('converts any received tokens to Chai and sends them to the owner)`
test, as it fails with the below error. Note that this test does pass in production even
though it fails here. Additionally, note that the version of this test that converts
Ether to Chai&mdash;`it('converts received Ether to Chai and sends it to the owner'`&mdash;only
passes if Truffle 5.0.43 is used, but fails with later versions. This fix was found in
[this ganache-cli issue](https://github.com/trufflesuite/ganache-cli/issues/702).

```text
Could not connect to your Ethereum client with the following parameters:
    - host       > 127.0.0.1
    - port       > 8545
    - network_id > 1
Please check that your Ethereum client:
    - is running
    - is accepting RPC connections (i.e., "--rpc" option is used in geth)
    - is accessible over the network
    - is properly configured in your Truffle configuration file (truffle-config.js)

  Error:     at PromiEvent (node_modules/truffle/build/webpack:/packages/contract/lib/promievent.js:9:1)
      at TruffleContract.convertAndSendEth (node_modules/truffle/build/webpack:/packages/contract/lib/execute.js:169:1)
      at Context.it (test/forwarder.js:302:29)
      at process._tickCallback (internal/process/next_tick.js:68:7)
```
