pragma solidity ^0.5.0;

import "./IERC20.sol";

/**
 * @dev Kyber Network Interface
 */
interface IKyberNetworkProxy {
  function getExpectedRate(IERC20 src, IERC20 dest, uint srcQty) external view returns (uint expectedRate, uint slippageRate);
  function swapEtherToToken(IERC20 token, uint minRate) external payable returns (uint);
  function swapTokenToToken(IERC20 src, uint srcAmount, IERC20 dest, uint minConversionRate) external returns(uint);
}