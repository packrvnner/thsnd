// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// ---------------------------------------------------------------------
///  AeroAdapter — single-hop Aerodrome route for MILLI + BurnEngine
///
///  Pull model: caller approves amountIn, adapter pulls, swaps on the
///  Aerodrome router, and forwards proceeds. Stateless between calls;
///  holds no balances. Implements BOTH:
///   - IRouteAdapter.swap(...)          (AgentVault trades — proceeds to caller)
///   - ISwapRouter.swapExactInput(...)  (BurnEngine route — proceeds to recipient)
///
///  Owner (treasury Safe) can only retune the router address and per-pair
///  stable flags. No custody, no sweep of in-flight funds beyond refunds.
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

    function defaultFactory() external view returns (address);
}

contract AeroAdapter {
    address public owner;
    IAeroRouter public router;
    address public factory;
    // pair key => use stable pool
    mapping(bytes32 => bool) public stablePair;

    event RouterSet(address router, address factory);
    event StablePairSet(address tokenA, address tokenB, bool stable);

    modifier onlyOwner() {
        require(msg.sender == owner, "AA: not owner");
        _;
    }

    constructor(address _router, address _factory) {
        owner = msg.sender;
        router = IAeroRouter(_router);
        factory = _factory;
    }

    function setRouter(address _router, address _factory) external onlyOwner {
        require(_router != address(0) && _factory != address(0), "AA: zero");
        router = IAeroRouter(_router);
        factory = _factory;
        emit RouterSet(_router, _factory);
    }

    function setStablePair(address a, address b, bool stable) external onlyOwner {
        stablePair[_key(a, b)] = stable;
        emit StablePairSet(a, b, stable);
    }

    function transferOwnership(address n) external onlyOwner {
        require(n != address(0), "AA: zero owner");
        owner = n;
    }

    // ---------------------------------------------------------------- AgentVault path
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) external returns (uint256 out) {
        return _swapTo(tokenIn, tokenOut, amountIn, minOut, msg.sender);
    }

    // ---------------------------------------------------------------- BurnEngine path (ISwapRouter)
    function swapExactInput(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address recipient)
        external
        returns (uint256 amountOut)
    {
        return _swapTo(tokenIn, tokenOut, amountIn, minAmountOut, recipient);
    }

    // ---------------------------------------------------------------- Core
    function _swapTo(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut, address to)
        internal
        returns (uint256 out)
    {
        require(amountIn > 0, "AA: zero in");
        require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "AA: pull failed");
        require(IERC20(tokenIn).approve(address(router), amountIn), "AA: approve failed");

        IAeroRouter.Route[] memory routes = new IAeroRouter.Route[](1);
        routes[0] = IAeroRouter.Route({from: tokenIn, to: tokenOut, stable: stablePair[_key(tokenIn, tokenOut)], factory: factory});

        uint256 beforeBal = IERC20(tokenOut).balanceOf(to);
        router.swapExactTokensForTokens(amountIn, minOut, routes, to, block.timestamp);
        out = IERC20(tokenOut).balanceOf(to) - beforeBal;
        require(out >= minOut, "AA: minOut");
        require(IERC20(tokenIn).approve(address(router), 0), "AA: unapprove failed");
    }

    function _key(address a, address b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
}
