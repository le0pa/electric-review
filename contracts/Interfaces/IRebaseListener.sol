// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IRebaseListener {
	function tokenRebased(
		address token,
		uint256 prevRebaseSupply,
		uint256 currentRebaseSupply,
		uint256 prevTotalSupply,
		uint256 currentTotalSupply
	) external;
}
