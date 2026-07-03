// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20Balance {
    function balanceOf(address account) external view returns (uint256);
}

interface ILatticeLock {
    function locks(address user) external view returns (uint128 amount, uint128 power, uint64 end);
}

/// ---------------------------------------------------------------------
///  TierRegistry — Slippage Insurance Matrix ("execution tiers")
///
///  Pure view layer: tierOf(user) is read by the frontend and by the
///  Lattice fee hook to grant reduced protocol-fee execution.
///
///  Effective balance = wallet MUY + 2x locked MUY (locking is rewarded).
///
///  Default tiers (owner-tunable, only downward-friendly changes ever):
///    Tier 0  —            < 10,000 MUY   : standard execution
///    Tier 1  MATRIX     ≥ 10,000 MUY     : -25% protocol fee
///    Tier 2  CONCENTRATE ≥ 100,000 MUY   : -50% protocol fee
///    Tier 3  SINGULARITY ≥ 1,000,000 MUY : zero protocol fee
///
///  NOTE for legal copy: this is a fee-tier system, not insurance in the
///  regulated sense. Keep "insurance" out of terms-of-service language.
/// ---------------------------------------------------------------------
contract TierRegistry {
    IERC20Balance public immutable muy;
    ILatticeLock public immutable latticeLock;
    address public owner;

    uint256 public constant LOCK_WEIGHT_BPS = 20_000; // locked MUY counts 2x

    // thresholds[i] = min effective balance for tier i+1 (ascending)
    uint256[] public thresholds;
    // feeDiscountBps[i] = discount for tier i (index 0 = tier 0 = 0 bps)
    uint256[] public feeDiscountBps;

    event TiersSet(uint256[] thresholds, uint256[] feeDiscountBps);

    modifier onlyOwner() {
        require(msg.sender == owner, "TR: not owner");
        _;
    }

    constructor(address _muy, address _latticeLock) {
        muy = IERC20Balance(_muy);
        latticeLock = ILatticeLock(_latticeLock);
        owner = msg.sender;

        thresholds = [10_000e18, 100_000e18, 1_000_000e18];
        feeDiscountBps = [0, 2_500, 5_000, 10_000];
    }

    // ---------------------------------------------------------------- Admin
    function setTiers(uint256[] calldata _thresholds, uint256[] calldata _feeDiscountBps) external onlyOwner {
        require(_feeDiscountBps.length == _thresholds.length + 1, "TR: length mismatch");
        for (uint256 i = 1; i < _thresholds.length; i++) {
            require(_thresholds[i] > _thresholds[i - 1], "TR: not ascending");
        }
        for (uint256 i = 0; i < _feeDiscountBps.length; i++) {
            require(_feeDiscountBps[i] <= 10_000, "TR: >100%");
        }
        thresholds = _thresholds;
        feeDiscountBps = _feeDiscountBps;
        emit TiersSet(_thresholds, _feeDiscountBps);
    }

    function transferOwnership(address n) external onlyOwner {
        require(n != address(0), "TR: zero owner");
        owner = n;
    }

    // ---------------------------------------------------------------- Views
    function effectiveBalance(address user) public view returns (uint256) {
        (uint128 lockedAmount,, uint64 end) = latticeLock.locks(user);
        uint256 lockedBoost = block.timestamp < end ? (uint256(lockedAmount) * LOCK_WEIGHT_BPS) / 10_000 : 0;
        return muy.balanceOf(user) + lockedBoost;
    }

    function tierOf(address user) public view returns (uint256 tier) {
        uint256 bal = effectiveBalance(user);
        uint256 n = thresholds.length;
        for (uint256 i = 0; i < n; i++) {
            if (bal >= thresholds[i]) tier = i + 1;
            else break;
        }
    }

    /// @notice Protocol-fee discount in bps for a user (0 .. 10_000).
    function discountOf(address user) external view returns (uint256) {
        return feeDiscountBps[tierOf(user)];
    }
}
