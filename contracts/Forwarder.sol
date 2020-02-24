pragma solidity 0.5.12;

import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "./IERC20.sol";
import "./IChai.sol";
import "./IKyberNetworkProxy.sol";


/**
 * @notice This contract is used as the receiving address for a user.
 * All Ether or tokens sent to this contract can only be removed by
 * converting them to Chai and sending them to the owner, where the
 * owner is the user.
 *
 * @dev WARNING: DO NOT CHANGE THE ORDER OF INHERITANCE
 * Because this is an upgradable contract, doing so changes the order of the
 * state variables in the parent contracts, which can lead to the storage
 * values getting mixed up
 */
contract Forwarder is Initializable, Ownable {

  using Address for address payable;  // enables OpenZeppelin's sendValue() function

  // =============================================================================================
  //                                    Storage Variables
  // =============================================================================================

  // Floatify server
  address public floatify;

  // Contract version
  uint256 public version;

  // Contract addresses and interfaces
  IERC20 public daiContract;
  IChai public chaiContract;
  IKyberNetworkProxy public knpContract;
  IERC20 constant public ETH_TOKEN_ADDRESS = IERC20(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);

  // =============================================================================================
  //                                        Events
  // =============================================================================================

  /**
   * @dev Emitted when Chai is successfully minted from Dai held by the contract
   */
  event ChaiSent(uint256 indexed amountInDai);

  /**
   * @dev Emitted when Ether is swapped for Dai
   */
  event SwapEther(uint256 indexed amountInDai, uint256 indexed amountInEther);

  /**
   * @dev Emitted when a token is swapped for Dai
   */
  event SwapToken(uint256 indexed amountInDai, uint256 indexed amountInToken, address token);

  /**
   * @dev Emitted when a token is withdrawn without being converted to Chai
   */
  event RawTokensSent(uint256 indexed amount, address token);

  /**
   * @dev Emitted when Ether is withdrawn without being converted to Chai
   */
  event RawEtherSent(uint256 indexed amount);

  /**
   * @dev Emitted when saved addresses are updated
   */
  event FloatifyAddressChanged(address indexed previousAddress, address indexed newAddress);
  event DaiAddressChanged(address indexed previousAddress, address indexed newAddress);
  event ChaiAddressChanged(address indexed previousAddress, address indexed newAddress);
  event KyberAddressChanged(address indexed previousAddress, address indexed newAddress);


  // ===============================================================================================
  //                                      Constructor
  // ===============================================================================================

  /**
   * @notice Constructor
   * @dev Calls other constructors, can only be called once due to initializer modifier
   * @param _recipient The user address that should receive all funds from this contract
   * @param _floatify Floatify address
   */
  function initialize(address _recipient, address _floatify) public initializer {
    // Call constructors of contracts we inherit from
    Ownable.initialize(_recipient);

    // Set variables
    floatify = _floatify;
    version = 1;

    // Set contract addresses and interfaces
    daiContract = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    chaiContract = IChai(0x06AF07097C9Eeb7fD685c692751D5C66dB49c215);
    knpContract = IKyberNetworkProxy(0x818E6FECD516Ecc3849DAf6845e3EC868087B755);

    // Approve the Chai contract to spend this contract's DAI balance
    approveChaiToSpendDai();
  }

  // ===============================================================================================
  //                                       Helpers
  // ===============================================================================================

  /**
   * @dev Throws if called by any account other than floatify
   */
  modifier onlyFloatify() {
    require(_msgSender() == floatify, "Forwarder: caller is not the floatify address");
    _;
  }


  /**
   * @notice Approve the Chai contract to spend our Dai
   */
  function approveChaiToSpendDai() private {
    bool result = daiContract.approve(address(chaiContract), uint256(-1));
    require(result, "Forwarder: failed to approve Chai contract to spend Dai");
  }


  /**
   * @notice Remove allowance of Chai contract to prevent it from spending Dai
   */
  function resetChaiAllowance() private {
    bool result = daiContract.approve(address(chaiContract), 0);
    require(result, "Forwarder: failed to remove allowance of Chai contract to spend Dai");
  }


  // ===============================================================================================
  //                                    Updating Addresses
  // ===============================================================================================

  /**
   * @dev Allows the floatify address to be changed
   * @param _newAddress new address
   */
  function updateFloatifyAddress(address _newAddress) external onlyFloatify {
    require(_newAddress != address(0), "Forwarder: new floatify address is the zero address");
    emit FloatifyAddressChanged(floatify, _newAddress);
    floatify = _newAddress;
  }

  /**
   * @dev Allows the Dai contract address to be changed
   * @param _newAddress new address
   */
  function updateDaiAddress(address _newAddress) external onlyFloatify {
    // Reset allowance for old address to zero
    resetChaiAllowance();
    // Set new allowance
    emit DaiAddressChanged(address(daiContract), _newAddress);
    daiContract = IERC20(_newAddress);
    approveChaiToSpendDai();
  }

  /**
   * @dev Allows the Chai contract address to be changed
   * @param _newAddress new address
   */
  function updateChaiAddress(address _newAddress) external onlyFloatify {
    // Reset allowance for old address to zero
    resetChaiAllowance();
    // Set new allowance
    emit ChaiAddressChanged(address(chaiContract), _newAddress);
    chaiContract = IChai(_newAddress);
    approveChaiToSpendDai();
  }

  /**
   * @dev Allows the Kyber Proxy contract address to be changed
   * @param _newAddress new address
   */
  function updateKyberAddress(address _newAddress) external onlyFloatify {
    emit KyberAddressChanged(address(knpContract), _newAddress);
    knpContract = IKyberNetworkProxy(_newAddress);
  }


  // ===============================================================================================
  //                               Handling Received Ether/Tokens
  // ===============================================================================================

  /**
   * @notice Convert Dai in this contract to Chai and send it to the owner
   */
  function mintAndSendChai() public {
    // Get Dai balance of this contract
    uint256 _daiBalance = daiContract.balanceOf(address(this));
    // Mint and send Chai
    emit ChaiSent(_daiBalance);
    chaiContract.join(owner(), _daiBalance);
  }


  /**
   * @notice Covert _srcTokenAddress to Chai and send it to the owner
   * @param _srcTokenAddress address of token to send
   */
  function convertAndSendToken(address _srcTokenAddress) external {
    // TODO convert token to Dai
    //   Use "Loose Token Conversion" as shown here
    //   https://developer.kyber.network/docs/DappsGuide/#scenario-1-loose-token-conversion

    // Get token parameters and contract balance
    IERC20 _srcTokenContract = IERC20(_srcTokenAddress);
    uint256 _srcTokenBalance = _srcTokenContract.balanceOf(address(this));

    // Mitigate ERC20 Approve front-running attack, by initially setting allowance to 0
    require(_srcTokenContract.approve(address(knpContract), 0), "Forwarder: first approval failed");

    // Approve tokens so network can take them during the swap
    require(_srcTokenContract.approve(address(knpContract), _srcTokenBalance), "Forwarder: second approval failed");

    // Use slippage rate as the minimum conversion rate
    uint256 minRate;
    (, minRate) = knpContract.getExpectedRate(_srcTokenContract, daiContract, _srcTokenBalance);

    // Swap the ERC20 token for Dai
    knpContract.swapTokenToToken(_srcTokenContract, _srcTokenBalance, daiContract, minRate);

    // Log the event
    uint256 daiBalance = daiContract.balanceOf(address(this));
    emit SwapToken(daiBalance, _srcTokenBalance, _srcTokenAddress);

    // Mint and send Chai
    mintAndSendChai();
  }


  /**
   * @notice Upon receiving Ether, convert it to Chai and send it to the owner
   */
  function convertAndSendEth() external {
    uint256 etherBalance = address(this).balance;

    // Use slippage rate as the minimum conversion rate
    uint256 minRate;
    (, minRate) = knpContract.getExpectedRate(ETH_TOKEN_ADDRESS, daiContract, etherBalance);

    // Swap Ether for Dai, and receive back tokens to this contract's address
    knpContract.swapEtherToToken.value(etherBalance)(daiContract, minRate);

    // Log the event
    uint256 daiBalance = daiContract.balanceOf(address(this));
    emit SwapEther(daiBalance, etherBalance);

    // Convert to Chai and send to owner
    mintAndSendChai();
  }

  // ===============================================================================================
  //                                          Escape Hatches
  // ===============================================================================================

  /**
   * @notice Forwards all tokens to owner
   * @dev This is useful if tokens get stuck, e.g. if Kyber is down somehow
   * @param _tokenAddress address of token to send
   */
  function sendRawTokens(address _tokenAddress) external {
    require(msg.sender == owner() || msg.sender == floatify, "Forwarder: caller must be owner or floatify");

    IERC20 _token = IERC20(_tokenAddress);
    uint256 _balance = _token.balanceOf(address(this));
    emit RawTokensSent(_balance, _tokenAddress);

    _token.transfer(owner(), _balance);
  }

  /**
   * @notice Forwards all Ether to owner
   * @dev This is useful if Ether get stuck, e.g. if Kyber is down somehow
   */
  function sendRawEther() external {
    require(msg.sender == owner() || msg.sender == floatify, "Forwarder: caller must be owner or floatify");

    uint256 _balance = address(this).balance;
    emit RawEtherSent(_balance);

    // Convert `address` to `address payable`
    address payable _recipient = address(uint160(address(owner())));

    // Transfer Ether with OpenZeppelin's sendValue() for reasons explained in below links.
    //   https://diligence.consensys.net/blog/2019/09/stop-using-soliditys-transfer-now/
    //   https://docs.openzeppelin.com/contracts/2.x/api/utils#Address-sendValue-address-payable-uint256-
    // Note: Even though this transfers control to the recipient, we do not have to worry
    // about reentrancy here. This is because:
    //   1. This function can only be called by the contract owner or floatify
    //   2. All Ether sent to this contract belongs to the owner anyway, so there is no
    //      way for reentrancy to enable the owner/attacker to send more Ether to themselves.
    _recipient.sendValue(_balance);
  }

  /**
   * @dev Fallback function to receive Ether
   */
  function() external payable {}
}
