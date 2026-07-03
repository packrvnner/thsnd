// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// ---------------------------------------------------------------------
///  FairLpOracle — manipulation-resistant USD pricing for a VOLATILE
///  (constant-product) Aerodrome LP token.
///
///  IPriceFeed-compatible (latestRoundData/decimals), so AgentVault can
///  list the LP token exactly like any other asset.
///
///  Method (fair-reserves, per Alpha Homora v2):
///      price_LP = 2 · √(p0 · p1 · r0 · r1) / totalSupply
///  using Chainlink USD prices p0, p1 — NEVER the pool's own spot ratio.
///  Because swaps hold k = r0·r1 (minus fees, which only *grow* k), an
///  attacker who flash-skews the reserves cannot move this answer, while
///  the naive quote (r0·p0 + r1·p1)/L would swing freely.
///
///  Restrictions, enforced in the constructor:
///   - volatile pools only (stable() == false) — stable-curve LPs need
///     different math and are out of scope for v1
///   - both underlying feeds must be 8-decimal Chainlink USD feeds
///   - token decimals must be ≤ 18
///
///  Staleness: updatedAt is the OLDER of the two feeds' timestamps, so
///  AgentVault's maxFeedAge gate applies to both legs.
///
///  STATUS: UNDEPLOYED — written for the audit bundle. Do not deploy or
///  whitelist before the audit covering this file is published.
/// ---------------------------------------------------------------------

interface IPriceFeed {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function decimals() external view returns (uint8);
}

interface IPool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast);
    function totalSupply() external view returns (uint256);
    function stable() external view returns (bool);
}

interface IERC20Meta {
    function decimals() external view returns (uint8);
}

contract FairLpOracle {
    uint8 public constant DECIMALS = 8; // answer scale, Chainlink-USD style

    IPool public immutable pool;
    IPriceFeed public immutable feed0; // USD feed for pool.token0()
    IPriceFeed public immutable feed1; // USD feed for pool.token1()
    uint8 public immutable scale0;     // 18 - token0 decimals
    uint8 public immutable scale1;     // 18 - token1 decimals

    constructor(address _pool, address _feed0, address _feed1) {
        require(_pool != address(0) && _feed0 != address(0) && _feed1 != address(0), "FLO: zero");
        pool = IPool(_pool);
        require(!pool.stable(), "FLO: volatile pools only");
        require(IPriceFeed(_feed0).decimals() == 8 && IPriceFeed(_feed1).decimals() == 8, "FLO: feeds must be 8d");
        uint8 d0 = IERC20Meta(pool.token0()).decimals();
        uint8 d1 = IERC20Meta(pool.token1()).decimals();
        require(d0 <= 18 && d1 <= 18, "FLO: token dec > 18");
        feed0 = IPriceFeed(_feed0);
        feed1 = IPriceFeed(_feed1);
        scale0 = 18 - d0;
        scale1 = 18 - d1;
    }

    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    /// @notice Fair USD price of ONE LP token (1e18 units), scaled to 1e8.
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        int256 a0;
        int256 a1;
        (roundId, updatedAt, answeredInRound, a0, a1) = _readFeeds();
        startedAt = updatedAt;
        answer = _fairPrice(uint256(a0), uint256(a1));
    }

    /// Conservative joins: the OLDER updatedAt, the SMALLER round ids.
    function _readFeeds() internal view returns (uint80 rid, uint256 upd, uint80 air, int256 a0, int256 a1) {
        (uint80 r0, int256 x0,, uint256 u0, uint80 i0) = feed0.latestRoundData();
        (uint80 r1, int256 x1,, uint256 u1, uint80 i1) = feed1.latestRoundData();
        require(x0 > 0 && x1 > 0, "FLO: bad answer");
        rid = r0 < r1 ? r0 : r1;
        upd = u0 < u1 ? u0 : u1;
        air = i0 < i1 ? i0 : i1;
        a0 = x0;
        a1 = x1;
    }

    function _fairPrice(uint256 a0, uint256 a1) internal view returns (int256) {
        (uint256 res0, uint256 res1,) = pool.getReserves();
        uint256 supply = pool.totalSupply();
        require(supply > 0, "FLO: empty pool");

        // g ≈ √(a0·r0n · a1·r1n) with reserves normalized to 1e18, so g is in
        // units 1e((8+18+8+18)/2) = 1e26. Split as √x·√y so each intermediate
        // stays ≤ ~1e35 (no overflow); the floor-error of splitting is ≤ 1
        // part in ~1e15 at these scales.
        uint256 g = _sqrt(a0 * (res0 * (10 ** scale0))) * _sqrt(a1 * (res1 * (10 ** scale1)));

        // price of one 1e18 LP unit, 1e8-scaled: 2·g / supply → 1e26/1e18 = 1e8
        uint256 p = (2 * g) / supply;
        require(p <= uint256(type(int256).max), "FLO: overflow");
        return int256(p);
    }

    // Babylonian square root (floor).
    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
