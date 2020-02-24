pragma solidity 0.5.12;

import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/GSN/GSNRecipient.sol";
import "./IERC20.sol";
import "./IChai.sol";
import "./IKyberNetworkProxy.sol";

/**
 * @notice The Swapper contract has a variety of functions that let
 * you do a few things via meta-transactions with the Gas Station
 * Network. These things are:
 *   1. Swap: swaps Chai for another token, e.g. Chai -> Ether
 *   2. Anti-swap: undoes a swap, e.g. Ether -> Chai (all swaps must
 *      have an anti-swap)
 *   3. Compose: Lets you combine an anti-swap and new swap in one
 *       transaction (e.g. Ether > Chai > PoolTogether)
 *
 * @dev WARNING: DO NOT CHANGE THE ORDER OF INHERITANCE
 * Because this is an upgradable contract, doing so changes the order of the
 * state variables in the parent contracts, which can lead to the storage
 * values getting mixed up

 * @dev IMPORTANT: Contracts derived from GSNRecipient should never use
 * msg.sender or msg.data, and should use _msgSender() and _msgData() instead.
 * Source: https://docs.openzeppelin.com/contracts/2.x/gsn#_msg_sender_and_msg_data
 */
contract Swapper is Initializable, Ownable, GSNRecipient {

  uint256 public version;

  mapping (address => bool) public isValidUser;
  address public forwarderFactory;

  IERC20 public daiContract;
  IChai public chaiContract;
  IKyberNetworkProxy public knpContract;

  IERC20 constant public ETH_TOKEN_ADDRESS = IERC20(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
  uint constant RAY = 10 ** 27;

  /**
   * @dev Emitted when Chai is withdrawn as Dai
   */
  event ChaiWithdrawnAsDai(address indexed user, uint256 indexed daiAmount, address indexed destination);

  /**
   * @dev Emitted when a new user is added
   */
  event NewUserAdded(address indexed user);

  /**
   * @dev Emitted when Chai is transferred
   */
  event ChaiTransferred(address indexed sender, address indexed recipient, uint256 indexed daiAmount);

  /**
   * @dev Emitted when saved addresses are updated
   */
  event ForwarderFactoryAddressChanged(address indexed previousAddress, address indexed newAddress);
  event DaiAddressChanged(address indexed previousAddress, address indexed newAddress);
  event ChaiAddressChanged(address indexed previousAddress, address indexed newAddress);
  event PotAddressChanged(address indexed previousAddress, address indexed newAddress);
  event KyberAddressChanged(address indexed previousAddress, address indexed newAddress);

  /**
   * @notice Constructor, calls other constructors. Can only be called once
   * due to initializer modifier
   * @dev Called initializeSwapper instead of initialize to avoid having the
   * same function signature as Owanble's initializer
   */
  function initializeSwapper(address _forwarderFactory) public initializer {
    // Call constructors of contracts we inherit from
    Ownable.initialize(_msgSender());
    GSNRecipient.initialize();

    // Set contract variables
    version = 1;
    forwarderFactory = _forwarderFactory;
    daiContract = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    chaiContract = IChai(0x06AF07097C9Eeb7fD685c692751D5C66dB49c215);
    knpContract = IKyberNetworkProxy(0x818E6FECD516Ecc3849DAf6845e3EC868087B755);

    // Approve contracts to spend this contract's Dai balance
    approveChaiToSpendDai();
  }

  /**
   * @notice Add address of a valid user to the mapping of valid users
   * @dev This is called by the ForwarderFactory contract when a user registers
   * @param _address User address to add
   */
  function addUser(address _address) external {
    require(
      _msgSender() == owner() || _msgSender() == forwarderFactory,
      "Swapper: caller is not owner or ForwarderFactory"
    );
    isValidUser[_address] = true;
    emit NewUserAdded(_address);
  }


  // ===============================================================================================
  //                                        Math
  // ===============================================================================================

  // These functions are taken from the Chai contract
  // https://github.com/dapphub/chai/blob/master/src/chai.sol#L62
  function add(uint x, uint y) internal pure returns (uint z) {
    require((z = x + y) >= x);
  }
  function sub(uint x, uint y) internal pure returns (uint z) {
    require((z = x - y) <= x);
  }
  function mul(uint x, uint y) internal pure returns (uint z) {
    require(y == 0 || (z = x * y) / y == x);
  }
  function rdivup(uint x, uint y) internal pure returns (uint z) {
    // always rounds up
    z = add(mul(x, RAY), sub(y, 1)) / y;
  }

  // ===============================================================================================
  //                                    Token Approvals
  // ===============================================================================================

  /**
   * @notice Approve the Chai contract to spend our Dai
   */
  function approveChaiToSpendDai() private {
    bool result = daiContract.approve(address(chaiContract), uint256(-1));
    require(result, "Swapper: failed to approve Chai contract to spend Dai");
  }

  /**
   * @notice Remove allowance of Chai contract to prevent it from spending Dai
   */
  function resetChaiAllowance() private {
    bool result = daiContract.approve(address(chaiContract), 0);
    require(result, "Swapper: failed to remove allowance of Chai contract to spend Dai");
  }


  // ===============================================================================================
  //                                    Updating Addresses
  // ===============================================================================================


  /**
   * @dev Allows the ForwarderFactory contract address to be changed
   * @param _newAddress new address
   */
  function updateForwarderFactoryAddress(address _newAddress) external onlyOwner {
    emit ForwarderFactoryAddressChanged(forwarderFactory, _newAddress);
    forwarderFactory = _newAddress;
  }

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
   * @dev Allows the Kyber Proxy contract address to be changed
   * @param _newAddress new address
   */
  function updateKyberAddress(address _newAddress) external onlyOwner {
    emit KyberAddressChanged(address(knpContract), _newAddress);
    knpContract = IKyberNetworkProxy(_newAddress);
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


  //  ----------------------------------- Token => Withdraw Dai ------------------------------------

  /**
   * @notice Withdraw all Dai to the provided address
   * @param _destination Address to send the Dai to
   */
  function withdrawDai(address _destination) private {
    uint256 _daiBalance = daiContract.balanceOf(address(this));
    emit ChaiWithdrawnAsDai(_msgSender(), _daiBalance, _destination);
    daiContract.transfer(_destination, _daiBalance);
  }


  /**
   * @notice Redeem Chai for Dai and send it to another address. This is primarily used
   * for withdrawing funds a to a bank account by sending Dai to a user's liquidation
   * address (this is how Wyre works)
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

  /**
   * @notice Send Chai to another user
   */
  function transferChai(address _recipient, uint256 _daiAmount) external {
    address _sender = _msgSender();
    if (_daiAmount == uint256(-1)) {
      // Get initial Dai balance of sender
      uint256 _daiBalance = chaiContract.dai(_sender);
      emit ChaiTransferred(_sender, _recipient, _daiBalance);

      // Transfer all Chai, denominated in Chai
      uint256 _chaiBalance = chaiContract.balanceOf(_sender);
      bool _result = chaiContract.transferFrom(_sender, _recipient, _chaiBalance);
      require(_result, "Swapper: Transfer of all Chai failed");

    } else {
      // Withdraw portion of Chai, demoninated in Dai
      bool _result = chaiContract.move(_sender, _recipient, _daiAmount);
      require(_result, "Swapper: Transfer of Chai failed");
      emit ChaiTransferred(_sender, _recipient, _daiAmount);
    }
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
    require(isValidUser[from], "Swapper: from address is not a valid user");
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
