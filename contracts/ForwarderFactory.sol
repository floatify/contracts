pragma solidity 0.5.12;

import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/upgrades/contracts/upgradeability/ProxyFactory.sol";
import "./Forwarder.sol";
import "./Swapper.sol";

/**
 * @notice This contract is a factory to deploy Forwarder instances for users
 * @dev This is based on EIP 1167: Minimal Proxy Contract. References:
 *   The EIP
 *     - https://eips.ethereum.org/EIPS/eip-1167
 *   Clone Factory repo and projects, included with the associated EIP
 *     - https://github.com/optionality/clone-factory
 *     - https://github.com/optionality/clone-factory/blob/master/contracts/CloneFactory.sol
 *   Open Zeppelin blog post and discussion
 *     - https://blog.openzeppelin.com/deep-dive-into-the-minimal-proxy-contract/
 *     - https://forum.openzeppelin.com/t/deep-dive-into-the-minimal-proxy-contract/1928
 *
 * WARNING: DO NOT CHANGE THE ORDER OF INHERITANCE
 * Because this is an upgradable contract, doing so changes the order of the
 * state variables in the contracts, which can lead to the storage
 * values getting mixed up
 */
contract ForwarderFactory is Initializable, Ownable, ProxyFactory {

  uint256 public version;
  address[] public users;
  mapping (address => address) public getForwarder; // maps user => forwarder

  /**
   * @dev Emitted when a new Forwarder proxy contract is created
   */
  event ForwarderCreated(address indexed user, address indexed forwarder);

  function initialize() public initializer {
    Ownable.initialize(msg.sender);
    version = 1;
  }

  /**
   * @notice Called to deploy a clone of _target for _user
   * @param _target address of the underlying logic contract to delegate to
   * @param _user address of the user who should own the proxy contract
   * @param _swapper address of the Swapper contract to add users
   */
  function createForwarder(address _target, address _user, address _swapper) external onlyOwner {
    address _floatify = owner();
    bytes memory _payload = abi.encodeWithSignature("initialize(address,address)", _user, _floatify);

    // Deploy proxy
    address _forwarder = deployMinimal(_target, _payload);
    emit ForwarderCreated(_user, _forwarder);

    // Update state
    users.push(_user);
    getForwarder[_user] = _forwarder;

    // Add user as a valid user in Swapper.sol
    Swapper(_swapper).addUser(_user);
  }

  /**
   * @notice Check if _query address is a clone of _target
   * @dev source: https://github.com/optionality/clone-factory/blob/master/contracts/CloneFactory.sol
   * @param _target address of the underlying logic contract to compare against
   * @param _query address to check
   */
  function isClone(address _target, address _query) external view returns (bool result) {
    bytes20 targetBytes = bytes20(_target);
    assembly {
      let clone := mload(0x40)
      mstore(clone, 0x363d3d373d3d3d363d7300000000000000000000000000000000000000000000)
      mstore(add(clone, 0xa), targetBytes)
      mstore(add(clone, 0x1e), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)

      let other := add(clone, 0x40)
      extcodecopy(_query, other, 0, 0x2d)
      result := and(
        eq(mload(clone), mload(other)),
        eq(mload(add(clone, 0xd)), mload(add(other, 0xd)))
      )
    }
  }

  /**
   * @notice Returns list of all user addresses
   */
  function getUsers() external view returns (address[] memory) {
    return users;
  }

}
