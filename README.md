# Floatify Contracts

- [Floatify Contracts](#floatify-contracts)
  - [Getting Started](#getting-started)
  - [Deployment](#deployment)
  - [Upgrading Contracts](#upgrading-contracts)
  - [Run Tests](#run-tests)
    - [Known Test Issues](#known-test-issues)
      - [Forwarder Factory](#forwarder-factory)
  - [Run Code Coverage](#run-code-coverage)
  - [Run Security Analysis](#run-security-analysis)
    - [MythX](#mythx)
    - [Slither](#slither)

## Getting Started

Install dependencies with `npm install`.

Next, create a file called `.env` that looks like this:

```text
export INFURA_ID=yourInfuraId
export EXCHANGE_ADDRESS=0x447a9652221f46471a2323B98B73911cda58FD8A
export FLOATIFY_ADDRESS=0xF6f9748308939416B758Ab3E656Db7ADd9928F06
export END_AUTHORIZED_USER=0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB
export MYTHX_API_KEY=yourMythxApiKey
export MNEMONIC="your 12 word seed phrase"
```

Where:

- The exchange address should be an address that has various ERC20 tokens for testing
- The Floatify address should be an address that has plenty of ETH for sending transactions
- The End authorized user address is an address authorized to begin the emergency shutdown process

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

Note that ganache-cli is installed globally and v6.9.1 is used along with
Truffle v5.0.43. Using a different version of ganache may result in additional
test failures due to bugs with the `--fork` feature of ganache-cli.

### Known Test Issues

After running tests, the below output indicates that all tests have passed and are
behaving as expected. Please see the following subsections for details.

```text
  49 passing (10m)
  1 failing

  1) Contract: ForwarderFactory
       deploys and initialize a proxy forwarder and marks the user as valid in Swapper:

      AssertionError: expected '0' to equal '1'
      + expected - actual

      -0
      +1
```

#### Forwarder Factory

In `forwarderFactory.js`, we run the `it('deploys and initialize a proxy forwarder')` test, but
currently this test is expected to fail. The test requires mainnet contracts, but initialization of
the deployed proxy contract fails when testing with the ganache-cli `--fork` feature. See
[this issue](https://github.com/trufflesuite/ganache-core/issues/526)
for more details. Note that this test does pass in production even though it fails here.

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
