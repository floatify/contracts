pragma solidity 0.5.12;

import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/GSN/GSNRecipient.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "./IERC20.sol";
import "./IChai.sol";

/**
 * @notice In the event that MakerDAO triggers an Emergency Shutdown (also
 * known as a Global Settlement) this contract can be used to simplify
 * the process of cashing out your Chai or Dai. The Emergency Shutdown (ES)
 * process lets Dai holders redeem 1 DAI for $1 worth of ETH. This contract
 * aims to remove exposure to the volatility of Ether by enabling users
 * to redeem the DAI for ETH/BAT, then convert the ETH/BAT to USDC. The USDC
 * will be sent to the address that triggered the transaction.
 *
 * @dev WARNING: DO NOT CHANGE THE ORDER OF INHERITANCE
 * Because this is an upgradable contract, doing so changes the order of the
 * state variables in the parent contracts, which can lead to the storage
 * values getting mixed up
 *
 * @dev IMPORTANT: Contracts derived from GSNRecipient should never use
 * msg.sender or msg.data, and should use _msgSender() and _msgData() instead.
 * Source: https://docs.openzeppelin.com/contracts/2.x/gsn#_msg_sender_and_msg_data
 */


contract IUniswapFactory {
  function getExchange(address token) external view returns (address exchange);
}

contract IUniswapExchange {
  function ethToTokenSwapInput(uint256 min_tokens, uint256 deadline) external payable returns (uint256  tokens_bought);
  function tokenToTokenSwapInput(uint256 tokens_sold, uint256 min_tokens_bought, uint256 min_eth_bought, uint256 deadline, address token_addr) external returns (uint256  tokens_bought);
}

interface IEnd {
  // Maker Emergency Shutdown interface
  // https://etherscan.io/address/0xaB14d3CE3F733CACB76eC2AbE7d2fcb00c99F3d5#code
  function pack(uint256 wad) external;
  function cash(bytes32 ilk, uint wad) external;
}

