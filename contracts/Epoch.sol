pragma solidity >=0.8.0;

import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';

contract Epoch is AccessControlEnumerable {
	using SafeMath for uint256;

	uint256 private period;
	uint256 private startTime;
	uint256 private epoch;

	/* ========== CONSTRUCTOR ========== */

	constructor(
		uint256 _period,
		uint256 _startTime,
		uint256 _startEpoch
	) {
		period = _period;
		startTime = _startTime;
		epoch = _startEpoch;
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
	}

	/* ========== Modifier ========== */

	modifier checkStartTime() {
		require(block.timestamp >= startTime, 'Epoch: not started yet');

		_;
	}

	modifier checkEpoch() {
		require(block.timestamp >= nextEpochPoint(), 'Epoch: not allowed');

		_;

		epoch = epoch.add(1);
	}

	/* ========== VIEW FUNCTIONS ========== */

	function getCurrentEpoch() external view returns (uint256) {
		return epoch;
	}

	function getPeriod() external view returns (uint256) {
		return period;
	}

	function getStartTime() external view returns (uint256) {
		return startTime;
	}

	function nextEpochPoint() public view returns (uint256) {
		return startTime.add(epoch.mul(period));
	}

	/* ========== GOVERNANCE ========== */

	function setPeriod(uint256 _period) external onlyRole(DEFAULT_ADMIN_ROLE) {
		period = _period;
	}
}
