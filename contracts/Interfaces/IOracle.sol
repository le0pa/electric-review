pragma solidity >=0.8.0;

interface IOracle {
	function update() external;

	function consult(address token, uint256 amountIn)
		external
		view
		returns (uint256 amountOut);
}
