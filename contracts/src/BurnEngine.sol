// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface ITHSND is IERC20 {
    function burn(uint256 amount) external;
}

/// @dev Minimal swap-router interface. Any Lattice/Aerodrome/UniV3-style
///      router can be adapted behind this via a thin wrapper.
interface ISwapRouter {
    /// @return amountOut MUY received
    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);
}

/// ---------------------------------------------------------------------
///  BurnEngine — the deflationary core
///
///  Flow:
///   1. MUY Strata's liquidation path transfers 1.5% of seized collateral
///      here (see LiquidationHook snippet in Strata's module).
///   2. A keeper calls execute(asset): the engine market-buys MUY through
///      a whitelisted route and burns 100% of proceeds. Forever.
///
///  Safety rails:
///   - Per-asset route whitelist (owner-set). No arbitrary calls.
///   - Keeper role for execution timing (MEV/sandwich control) with an
///     owner-set max slippage vs. keeper-provided minOut floor.
///   - No withdrawal path for MUY: anything the engine buys can only burn.
///     Non-whitelisted stray assets can be swept by owner (never MUY).
/// ---------------------------------------------------------------------
contract BurnEngine {
    ITHSND public immutable muy;
    address public owner;

    mapping(address => bool) public isKeeper;
    // asset => router approved to trade it for MUY
    mapping(address => address) public routeOf;

    uint256 public totalMuyBurned;

    event RouteSet(address indexed asset, address indexed router);
    event KeeperSet(address indexed keeper, bool enabled);
    event Executed(address indexed asset, uint256 amountIn, uint256 muyBurned);
    event Swept(address indexed asset, uint256 amount, address indexed to);

    modifier onlyOwner() {
        require(msg.sender == owner, "BE: not owner");
        _;
    }

    modifier onlyKeeper() {
        require(isKeeper[msg.sender] || msg.sender == owner, "BE: not keeper");
        _;
    }

    constructor(address _muy) {
        muy = ITHSND(_muy);
        owner = msg.sender;
    }

    // ---------------------------------------------------------------- Admin
    function setRoute(address asset, address router) external onlyOwner {
        require(asset != address(muy), "BE: THSND needs no route");
        routeOf[asset] = router;
        emit RouteSet(asset, router);
    }

    function setKeeper(address keeper, bool enabled) external onlyOwner {
        isKeeper[keeper] = enabled;
        emit KeeperSet(keeper, enabled);
    }

    function transferOwnership(address n) external onlyOwner {
        require(n != address(0), "BE: zero owner");
        owner = n;
    }

    // ---------------------------------------------------------------- Core
    /// @notice Market-buy MUY with the engine's entire balance of `asset`, then burn it.
    /// @param minMuyOut Slippage floor. Keeper computes offchain (e.g. TWAP - tolerance).
    function execute(address asset, uint256 minMuyOut) external onlyKeeper returns (uint256 burned) {
        address router = routeOf[asset];
        require(router != address(0), "BE: no route");

        uint256 amountIn = IERC20(asset).balanceOf(address(this));
        require(amountIn > 0, "BE: nothing to burn");
        require(minMuyOut > 0, "BE: zero minOut");

        require(IERC20(asset).approve(router, amountIn), "BE: approve failed");
        uint256 out = ISwapRouter(router).swapExactInput(asset, address(muy), amountIn, minMuyOut, address(this));
        require(out >= minMuyOut, "BE: slippage");

        muy.burn(out);
        totalMuyBurned += out;
        burned = out;
        emit Executed(asset, amountIn, out);
    }

    /// @notice If MUY itself lands here (direct donations), burn it permissionlessly.
    function burnDirect() external returns (uint256 burned) {
        burned = muy.balanceOf(address(this));
        require(burned > 0, "BE: nothing to burn");
        muy.burn(burned);
        totalMuyBurned += burned;
        emit Executed(address(muy), burned, burned);
    }

    /// @notice Rescue non-routed junk tokens. MUY can never leave — only burn.
    function sweep(address asset, address to) external onlyOwner {
        require(asset != address(muy), "BE: THSND only burns");
        require(routeOf[asset] == address(0), "BE: routed asset");
        uint256 bal = IERC20(asset).balanceOf(address(this));
        require(IERC20(asset).transfer(to, bal), "BE: transfer failed");
        emit Swept(asset, bal, to);
    }
}

/// ---------------------------------------------------------------------
///  Strata-side integration reference (lives in the lending module):
///
///  uint256 constant BURN_SLICE_BPS = 150; // 1.5%
///
///  function _afterLiquidation(address collateral, uint256 seized) internal {
///      uint256 slice = (seized * BURN_SLICE_BPS) / 10_000;
///      IERC20(collateral).transfer(address(burnEngine), slice);
///      // keeper picks it up and calls burnEngine.execute(collateral, minOut)
///  }
/// ---------------------------------------------------------------------
