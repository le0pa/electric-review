// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import './lib/Babylonian.sol';
import './Interfaces/IBasisAsset.sol';
import './Interfaces/IOracle.sol';
import './Interfaces/IBoardroom.sol';
import './Interfaces/IShare.sol';
import './Interfaces/IBoardroomAllocation.sol';
import './lib/SafeMathint.sol';
import './lib/UInt256Lib.sol';
import './Interfaces/ITreasury.sol';

/**
 * @title Basis Cash Treasury contract
 * @notice Monetary policy logic to adjust supplies of basis cash assets
 * @author Summer Smith & Rick Sanchez
 */
contract Treasury is AccessControlEnumerable, ITreasury, ReentrancyGuard {
	using SafeERC20 for IERC20;
	using Address for address;
	using SafeMath for uint256;
	using UInt256Lib for uint256;
	using SafeMathInt for int256;

	/* ========= CONSTANT VARIABLES ======== */

	uint256 public override PERIOD;

	/* ========== STATE VARIABLES ========== */

	// flags
	bool public migrated = false;
	bool public initialized = false;

	// epoch
	uint256 public startTime;
	uint256 public override epoch = 0;
	uint256 public epochSupplyContractionLeft = 0;
	uint256 public epochsUnderPeg = 0;

	// core components
	address public dollar;
	address public bond;
	address public share;

	address public boardroomAllocation;
	address public dollarOracle;

	// price
	uint256 public dollarPriceOne;
	uint256 public dollarPriceCeiling;

	uint256 public seigniorageSaved;

	// protocol parameters
	uint256 public bondDepletionFloorPercent;
	uint256 public maxDebtRatioPercent;
	uint256 public devPercentage;
	uint256 public bondRepayPercent;
	int256 public contractionIndex;
	int256 public expansionIndex;
	uint256 public triggerRebasePriceCeiling;
	uint256 public triggerRebaseNumEpochFloor;
	uint256 public maxSupplyContractionPercent;

	// share rewards
	uint256 public sharesMintedPerEpoch;

	address public devAddress;

	/* =================== Events =================== */

	event Initialized(address indexed executor, uint256 at);
	event Migration(address indexed target);
	event RedeemedBonds(
		uint256 indexed epoch,
		address indexed from,
		uint256 amount
	);
	event BoughtBonds(
		uint256 indexed epoch,
		address indexed from,
		uint256 amount
	);
	event TreasuryFunded(
		uint256 indexed epoch,
		uint256 timestamp,
		uint256 seigniorage
	);
	event BoardroomFunded(
		uint256 indexed epoch,
		uint256 timestamp,
		uint256 seigniorage,
		uint256 shareRewards
	);
	event DevsFunded(
		uint256 indexed epoch,
		uint256 timestamp,
		uint256 seigniorage
	);

	/* =================== Modifier =================== */

	modifier whenActive() {
		require(!migrated, 'Migrated');
		require(block.timestamp >= startTime, 'Not started yet');
		_;
	}

	modifier whenNextEpoch() {
		require(block.timestamp >= nextEpochPoint(), 'Not opened yet');
		epoch = epoch.add(1);

		epochSupplyContractionLeft = IERC20(dollar)
			.totalSupply()
			.mul(maxSupplyContractionPercent)
			.div(10000);
		_;
	}

	/* ========== VIEW FUNCTIONS ========== */

	// flags
	function isMigrated() external view returns (bool) {
		return migrated;
	}

	function isInitialized() external view returns (bool) {
		return initialized;
	}

	// epoch
	function nextEpochPoint() public view override returns (uint256) {
		return startTime.add(epoch.mul(PERIOD));
	}

	// oracle
	function getDollarPrice()
		public
		view
		override
		returns (uint256 dollarPrice)
	{
		try IOracle(dollarOracle).consult(dollar, 1e18) returns (
			uint256 price
		) {
			return price;
		} catch {
			revert('Failed to consult dollar price from the oracle');
		}
	}

	// budget
	function getReserve() public view returns (uint256) {
		return seigniorageSaved;
	}

	constructor() {
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
	}

	/* ========== GOVERNANCE ========== */

	function initialize(
		uint256 _period,
		address _dollar,
		address _bond,
		address _share,
		uint256 _startTime,
		address _devAddress,
		address _boardroomAllocation,
		address _dollarOracle
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		require(!initialized, 'Initialized');

		expansionIndex = 1000;
		contractionIndex = 10000;
		bondDepletionFloorPercent = 10000;
		bondRepayPercent = 1000;
		triggerRebaseNumEpochFloor = 5;
		maxSupplyContractionPercent = 300;
		maxDebtRatioPercent = 3500;
		PERIOD = _period;

		dollar = _dollar;
		bond = _bond;
		share = _share;
		startTime = _startTime;
		devAddress = _devAddress;
		boardroomAllocation = _boardroomAllocation;
		dollarOracle = _dollarOracle;
		dollarPriceOne = 1e18;
		dollarPriceCeiling = dollarPriceOne.mul(101).div(100);
		triggerRebasePriceCeiling = dollarPriceOne.mul(80).div(100);

		seigniorageSaved = IERC20(dollar).balanceOf(address(this));

		initialized = true;
		emit Initialized(msg.sender, block.number);
	}

	function setContractionIndex(int256 _contractionIndex)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(_contractionIndex >= 0, 'less than 0');
		require(_contractionIndex <= 10000, 'Contraction too large');
		contractionIndex = _contractionIndex;
	}

	function setExpansionIndex(int256 _expansionIndex)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(_expansionIndex >= 0, 'less than 0');
		require(_expansionIndex <= 10000, 'Expansion too large');
		expansionIndex = _expansionIndex;
	}

	function setBondRepayPercent(uint256 _bondRepayPercent)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(_bondRepayPercent <= 10000, 'Bond repayment is too large');
		bondRepayPercent = _bondRepayPercent;
	}

	function setMaxSupplyContractionPercent(
		uint256 _maxSupplyContractionPercent
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		require(
			_maxSupplyContractionPercent >= 100 &&
				_maxSupplyContractionPercent <= 10000,
			'out of range'
		); // [0.1%, 100%]
		maxSupplyContractionPercent = _maxSupplyContractionPercent;
	}

	function setMaxDebtRatioPercent(uint256 _maxDebtRatioPercent)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(
			_maxDebtRatioPercent >= 500 && _maxDebtRatioPercent <= 10000,
			'out of range'
		); // [5%, 100%]
		maxDebtRatioPercent = _maxDebtRatioPercent;
	}

	function setBondDepletionFloorPercent(uint256 _bondDepletionFloorPercent)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(
			_bondDepletionFloorPercent >= 500 &&
				_bondDepletionFloorPercent <= 10000,
			'out of range'
		); // [5%, 100%]
		bondDepletionFloorPercent = _bondDepletionFloorPercent;
	}

	function setDevPercentage(uint256 _devPercentage)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(_devPercentage < 2000, 'Greedy devs are bad.');

		devPercentage = _devPercentage;
	}

	function setDevAddress(address _devAddress)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		devAddress = _devAddress;
	}

	function setDollarOracle(address _dollarOracle)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		dollarOracle = _dollarOracle;
	}

	function setDollarPriceCeiling(uint256 _dollarPriceCeiling)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(
			_dollarPriceCeiling >= dollarPriceOne &&
				_dollarPriceCeiling <= dollarPriceOne.mul(120).div(100),
			'out of range'
		); // [$1.0, $1.2]
		dollarPriceCeiling = _dollarPriceCeiling;
	}

	function setTriggerRebasePriceCeiling(uint256 _triggerRebasePriceCeiling)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		require(
			_triggerRebasePriceCeiling < dollarPriceOne,
			'rebase ceiling is too high'
		);
		triggerRebasePriceCeiling = _triggerRebasePriceCeiling;
	}

	function setTriggerRebaseNumEpochFloor(uint256 _triggerRebaseNumEpochFloor)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		triggerRebaseNumEpochFloor = _triggerRebaseNumEpochFloor;
	}

	function setSharesMintedPerEpoch(uint256 _sharesMintedPerEpoch)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		sharesMintedPerEpoch = _sharesMintedPerEpoch;
	}

	/**
	 * @dev Handles migrating assets to a new treasury contract
	 *
	 * Steps to migrate
	 *	1. Deploy new treasury contract with required roles
	 * 	2. Call this migrate method with `target`
	 *  3. Revoke roles of this contract (optional, as all mint/rebase functions are blocked after migration)
	 *
	 * @param target The address of the new Treasury contract
	 *
	 */
	function migrate(address target) external onlyRole(DEFAULT_ADMIN_ROLE) {
		require(!migrated, 'Migrated');

		IERC20(dollar).safeTransfer(
			target,
			IERC20(dollar).balanceOf(address(this))
		);
		IERC20(bond).safeTransfer(
			target,
			IERC20(bond).balanceOf(address(this))
		);
		IERC20(share).safeTransfer(
			target,
			IERC20(share).balanceOf(address(this))
		);

		migrated = true;
		emit Migration(target);
	}

	/* ========== MUTABLE FUNCTIONS ========== */

	function _updateDollarPrice() internal {
		try IOracle(dollarOracle).update() {} catch {}
	}

	function buyBonds(uint256 amount) external nonReentrant whenActive {
		require(amount > 0, 'Cannot purchase bonds with zero amount');

		uint256 dollarPrice = getDollarPrice();
		uint256 accountBalance = IERC20(dollar).balanceOf(msg.sender);

		require(
			dollarPrice < dollarPriceOne, // price < $1
			'DollarPrice not eligible for bond purchase'
		);

		require(
			amount <= epochSupplyContractionLeft,
			'Not enough bond left to purchase this epoch'
		);
		require(accountBalance >= amount, 'Not enough BTD to buy bond');

		uint256 dollarSupply = IERC20(dollar).totalSupply();
		uint256 newBondSupply = IERC20(bond).totalSupply().add(amount);

		require(
			newBondSupply <= dollarSupply.mul(maxDebtRatioPercent).div(10000),
			'over max debt ratio'
		);

		IBasisAsset(dollar).burnFrom(msg.sender, amount);
		IBasisAsset(bond).mint(msg.sender, amount);

		epochSupplyContractionLeft = epochSupplyContractionLeft.sub(amount);
		_updateDollarPrice();

		emit BoughtBonds(epoch, msg.sender, amount);
	}

	function redeemBonds(uint256 amount) external nonReentrant whenActive {
		require(amount > 0, 'Cannot redeem bonds with zero amount');

		uint256 dollarPrice = getDollarPrice();
		require(
			dollarPrice > dollarPriceCeiling, // price > $1.01
			'DollarPrice not eligible for bond purchase'
		);
		require(
			IERC20(dollar).balanceOf(address(this)) >= amount,
			'Treasury has no more budget'
		);
		require(getReserve() >= amount, "Treasury hasn't saved any dollar");

		seigniorageSaved = seigniorageSaved.sub(
			Math.min(seigniorageSaved, amount)
		);

		IBasisAsset(bond).burnFrom(msg.sender, amount);
		IERC20(dollar).safeTransfer(msg.sender, amount);

		_updateDollarPrice();

		emit RedeemedBonds(epoch, msg.sender, amount);
	}

	function allocateSeigniorage()
		external
		nonReentrant
		whenActive
		whenNextEpoch
	{
		_updateDollarPrice();

		// expansion amount = (TWAP - 1.00) * totalsupply * index / maxindex
		// 10% saved for bonds
		// 10% after bonds saved for team
		// 45% after bonds given to shares
		// 45% after bonds given to LP

		uint256 dollarPrice = getDollarPrice();
		epochsUnderPeg = dollarPrice >= dollarPriceOne
			? 0
			: epochsUnderPeg.add(1);

		int256 supplyDelta = _computeSupplyDelta(dollarPrice, dollarPriceOne);
		uint256 shareRewards = _getSharesRewardsForEpoch();

		if (dollarPrice > dollarPriceCeiling) {
			_expandDollar(supplyDelta, shareRewards);
		} else if (
			dollarPrice <= triggerRebasePriceCeiling ||
			epochsUnderPeg > triggerRebaseNumEpochFloor
		) {
			_contractDollar(supplyDelta, shareRewards);
		} else {
			//always send shares to boardroom
			_sendToBoardRoom(0, shareRewards);
		}
	}

	function governanceRecoverUnsupported(
		IERC20 _token,
		uint256 _amount,
		address _to
	) external onlyRole(DEFAULT_ADMIN_ROLE) {
		// do not allow to drain core tokens
		require(address(_token) != address(dollar), 'dollar');
		require(address(_token) != address(bond), 'bond');
		require(address(_token) != address(share), 'share');
		_token.safeTransfer(_to, _amount);
	}

	function _getSharesRewardsForEpoch() internal view returns (uint256) {
		uint256 mintLimit = IShare(share).mintLimitOf(address(this));
		uint256 mintedAmount = IShare(share).mintedAmountOf(address(this));

		uint256 amountMintable = mintLimit > mintedAmount
			? mintLimit.sub(mintedAmount)
			: 0;

		return Math.min(sharesMintedPerEpoch, amountMintable);
	}

	function _expandDollar(int256 supplyDelta, uint256 shareRewards) private {
		// Expansion (Price > 1.01$): there is some seigniorage to be allocated
		supplyDelta = supplyDelta.mul(expansionIndex).div(10000);

		uint256 _bondSupply = IERC20(bond).totalSupply();
		uint256 _savedForBond = 0;
		uint256 _savedForBoardRoom;
		uint256 _savedForDevs;

		if (
			seigniorageSaved >=
			_bondSupply.mul(bondDepletionFloorPercent).div(10000)
		) {
			_savedForBoardRoom = uint256(supplyDelta);
		} else {
			// have not saved enough to pay dept, mint more
			uint256 _seigniorage = uint256(supplyDelta);

			if (
				_seigniorage.mul(bondRepayPercent).div(10000) <=
				_bondSupply.sub(seigniorageSaved)
			) {
				_savedForBond = _seigniorage.mul(bondRepayPercent).div(10000);
				_savedForBoardRoom = _seigniorage.sub(_savedForBond);
			} else {
				_savedForBond = _bondSupply.sub(seigniorageSaved);
				_savedForBoardRoom = _seigniorage.sub(_savedForBond);
			}
		}

		if (_savedForBond > 0) {
			seigniorageSaved = seigniorageSaved.add(_savedForBond);
			emit TreasuryFunded(epoch, block.timestamp, _savedForBond);
			IBasisAsset(dollar).mint(address(this), _savedForBond);
		}

		if (_savedForBoardRoom > 0) {
			_savedForDevs = _savedForBoardRoom.mul(devPercentage).div(10000);
			_savedForBoardRoom = _savedForBoardRoom.sub(_savedForDevs);
			_sendToDevs(_savedForDevs);
		}

		_sendToBoardRoom(_savedForBoardRoom, shareRewards);
	}

	function _contractDollar(int256 supplyDelta, uint256 shareRewards) private {
		supplyDelta = supplyDelta.mul(contractionIndex).div(10000);
		IBasisAsset(dollar).rebase(epoch, supplyDelta);
		_sendToBoardRoom(0, shareRewards);
	}

	function _sendToDevs(uint256 _amount) internal {
		if (_amount > 0) {
			require(
				IBasisAsset(dollar).mint(devAddress, _amount),
				'Unable to mint for devs'
			);
			emit DevsFunded(epoch, block.timestamp, _amount);
		}
	}

	function _sendToBoardRoom(uint256 _cashAmount, uint256 _shareAmount)
		internal
	{
		if (_cashAmount > 0 || _shareAmount > 0) {
			uint256 boardroomCount = IBoardroomAllocation(boardroomAllocation)
				.boardroomInfoLength();

			// mint assets
			if (_cashAmount > 0)
				IBasisAsset(dollar).mint(address(this), _cashAmount);

			if (_shareAmount > 0)
				IBasisAsset(share).mint(address(this), _shareAmount);

			for (uint256 i = 0; i < boardroomCount; i++) {
				(
					address boardroom,
					bool isActive,
					uint256 cashAllocationPoints,
					uint256 shareAllocationPoints
				) = IBoardroomAllocation(boardroomAllocation).boardrooms(i);
				if (isActive) {
					uint256 boardroomCashAmount = _cashAmount
						.mul(cashAllocationPoints)
						.div(
							IBoardroomAllocation(boardroomAllocation)
								.totalCashAllocationPoints()
						);

					uint256 boardroomShareAmount = _shareAmount
						.mul(shareAllocationPoints)
						.div(
							IBoardroomAllocation(boardroomAllocation)
								.totalShareAllocationPoints()
						);

					if (boardroomCashAmount > 0)
						IERC20(dollar).safeApprove(
							boardroom,
							boardroomCashAmount
						);

					if (boardroomShareAmount > 0)
						IERC20(share).safeApprove(
							boardroom,
							boardroomShareAmount
						);

					if (boardroomCashAmount > 0 || boardroomShareAmount > 0) {
						IBoardroom(boardroom).allocateSeigniorage(
							boardroomCashAmount,
							boardroomShareAmount
						);
					}
				}
			}

			emit BoardroomFunded(
				epoch,
				block.timestamp,
				_cashAmount,
				_shareAmount
			);
		}
	}

	/**
	 * @return Computes the total supply adjustment in response to the exchange rate
	 *         and the targetRate.
	 */
	function _computeSupplyDelta(uint256 rate, uint256 targetRate)
		private
		view
		returns (int256)
	{
		int256 targetRateSigned = targetRate.toInt256Safe();

		int256 supply = (
			IERC20(dollar)
				.totalSupply()
				.sub(IERC20(dollar).balanceOf(address(this)))
				.sub(boardroomsBalance())
		).toInt256Safe();

		if (rate < targetRate) {
			supply = IBasisAsset(dollar).rebaseSupply().toInt256Safe();
		}
		return
			supply.mul(rate.toInt256Safe().sub(targetRateSigned)).div(
				targetRateSigned
			);
	}

	function boardroomsBalance() private view returns (uint256) {
		uint256 bal = 0;

		uint256 boardroomCount = IBoardroomAllocation(boardroomAllocation)
			.boardroomInfoLength();

		for (uint256 i = 0; i < boardroomCount; i++) {
			(address boardroom, , , ) = IBoardroomAllocation(
				boardroomAllocation
			).boardrooms(i);

			bal = bal.add(IERC20(dollar).balanceOf(boardroom));
		}

		return bal;
	}
}
