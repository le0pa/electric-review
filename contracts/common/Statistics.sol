// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../Interfaces/IPancakeRouter02.sol';
import './PriceCalculator.sol';

abstract contract Statistics is PriceCalculator {
	function APR() external view virtual returns (uint256);

	function TVL() external view virtual returns (uint256);
}
