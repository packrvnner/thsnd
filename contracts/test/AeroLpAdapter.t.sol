// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Self-contained test suite (no forge-std dependency), matching MilliVault.t.sol.
// Covers: FairLpOracle math + manipulation resistance, AeroLpAdapter zaps,
// and AgentVault integration through the normal trade() path.
// NOTE for audit: these are unit tests against mocks; a Base-mainnet fork test
// against the real Aerodrome router/pool is a required pre-deploy step.

import {AgentVault} from "../src/milli/AgentVault.sol";
import {AeroLpAdapter} from "../src/milli/AeroLpAdapter.sol";
import {FairLpOracle} from "../src/milli/FairLpOracle.sol";

interface Vm {
    function warp(uint256) external;
    function prank(address) external;
    function startPrank(address) external;
    function stopPrank() external;
    function expectRevert(bytes calldata) external;
}

// ---------------------------------------------------------------- mocks
contract MockERC20 {
    string public name;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _n, uint8 _d) {
        name = _n;
        decimals = _d;
    }

    function mint(address to, uint256 amt) public {
        balanceOf[to] += amt;
        totalSupply += amt;
    }

    function burn(address from, uint256 amt) public {
        balanceOf[from] -= amt;
        totalSupply -= amt;
    }

    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a;
        return true;
    }

    function transfer(address to, uint256 a) external returns (bool) {
        require(balanceOf[msg.sender] >= a, "bal");
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
        return true;
    }

    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        require(balanceOf[f] >= a, "bal");
        uint256 al = allowance[f][msg.sender];
        if (al != type(uint256).max) {
            require(al >= a, "allow");
            allowance[f][msg.sender] = al - a;
        }
        balanceOf[f] -= a;
        balanceOf[t] += a;
        return true;
    }
}

contract MockFeed {
    int256 public answer;
    uint8 public decimals;
    uint256 public updatedAt;

    constructor(int256 _a, uint8 _d) {
        answer = _a;
        decimals = _d;
        updatedAt = block.timestamp;
    }

    function set(int256 _a) external {
        answer = _a;
        updatedAt = block.timestamp;
    }

    function setStale(uint256 t) external {
        updatedAt = t;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

/// LP token + pair in one, like a real Aerodrome pool.
contract MockPool is MockERC20 {
    address public token0;
    address public token1;
    bool public stable;
    uint256 public reserve0;
    uint256 public reserve1;

    constructor(address _t0, address _t1, bool _stable) MockERC20("vAMM-WETH/USDC", 18) {
        token0 = _t0;
        token1 = _t1;
        stable = _stable;
    }

    function setReserves(uint256 r0, uint256 r1) external {
        reserve0 = r0;
        reserve1 = r1;
    }

    function getReserves() external view returns (uint256, uint256, uint256) {
        return (reserve0, reserve1, block.timestamp);
    }
}

/// Router mock: swaps at feed-implied fair value (minus optional haircut),
/// add/remove liquidity against the mock pool at fair proportions.
contract MockAeroRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    MockERC20 public usdc; // 6d
    MockERC20 public weth; // 18d
    MockFeed public wethFeed; // 8d
    MockPool public pool;
    address public factoryAddr;
    uint256 public haircutBps;

    constructor(MockERC20 _u, MockERC20 _w, MockFeed _f, MockPool _p, address _factory) {
        usdc = _u;
        weth = _w;
        wethFeed = _f;
        pool = _p;
        factoryAddr = _factory;
    }

    function setHaircut(uint256 bps) external {
        haircutBps = bps;
    }

    function poolFor(address, address, bool, address) external view returns (address) {
        return address(pool);
    }

    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, Route[] calldata routes, address to, uint256)
        external
        returns (uint256[] memory amounts)
    {
        require(routes.length == 1, "MR: route");
        uint256 px = uint256(wethFeed.answer());
        uint256 out;
        MockERC20(routes[0].from).transferFrom(msg.sender, address(this), amountIn);
        if (routes[0].from == address(usdc)) {
            out = amountIn * 1e8 * 1e12 / px;
        } else {
            out = amountIn * px / 1e8 / 1e12;
        }
        out = out * (10_000 - haircutBps) / 10_000;
        require(out >= amountOutMin, "MR: minOut");
        MockERC20(routes[0].to).mint(to, out);
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = out;
    }

    /// Mints LP at the pool's fair proportion of value added; pulls only what it uses.
    function addLiquidity(
        address tokenA,
        address,
        bool,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256,
        uint256,
        address to,
        uint256
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // identify weth/usdc legs regardless of order
        (uint256 useW, uint256 useU) =
            tokenA == address(weth) ? (amountADesired, amountBDesired) : (amountBDesired, amountADesired);

        // keep legs balanced by value at the feed price
        uint256 valueW = useW * uint256(wethFeed.answer()) / 1e8 / 1e12; // USDC 6d terms
        if (valueW < useU) useU = valueW;
        else useW = useU * 1e8 * 1e12 / uint256(wethFeed.answer());

        liquidity = _settle(useW, useU, to);
        (amountA, amountB) = tokenA == address(weth) ? (useW, useU) : (useU, useW);
    }

    function _settle(uint256 useW, uint256 useU, address to) internal returns (uint256 liquidity) {
        MockERC20(address(weth)).transferFrom(msg.sender, address(this), useW);
        MockERC20(address(usdc)).transferFrom(msg.sender, address(this), useU);
        uint256 px = uint256(wethFeed.answer());
        uint256 poolValue6 = pool.reserve0() * px / 1e8 / 1e12 + pool.reserve1(); // token0=weth,token1=usdc
        uint256 addedValue6 = useW * px / 1e8 / 1e12 + useU;
        uint256 supply = pool.totalSupply();
        liquidity = supply == 0 ? addedValue6 * 1e12 : supply * addedValue6 / poolValue6;
        pool.mint(to, liquidity);
        pool.setReserves(pool.reserve0() + useW, pool.reserve1() + useU);
    }

    function removeLiquidity(address tokenA, address, bool, uint256 liquidity, uint256, uint256, address to, uint256)
        external
        returns (uint256 amountA, uint256 amountB)
    {
        uint256 supply = pool.totalSupply();
        uint256 outW = pool.reserve0() * liquidity / supply;
        uint256 outU = pool.reserve1() * liquidity / supply;
        pool.transferFrom(msg.sender, address(this), liquidity);
        pool.burn(address(this), liquidity);
        pool.setReserves(pool.reserve0() - outW, pool.reserve1() - outU);
        weth.mint(to, outW);
        usdc.mint(to, outU);
        (amountA, amountB) = tokenA == address(weth) ? (outW, outU) : (outU, outW);
    }
}

