pragma solidity >=0.8.0;

interface IBoardroom {
	function balanceOf(address _director) external view returns (uint256);

	function earned(address _director) external view returns (uint256, uint256);

	function canWithdraw(address _director) external view returns (bool);

	function canClaimReward(address _director) external view returns (bool);

	function setOperator(address _operator) external;

	function setLockUp(
		uint256 _withdrawLockupEpochs,
		uint256 _rewardLockupEpochs
	) external;

	function stake(uint256 _amount) external;

	function withdraw(uint256 _amount) external;

	function exit() external;

	function claimReward() external;

	function allocateSeigniorage(uint256 _cashReward, uint256 _shareReward)
		external;

	function governanceRecoverUnsupported(
		address _token,
		uint256 _amount,
		address _to
	) external;

	function APR() external pure returns (uint256);
}
