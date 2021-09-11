// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IMintableToken {
	function mint(address recipient_, uint256 amount_) external returns (bool);
}