// ---------------------------------------------------------------- tests
contract AeroLpAdapterTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    MockERC20 usdc;
    MockERC20 weth;
    MockFeed wethFeed; // $2000, 8d
    MockFeed usdcFeed; // $1, 8d
    MockPool pool;
    MockAeroRouter router;
    FairLpOracle oracle;
    AeroLpAdapter adapter;

    address constant FACTORY = address(0xFAC);

    function setUp() public {
        usdc = new MockERC20("USDC", 6);
        weth = new MockERC20("WETH", 18);
        wethFeed = new MockFeed(2000e8, 8);
        usdcFeed = new MockFeed(1e8, 8);
        pool = new MockPool(address(weth), address(usdc), false);
        router = new MockAeroRouter(usdc, weth, wethFeed, pool, FACTORY);

        // balanced pool: 100 WETH + 200_000 USDC, 1000 LP → $400/LP fair
        pool.setReserves(100e18, 200_000e6);
        pool.mint(address(0xDEAD), 1000e18);

        oracle = new FairLpOracle(address(pool), address(wethFeed), address(usdcFeed));
        adapter = new AeroLpAdapter(address(router), FACTORY, address(pool), address(usdc), address(weth));
    }

    function _lpPrice() internal view returns (uint256) {
        (, int256 a,,,) = oracle.latestRoundData();
        return uint256(a);
    }

    // ---------------- oracle
    function test_FairPriceBalancedPool() public view {
        uint256 p = _lpPrice();
        require(p > 39_999_000_000 && p < 40_001_000_000, "fair price != ~$400"); // 400e8 ±0.0025%
    }

    function test_FairPriceIgnoresReserveSkew() public {
        uint256 before = _lpPrice();
        // attacker flash-skews reserves along constant k: 100*200k = 25*800k
        pool.setReserves(25e18, 800_000e6);
        uint256 afterSkew = _lpPrice();
        uint256 diffBps = afterSkew > before ? (afterSkew - before) * 10_000 / before : (before - afterSkew) * 10_000 / before;
        require(diffBps <= 1, "fair price moved on skew");
        // while the naive quote (r0·p0 + r1·p1)/L would read $850 (+112%)
    }

    function test_OracleReportsOldestTimestamp() public {
        wethFeed.setStale(block.timestamp > 1000 ? block.timestamp - 1000 : 0);
        (,,, uint256 upd,) = oracle.latestRoundData();
        require(upd == wethFeed.updatedAt(), "must surface older feed ts");
    }

    function test_OracleRejectsBadAnswer() public {
        wethFeed.set(0);
        vm.expectRevert(bytes("FLO: bad answer"));
        oracle.latestRoundData();
    }

    function test_OracleRejectsStablePool() public {
        MockPool sp = new MockPool(address(weth), address(usdc), true);
        vm.expectRevert(bytes("FLO: volatile pools only"));
        new FairLpOracle(address(sp), address(wethFeed), address(usdcFeed));
    }

    // ---------------- adapter zaps
    function test_ZapInMintsLpAndLeavesNothing() public {
        usdc.mint(address(this), 1_000e6);
        usdc.approve(address(adapter), 1_000e6);
        uint256 minLp = 2.4e18; // ~$1000 at ~$400/LP → 2.5 LP, 4% headroom
        uint256 out = adapter.swap(address(usdc), address(pool), 1_000e6, minLp);
        require(out >= minLp, "lp out");
        require(pool.balanceOf(address(this)) == out, "lp to caller");
        require(usdc.balanceOf(address(adapter)) == 0, "adapter usdc dust");
        require(weth.balanceOf(address(adapter)) == 0, "adapter weth dust");
        require(pool.balanceOf(address(adapter)) == 0, "adapter lp dust");
    }

    function test_ZapOutRoundTrip() public {
        usdc.mint(address(this), 1_000e6);
        usdc.approve(address(adapter), 1_000e6);
        uint256 lp = adapter.swap(address(usdc), address(pool), 1_000e6, 0);

        pool.approve(address(adapter), lp);
        uint256 back = adapter.swap(address(pool), address(usdc), lp, 0);
        // fee-less mocks: round trip within 0.5% of the original
        require(back > 995e6 && back <= 1_001e6, "round trip value");
        require(usdc.balanceOf(address(this)) == back, "usdc to caller");
        require(usdc.balanceOf(address(adapter)) == 0 && weth.balanceOf(address(adapter)) == 0, "adapter empty");
    }

    function test_ZapRejectsUnsupportedPair() public {
        vm.expectRevert(bytes("ALA: unsupported pair"));
        adapter.swap(address(weth), address(pool), 1e18, 0);
    }

    function test_AdapterRejectsMismatchedPool() public {
        MockPool other = new MockPool(address(weth), address(weth), false);
        vm.expectRevert(bytes("ALA: pool/token mismatch"));
        new AeroLpAdapter(address(router), FACTORY, address(other), address(usdc), address(weth));
    }

    // ---------------- vault integration through trade()
    function test_VaultZapWithinCapsKeepsNAV() public {
        AgentVault vault = new AgentVault(address(usdc), address(this), address(this), address(0xFEE));
        vault.setAsset(address(weth), address(wethFeed), true);
        vault.setAsset(address(pool), address(oracle), true);
        vault.setAdapter(address(adapter), true);
        vault.setDepositCaps(100_000e6, 100_000e6);

        usdc.mint(address(this), 10_000e6);
        usdc.approve(address(vault), 10_000e6);
        vault.deposit(10_000e6, address(this));

        uint256 navBefore = vault.totalAssets();
        // 10% per-trade cap on $10k NAV → $1,000 zap exactly at the cap
        vault.trade(address(adapter), address(usdc), address(pool), 1_000e6, 2.4e18);
        uint256 navAfter = vault.totalAssets();

        uint256 dropBps = navBefore > navAfter ? (navBefore - navAfter) * 10_000 / navBefore : 0;
        require(dropBps <= 100, "NAV dropped beyond slippage floor"); // vault-enforced ≤1%
        require(pool.balanceOf(address(vault)) >= 2.4e18, "vault holds LP");

        // and back out
        uint256 lpBal = pool.balanceOf(address(vault));
        vault.trade(address(adapter), address(pool), address(usdc), lpBal, 900e6);
        require(pool.balanceOf(address(vault)) == 0, "lp closed");
    }

    function test_VaultBlocksOversizedZap() public {
        AgentVault vault = new AgentVault(address(usdc), address(this), address(this), address(0xFEE));
        vault.setAsset(address(weth), address(wethFeed), true);
        vault.setAsset(address(pool), address(oracle), true);
        vault.setAdapter(address(adapter), true);
        vault.setDepositCaps(100_000e6, 100_000e6);
        usdc.mint(address(this), 10_000e6);
        usdc.approve(address(vault), 10_000e6);
        vault.deposit(10_000e6, address(this));

        vm.expectRevert(bytes("MV: per-trade cap"));
        vault.trade(address(adapter), address(usdc), address(pool), 1_001e6, 1);
    }
}
