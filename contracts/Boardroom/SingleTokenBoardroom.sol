// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import './Boardroom.sol';

contract SingleTokenBoardroom is Boardroom {
	address[] public wantToStablePath;

	constructor(
		IERC20 _cash,
		IERC20 _share,
		IERC20 _wantToken,
		ITreasury _treasury,
		IPancakeRouter02 _router,
		address[] memory _cashToStablePath,
		address[] memory _shareToStablePath,
		address[] memory _wantToStablePath
	)
		Boardroom(
			_cash,
			_share,
			_wantToken,
			_treasury,
			_router,
			_cashToStablePath,
			_shareToStablePath
		)
	{
		wantToStablePath = _wantToStablePath;
	}

	function _getWantTokenPrice() internal view override returns (uint256) {
		return _getTokenPrice(router, wantToStablePath);
	}
}
