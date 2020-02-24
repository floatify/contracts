pragma solidity 0.5.12;

/**
 * =================================================================================================
 *
 * WARNING
 *
 * This contract is a work in progress and contains cDAI functionality which
 * is a work in progress and almost certainly contains bugs. DO NOT use this
 * contract at this time.
 *
 * The following functions need to be implemented:
 *   - approveCdaiToSpendDai()
 *   - resetCdaiAllowance()
 * =================================================================================================
 */

import "@openzeppelin/contracts-ethereum-package/contracts/GSN/GSNRecipient.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "./IChai.sol";
import "./IERC20.sol";
import "./ICERC20.sol";

/**
 * @notice The Swapper contract has a variety of functions that let
 * you do a few things via meta-transactions with the Gas Station
 * Network. These things are:
 *   1. Swap: swaps Chai for another token, e.g. Chai -> cDAI
 *   2. Anti-swap: undoes a swap, e.g. cDAI -> Chai (all swaps must
 *      have an anti-swap)
 *   3. Compose: Lets you combine an anti-swap and new swap in one
 *       transaction (e.g. cDAI > Chai > RAY)
 */
contract SwapperV2 is Initializable, Ownable, GSNRecipient {

  /**
   * DEVELOPER NOTES
   *
   *   - IMPORTANT: Contracts derived from GSNRecipient should never
   *      use `msg.sender` or `msg.data`, and should use `_msgSender()`
   *      and `_msgData()` instead. Source:
   *      https://docs.openzeppelin.com/contracts/2.x/gsn#_msg_sender_and_msg_data
   *
   *   - GSNRecipientSignature was previously called GSNRecipientSignature,
   *     and is referred to by that name in the OpenZeppelin docs
   */

  mapping (address => bool) public isValidUser;
  IERC20 public daiContract;
  IChai public chaiContract;
  ICERC20 public cdaiContract;

  event DaiAddressChanged(address indexed previousAddress, address indexed newAddress);
  event ChaiAddressChanged(address indexed previousAddress, address indexed newAddress);
  event CdaiAddressChanged(address indexed previousAddress, address indexed newAddress);
  event AssertionError(string indexed message);

  /**
   * @notice Constructor, calls other constructors. Can only be called once
   * due to initializer modifier
   */
  function initialize() public initializer {
    // Call constructors of contracts we inherit from
    Ownable.initialize(_msgSender());
    GSNRecipient.initialize();

    // Set contract addresses and interfaces
    daiContract = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    chaiContract = IChai(0x06AF07097C9Eeb7fD685c692751D5C66dB49c215);
    cdaiContract = ICERC20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);

    // Approve contracts to spend this contract's Dai balance
    approveChaiToSpendDai();
    approveCdaiToSpendDai();
  }

  /**
   * @dev Defines valid IDs for tokens
   */
  modifier verifyId(uint256 _id) {
    require(
      _id == 0 ||
      _id == 1,
      "swapper/invalid-id-provided"
    );
    _;
  }

  /**
   * @notice Add address of a valid user to the mapping of valid users
   * @dev This is called by the Floatify server when a user registers
   * @param _address User address to add
   */
  function addUser(address _address) external onlyOwner {
    isValidUser[_address] = true;
  }


  // ===============================================================================================
  //                                    Token Approvals
  // ===============================================================================================

  /**
   * @notice Approve the Chai contract to spend our Dai
   */
  function approveChaiToSpendDai() private {
    bool result = daiContract.approve(address(chaiContract), uint256(-1));
    require(result, "swapper/approve-chai-to-spend-dai-failed");
  }

  /**
   * @notice Remove allowance of Chai contract to prevent it from spending Dai
   */
  function resetChaiAllowance() private {
    bool result = daiContract.approve(address(chaiContract), 0);
    require(result, "swapper/reset-chai-allowance-failed");
  }

  /**
   * @notice Approve the cDAI contract to spend our Dai
   */
  function approveCdaiToSpendDai() private {
    bool result = daiContract.approve(address(cdaiContract), uint256(-1));
    require(result, "swapper/approve-cdai-to-spend-dai-failed");
  }

  /**
   * @notice Remove allowance of cDAI contract to prevent it from spending Dai
   */
  function resetCdaiAllowance() private {
    bool result = daiContract.approve(address(cdaiContract), 0);
    require(result, "swapper/reset-cdai-allowance-failed");
  }


  // ===============================================================================================
  //                                    Updating Addresses
  // ===============================================================================================


  /**
   * @dev Allows the Dai contract address to be changed
   * @param _newAddress new address
   */
  function updateDaiAddress(address _newAddress) external onlyOwner {
    emit DaiAddressChanged(address(daiContract), _newAddress);
    daiContract = IERC20(_newAddress);
  }

  /**
   * @dev Allows the Chai contract address to be changed
   * @param _newAddress new address
   */
  function updateChaiAddress(address _newAddress) external onlyOwner {
    resetChaiAllowance();
    emit ChaiAddressChanged(address(chaiContract), _newAddress);
    chaiContract = IChai(_newAddress);
    approveChaiToSpendDai();
  }

  /**
   * @dev Allows the Chai contract address to be changed
   * @param _newAddress new address
   */
  function updateCdaiAddress(address _newAddress) external onlyOwner {
    resetCdaiAllowance();
    emit CdaiAddressChanged(address(cdaiContract), _newAddress);
    cdaiContract = ICERC20(_newAddress);
    approveCdaiToSpendDai();
  }


  // ===============================================================================================
  //                                        Swaps / Anti-swaps
  // ===============================================================================================

  /**
   * Swap Rules:
   *   - When going from any token to Dai, we must specify a Dai-denominated
   *     amount to swap
   *   - When going from Dai to any other token, we convert all Dai
   *   - When a Dai amount is required, we should be able to pass in
   *     uint256(-1) to convert all tokens
   */

  //  ---------------------------------------- Chai <> Dai -----------------------------------------
  /**
   * @notice Swap Chai for Dai. Resulting Dai balance remains in this contract
   * @param _daiAmount Amount of Dai to swap
   */
  function swapChaiForDai(uint256 _daiAmount) private {
    address _user = _msgSender();
    if (_daiAmount == uint256(-1)) {
      // Withdraw all Chai, denominated in Chai
      uint256 _chaiBalance = chaiContract.balanceOf(_user);
      chaiContract.exit(_user, _chaiBalance);
    } else {
      // Withdraw portion of Chai, demoninated in Dai
      chaiContract.draw(_user, _daiAmount);
    }
  }

  /**
   * @notice Swap Dai for Chai, and send Chai to the selected recipient
   */
  function swapDaiForChai() private {
    uint256 _daiBalance = daiContract.balanceOf(address(this));
    chaiContract.join(_msgSender(), _daiBalance);
  }

  //  ---------------------------------------- cDAI <> Dai -----------------------------------------

  /**
   * @notice Swap cDAI for Dai. Resulting Dai balance remains in this contract
   * @param _daiAmount Amount of Dai to swap
   */
  function swapCdaiForDai(uint256 _daiAmount) private {
    address _user = _msgSender();
    if (_daiAmount == uint256(-1)) {
      uint256 _cdaiBalance = cdaiContract.balanceOf(_user);
      cdaiContract.transferFrom(_user, address(this), _cdaiBalance);
      require(cdaiContract.redeem(_cdaiBalance) == 0, "swapper/max-cdai-redemption-failed");
    } else {
      require(cdaiContract.redeemUnderlying(_daiAmount) == 0, "swapper/partial-cdai-redemption-failed");
    }
  }

  /**
   * @notice Swap Dai for cDAI, and send cDAI to the owner
   */
  function swapDaiForCdai() private {
    // Swap for cDAI
    uint256 _daiBalance = daiContract.balanceOf(address(this));
    require(cdaiContract.mint(_daiBalance) == 0, "swapper/cdai-mint-failed");
    // Send cDAI to owner
    uint256 _cdaiBalance = cdaiContract.balanceOf(address(this));
    cdaiContract.transfer(_msgSender(), _cdaiBalance);
  }


  //  --------------------------------- Token => Different Token -----------------------------------


  /**
   * @notice Lets you combine two swaps in one transaction (e.g. Chai > Dai > cDAI)
   * @dev Source and destination IDs are as follows:
   *   ID     Token
   *    0     Chai
   *    1     cDAI
   * @param _srcId ID of the token to swap from
   * @param _destId ID of the token to swap to
   * @param _daiAmount amount in Dai to swap
   */
  function composeSwap(uint256 _srcId, uint256 _destId, uint256 _daiAmount) external
    verifyId(_srcId)
    verifyId(_destId)
  {
    // Prevent swaps that start and end with same token
    require(_srcId != _destId, "swapper/src-and-dest-tokens-cannot-equal");
    // Swap from source to Dai
    if      (_srcId == 0) { swapChaiForDai(_daiAmount); }
    else if (_srcId == 1) { swapCdaiForDai(_daiAmount); }
    else    { emit AssertionError("Invalid srcId got through"); }

    // Swap from Dai to dest
    if      (_destId == 0) { swapDaiForChai(); }
    else if (_destId == 1) { swapDaiForCdai(); }
    else    { emit AssertionError("Invalid destId got through"); }
  }


  //  ----------------------------------- Token => Withdraw Dai ------------------------------------

  /**
   * @notice Withdraw all Dai to the provided address
   * @param _destination Address to send the Dai to
   */
  function withdrawDai(address _destination) private {
    uint256 _daiBalance = daiContract.balanceOf(address(this));
    daiContract.transfer(_destination, _daiBalance);
  }

  // The functions below are primarily used for withdrawing a to a bank account by sending
  // Dai to a user's liquidation address (e.g. how Wyre works)

  /**
   * @notice Redeem Chai for Dai and send it to another address
   * @param _destination Address to send the Dai to
   * @param _daiAmount Amount of Dai to swap
   */
  function withdrawChaiAsDai(address _destination, uint256 _daiAmount) external {
    swapChaiForDai(_daiAmount);
    withdrawDai(_destination);
  }


  // ===============================================================================================
  //                                    Transfers
  // ===============================================================================================

  uint256 public count;
  function increaseCount() external {
    count += 1;
  }

  /**
   * @notice Send Chai to another user
   */
  function transferChai(address _recipient, uint256 _daiAmount) external {
    bool _result = chaiContract.move(_msgSender(), _recipient, _daiAmount);
    require(_result, "swapper/chai-transfer-failed");
  }

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
    // TODO improve logic
    // if (someCondition) {
    //   return _approveRelayedCall();
    // } else {
    //   _rejectRelayedCall(1); // error code 1
    // }

    // For now we accept all calls
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
}
