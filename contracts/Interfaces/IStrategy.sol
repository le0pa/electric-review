// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

// For interacting with our own strategy
interface IStrategy {
	// Total staked tokens managed by strategy
	function stakedLockedTotal() external view returns (uint256);

	// Main staked token compounding function
	function earn() external;

	// Transfer want tokens ChargeMaster -> IFOStrategy
	function deposit(uint256 _amount) external returns (uint256);

	// Transfer want tokens IFOStrategy -> ChargeMaster
	function withdraw(uint256 _amount) external returns (uint256);

	function inCaseTokensGetStuck(
		address _token,
		uint256 _amount,
		address _to
	) external;
}
