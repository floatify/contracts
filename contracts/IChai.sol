pragma solidity ^0.5.0;

/**
 * @dev Chai interface
 */
interface IChai {
  // ERC20 functions
  function totalSupply() external view returns (uint256);
  function balanceOf(address account) external view returns (uint256);
  function transfer(address recipient, uint256 amount) external returns (bool);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);
  // Chai-specific functions
  function dai(address usr) external returns (uint wad);
  function join(address dst, uint wad) external;
  function exit(address src, uint wad) external;
  function draw(address src, uint wad) external;
  function move(address src, address dst, uint wad) external returns (bool);
}