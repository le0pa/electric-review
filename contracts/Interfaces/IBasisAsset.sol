// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import './IMintableToken.sol';

interface IBasisAsset is IMintableToken {
	function burn(uint256 amount) external;

	function burnFrom(address from, uint256 amount) external;

	function isOperator() external returns (bool);

	function operator() external view returns (address);

	function rebase(uint256 epoch, int256 supplyDelta) external;

	function rebaseSupply() external view returns (uint256);
}
