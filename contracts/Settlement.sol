pragma solidity 0.5.12;

import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/GSN/GSNRecipient.sol";
import "./IERC20.sol";
import "./IChai.sol";
import "./IKyberNetworkProxy.sol";

/**
 * @notice In the event that MakerDAO triggers an Emergency Shutdown (also
 * known as a Global Settlement) this contract can be used to simplify
 * the process of cashing out your Chai or Dai. The Global Settlement process
 * lets Dai holders redeem 1 DAI for $1 worth of ETH. This contract aims to
 * remove exposure to the volatility of Ether by providing two options:
 *   1. Redeem the DAI for ETH, then convert ETH to USDC. The USDC will be
 *      sent to the address that triggered the transaction.
 *   2. Redeem the DAI for ETH, then send the Ether to a liqudation address.
 *      This is intended for use with systems like Wyre, where users have a
 *      designated address, and all Ether sent to that address is automatically
 *      liquidated and sent to their bank account.
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


interface IEnd {
  // TODO
}

contract Settlement is Initializable, Ownable, GSNRecipient {

  IERC20 public daiContract;
  IChai public chaiContract;
  IKyberNetworkProxy public knpContract;
  IEnd public endContract;

  /**
   * @notice Constructor, calls other constructors. Can only be called once
   * due to initializer modifier
   * @dev Called initializeSwapper instead of initialize to avoid having the
   * same function signature as Owanble's initializer
   */
  function initializeSettlement() public initializer {
    // Call constructors of contracts we inherit from
    Ownable.initialize(_msgSender());
    GSNRecipient.initialize();

    // Set contract definitions
    daiContract = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    chaiContract = IChai(0x06AF07097C9Eeb7fD685c692751D5C66dB49c215);
    knpContract = IKyberNetworkProxy(0x818E6FECD516Ecc3849DAf6845e3EC868087B755);
    endContract = IEnd(0xaB14d3CE3F733CACB76eC2AbE7d2fcb00c99F3d5);

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