contract ESRedemption is Initializable, Ownable, GSNRecipient {
  // Ownable is only used to restrict who can withdraw funds to RelayHub
  using SafeMath for uint256;

  IERC20 public batContract;
  IERC20 public daiContract;
  IERC20 public usdcContract;
  IChai public chaiContract;
  IEnd public endContract;

  IUniswapFactory public uniswapFactoryContract;
  IUniswapExchange public uniswapUsdc;
  IUniswapExchange public uniswapBat;

  /**
   * @notice Constructor, can only be called once due to initializer modifier
   */
  function initializeEsRedemption() public initializer {
    // Call constructors of contracts we inherit from
    Ownable.initialize(_msgSender());
    GSNRecipient.initialize();

    // Set contract definitions
    batContract = IERC20(0x0D8775F648430679A709E98d2b0Cb6250d2887EF);
    daiContract = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    usdcContract = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    chaiContract = IChai(0x06AF07097C9Eeb7fD685c692751D5C66dB49c215);
    endContract = IEnd(0xaB14d3CE3F733CACB76eC2AbE7d2fcb00c99F3d5);

    uniswapFactoryContract = IUniswapFactory(0xc0a47dFe034B400B47bDaD5FecDa2621de6c4d95);
    uniswapUsdc = IUniswapExchange(uniswapFactoryContract.getExchange(address(usdcContract)));
    uniswapBat = IUniswapExchange(uniswapFactoryContract.getExchange(address(batContract)));

    // Approve End to spend our dai (so we can redeem it for collateral)
    daiContract.approve(address(endContract), uint256(-1));

    // Approve Uniswap BAT contract to spend our BAT (so we can swap it for USDC)
    batContract.approve(address(uniswapBat), uint256(-1));
  }


  // ====================================== PRIMARY FUNCTIONS ======================================

  /**
   * @notice For the provided token address, transfer all tokens held
   * by this contract to the caller
   */
  function sendUsdcToCaller() private {
    uint256 _balance = usdcContract.balanceOf(address(this));
    require(usdcContract.transfer(_msgSender(), _balance), "ESRedemption: Token transfer failed");
  }

  /**
   * @notice Swap all Ether held by this contract to USDC
   */
  function swapEtherForUsdc() private {
    uint256 _ethBalance = address(this).balance;
    // We don't worry about the exchange rate since this is an emergency
    // and market conditions may be unpredictable
    uint256 _minTokens = 1;
    // Trade is valid for one week (allows tx time to process in clogged market)
    uint256 _deadline = now + 1 weeks;
    // Execute swap
    uniswapUsdc.ethToTokenSwapInput.value(_ethBalance)(_minTokens, _deadline);
  }

  /**
   * @notice Swap all BAT held by this contract to _dstToken
   */
  function swapBatForUsdc() private {
    // Get contract's BAT balance
    IERC20 _bat = IERC20(0x0D8775F648430679A709E98d2b0Cb6250d2887EF);
    uint256 _batBalance = _bat.balanceOf(address(this));
    // We don't worry about the exchange rate since this is an emergency
    // and market conditions may be unpredictable
    uint256 _minTokensBought = 1;
    uint256 _minEthBought = 1;
    // Trade is valid for one week (allows tx time to process in clogged market)
    uint256 _deadline = now + 1 weeks;
    // Execute swap
    uniswapBat.tokenToTokenSwapInput(_batBalance, _minTokensBought, _minEthBought, _deadline, address(usdcContract));
  }

  /**
   * @notice Exchanges all Dai held by this contract for the underlying collateral
   */
  function redeemDaiForCollateral(uint256 _daiAmount) private {
    // After this function the contract will have some ETH, some BAT (and some SAI?)
    // Pack Dai into a bag in preparation to cash out
    endContract.pack(_daiAmount);

    // Only two collateral types in MCD that we need to worry about
    // TODO do we need to call this with "SAI" also?
    endContract.cash("ETH-A", _daiAmount);
    endContract.cash("BAT-A", _daiAmount);
    endContract.cash("USDC-A", _daiAmount);
    // endContract.cash("SAI", _daiAmount); // TODO is this needed?

    // For reference the actual bytes32 Ilk values for ETH and BAT are below
    // ETH-A: 0x4554482d41000000000000000000000000000000000000000000000000000000
    // BAT-A: 0x4241542d41000000000000000000000000000000000000000000000000000000
  }

  /**
   * @notice Swap Chai for Dai. Resulting Dai balance remains in this contract
   * @dev Amount denominated in Dai, use MAX_UINT256 to swap everything
   */
  function swapChaiForDai(uint256 _daiAmount) private {
    address _user = _msgSender();
    if (_daiAmount == uint256(-1)) {
      // Redeem all Chai, denominated in Chai
      uint256 _chaiBalance = chaiContract.balanceOf(_user);
      chaiContract.exit(_user, _chaiBalance);
    } else {
      // Redeem portion of Chai, demoninated in Dai
      chaiContract.draw(_user, _daiAmount);
    }
  }

  /**
   * @notice Redeems all Dai for specified token and sends to the caller
   * @dev Pass in MAX_UINT256 to redeem all Dai
   */
  function redeemDaiForUsdc(uint256 _daiAmount) public {
    redeemDaiForCollateral(_daiAmount);
    swapEtherForUsdc();
    swapBatForUsdc();
    sendUsdcToCaller();
  }

  /**
   * @notice Redeems all Chai for specified token and sends to the caller
   * @dev Pass in MAX_UINT256 to redeem all Chai
   */
  function redeemChaiForUsdc(uint256 _daiAmount) external {
    swapChaiForDai(_daiAmount);
    redeemDaiForUsdc(_daiAmount);
  }

  /**
   * @notice Ensure we can receive ETH
   */
  function() external payable { }


  // ===============================================================================================
  //                               Gas Station Network Functions
  // ===============================================================================================

  /**
   * @dev Determine if we should receive a relayed call.
   * There are multiple ways to make this work, including:
   *   - having a whitelist of trusted users
   *   - only accepting calls to an onboarding function
   *   - charging users in tokens (possibly issued by you)
   *   - delegating the acceptance logic off-chain
   * All relayed call requests can be rejected at no cost to the recipient.
   *
   * In this function, we return a number indicating whether we:
   *   - Accept the call: 0, signalled by the call to `_approveRelayedCall()`
   *   - Reject the call: Any other number, signalled by the call to `_rejectRelayedCall(uint256)`
   *
   * We can also return some arbitrary data that will get passed along
   * to the pre and post functions as an execution context.
   *
   * Source: https://docs.openzeppelin.com/contracts/2.x/gsn#_acceptrelayedcall
   */
  function acceptRelayedCall(
    address relay,
    address from,
    bytes calldata encodedFunction,
    uint256 transactionFee,
    uint256 gasPrice,
    uint256 gasLimit,
    uint256 nonce,
    bytes calldata approvalData,
    uint256 maxPossibleCharge
  ) external view returns (uint256, bytes memory) {
    // accept all requests
    return _approveRelayedCall();
  }

  /**
   * @dev After call is accepted, but before it's executed, we can use
   * this function to charge the user for their call, perform some
   * bookeeping, etc.
   *
   * This function will inform us of the maximum cost the call may
   * have, and can be used to charge the user in advance. This is
   * useful if the user may spend their allowance as part of the call,
   * so we can lock some funds here.
   *
   * Source: https://docs.openzeppelin.com/contracts/2.x/gsn#_pre_and_postrelayedcall
   */
  function _preRelayedCall(bytes memory context) internal returns (bytes32) {
  }

  /**
   * @dev After call is accepted and executed, we can use this function
   * to charge the user for their call, perform some bookeeping, etc.
   *
   * This function will give us an accurate estimate of the transaction
   * cost, making it a natural place to charge users. It will also let
   * us know if the relayed call reverted or not. This allows us, for
   * instance, to not charge users for reverted calls - but remember
   * that we will be charged by the relayer nonetheless.
   *
   * Source: https://docs.openzeppelin.com/contracts/2.x/gsn#_pre_and_postrelayedcall
   */
  function _postRelayedCall(bytes memory context, bool, uint256 actualCharge, bytes32) internal {
  }

  function setRelayHubAddress() public {
    if(getHubAddr() == address(0)) {
      _upgradeRelayHub(0xD216153c06E857cD7f72665E0aF1d7D82172F494);
    }
  }

  function getRecipientBalance() public view returns (uint) {
    return IRelayHub(getHubAddr()).balanceOf(address(this));
  }

  /**
   * @dev Withdraw funds from RelayHub
   * @param _amount Amount of Ether to withdraw
   * @param _recipient Address to send the Ether to
   */
  function withdrawRelayHubFunds(uint256 _amount, address payable _recipient) external onlyOwner {
    IRelayHub(getHubAddr()).withdraw(_amount, _recipient);
  }
}
