// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// ---------------------------------------------------------------------
///  AeroLpAdapter — USDC ⇄ Aerodrome volatile-LP zap for AgentVault
///
///  Implements IRouteAdapter.swap(tokenIn, tokenOut, amountIn, minOut) so
///  the vault can treat the LP token as a listed asset (priced by
///  FairLpOracle) and enter/exit it through its normal trade() path:
///
///    zap-in :  tokenIn = USDC, tokenOut = pool (LP token)
///              pull USDC → swap half to WETH → addLiquidity →
///              LP minted straight to the vault, leftovers refunded
///    zap-out:  tokenIn = pool, tokenOut = USDC
///              pull LP → removeLiquidity → swap WETH leg to USDC →
///              all USDC to the vault
///
///  Pull model, stateless, holds nothing between calls (same contract
///  posture as AeroAdapter).
///
///  SECURITY NOTE — router-leg minimums are deliberately 0 here. This
///  adapter is only reachable through AgentVault, which enforces, per
///  trade: (1) the caller's minOut on the units received, (2) an
///  oracle-value slippage floor (maxSlippageBps) priced by Chainlink /
///  FairLpOracle, and (3) the per-trade NAV cap. Total extractable value
///  from sandwiching a zap is therefore bounded by the vault, not by
///  this contract. Do NOT reuse this adapter from contexts without an
///  equivalent value floor.
///
///  STATUS: UNDEPLOYED — written for the audit bundle. Do not deploy or
///  whitelist before the audit covering this file is published.
/// ---------------------------------------------------------------------

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
}

interface IAeroRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function poolFor(address tokenA, address tokenB, bool stable, address _factory) external view returns (address);
}

interface IPoolMeta {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function stable() external view returns (bool);
}

contract AeroLpAdapter {
    address public owner;
    IAeroRouter public router;
    address public factory;

    address public immutable pool; // the LP token AND the pair
    address public immutable usdc;
    address public immutable weth;

    event RouterSet(address router, address factory);
    event ZapIn(uint256 usdcIn, uint256 lpOut, uint256 usdcRefund, uint256 wethRefund);
    event ZapOut(uint256 lpIn, uint256 usdcOut);

    modifier onlyOwner() {
        require(msg.sender == owner, "ALA: not owner");
        _;
    }

    constructor(address _router, address _factory, address _pool, address _usdc, address _weth) {
        require(
            _router != address(0) && _factory != address(0) && _pool != address(0) && _usdc != address(0)
                && _weth != address(0),
            "ALA: zero"
        );
        owner = msg.sender;
        router = IAeroRouter(_router);
        factory = _factory;
        pool = _pool;
        usdc = _usdc;
        weth = _weth;

        require(!IPoolMeta(_pool).stable(), "ALA: volatile only");
        address t0 = IPoolMeta(_pool).token0();
        address t1 = IPoolMeta(_pool).token1();
        require((t0 == _usdc && t1 == _weth) || (t0 == _weth && t1 == _usdc), "ALA: pool/token mismatch");
        require(IAeroRouter(_router).poolFor(_weth, _usdc, false, _factory) == _pool, "ALA: router pool mismatch");
    }

    function setRouter(address _router, address _factory) external onlyOwner {
        require(_router != address(0) && _factory != address(0), "ALA: zero");
        require(IAeroRouter(_router).poolFor(weth, usdc, false, _factory) == pool, "ALA: router pool mismatch");
        router = IAeroRouter(_router);
        factory = _factory;
        emit RouterSet(_router, _factory);
    }

    function transferOwnership(address n) external onlyOwner {
        require(n != address(0), "ALA: zero owner");
        owner = n;
    }

    // ---------------------------------------------------------------- IRouteAdapter
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) external returns (uint256 out) {
        require(amountIn > 0, "ALA: zero in");
        if (tokenIn == usdc && tokenOut == pool) return _zapIn(amountIn, minOut);
        if (tokenIn == pool && tokenOut == usdc) return _zapOut(amountIn, minOut);
        revert("ALA: unsupported pair");
    }

    // ---------------------------------------------------------------- zap in
    function _zapIn(uint256 usdcIn, uint256 minLpOut) internal returns (uint256 lpOut) {
        require(IERC20(usdc).transferFrom(msg.sender, address(this), usdcIn), "ALA: pull failed");

        // swap half the USDC to WETH (leg min 0 — see SECURITY NOTE)
        uint256 half = usdcIn / 2;
        _approve(usdc, address(router), usdcIn); // covers swap leg + addLiquidity leg
        IAeroRouter.Route[] memory routes = new IAeroRouter.Route[](1);
        routes[0] = IAeroRouter.Route({from: usdc, to: weth, stable: false, factory: factory});
        router.swapExactTokensForTokens(half, 0, routes, address(this), block.timestamp);

        uint256 wethBal = IERC20(weth).balanceOf(address(this));
        _approve(weth, address(router), wethBal);
        (,, lpOut) = router.addLiquidity(
            weth, usdc, false, wethBal, usdcIn - half, 0, 0, msg.sender, block.timestamp
        );
        require(lpOut >= minLpOut, "ALA: minOut");

        // refund any unconsumed legs to the vault (both are listed assets there)
        uint256 usdcDust = IERC20(usdc).balanceOf(address(this));
        uint256 wethDust = IERC20(weth).balanceOf(address(this));
        if (usdcDust > 0) require(IERC20(usdc).transfer(msg.sender, usdcDust), "ALA: refund usdc");
        if (wethDust > 0) require(IERC20(weth).transfer(msg.sender, wethDust), "ALA: refund weth");
        _approve(usdc, address(router), 0);
        _approve(weth, address(router), 0);
        emit ZapIn(usdcIn, lpOut, usdcDust, wethDust);
    }

    // ---------------------------------------------------------------- zap out
    function _zapOut(uint256 lpIn, uint256 minUsdcOut) internal returns (uint256 usdcOut) {
        require(IERC20(pool).transferFrom(msg.sender, address(this), lpIn), "ALA: pull failed");
        _approve(pool, address(router), lpIn);
        (uint256 wethGot,) = router.removeLiquidity(weth, usdc, false, lpIn, 0, 0, address(this), block.timestamp);

        if (wethGot > 0) {
            _approve(weth, address(router), wethGot);
            IAeroRouter.Route[] memory routes = new IAeroRouter.Route[](1);
            routes[0] = IAeroRouter.Route({from: weth, to: usdc, stable: false, factory: factory});
            router.swapExactTokensForTokens(wethGot, 0, routes, address(this), block.timestamp);
            _approve(weth, address(router), 0);
        }

        usdcOut = IERC20(usdc).balanceOf(address(this));
        require(usdcOut >= minUsdcOut, "ALA: minOut");
        require(IERC20(usdc).transfer(msg.sender, usdcOut), "ALA: send failed");
        _approve(pool, address(router), 0);
        emit ZapOut(lpIn, usdcOut);
    }

    function _approve(address token, address spender, uint256 amount) internal {
        require(IERC20(token).approve(spender, amount), "ALA: approve failed");
    }
}
