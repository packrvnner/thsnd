// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Self-contained test suite (no forge-std dependency).
import {AgentVault} from "../src/milli/AgentVault.sol";
import {FeeSink} from "../src/milli/FeeSink.sol";
import {THSND} from "../src/THSND.sol";
import {LatticeLock} from "../src/LatticeLock.sol";
import {BurnEngine} from "../src/BurnEngine.sol";

// ---------------------------------------------------------------- cheatcodes
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

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
        totalSupply += amt;
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

/// Adapter mock: swaps at feed-implied fair value minus a configurable haircut.
contract MockAdapter {
    MockERC20 public usdc; // 6d
    MockERC20 public weth; // 18d
    MockFeed public wethFeed; // 8d USD
    uint256 public haircutBps; // simulated slippage

    constructor(MockERC20 _u, MockERC20 _w, MockFeed _f) {
        usdc = _u;
        weth = _w;
        wethFeed = _f;
    }

    function setHaircut(uint256 bps) external {
        haircutBps = bps;
    }

    function quoteOut(address tokenIn, uint256 amountIn) public view returns (uint256 out) {
        uint256 px = uint256(wethFeed.answer()); // 8d
        if (tokenIn == address(usdc)) {
            // USDC(6d) -> WETH(18d): out = in * 1e8/px * 1e12
            out = amountIn * 1e8 * 1e12 / px;
        } else {
            // WETH(18d) -> USDC(6d)
            out = amountIn * px / 1e8 / 1e12;
        }
        out = out * (10_000 - haircutBps) / 10_000;
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) external returns (uint256 out) {
        return _do(tokenIn, tokenOut, amountIn, minOut, msg.sender);
    }

    function swapExactInput(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut, address to)
        external
        returns (uint256 out)
    {
        return _do(tokenIn, tokenOut, amountIn, minOut, to);
    }

    function _do(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut, address to) internal returns (uint256 out) {
        MockERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        out = quoteOut(tokenIn, amountIn);
        require(out >= minOut, "MA: minOut");
        MockERC20(tokenOut).mint(to, out);
    }
}

/// Router mock for BurnEngine (buys THSND with WETH at fixed rate).
contract MockBurnRouter {
    THSND public thsnd;
    address public thsndHolder; // funds the "market"

    constructor(THSND _t, address holder) {
        thsnd = _t;
        thsndHolder = holder;
    }

    function swapExactInput(address, address, uint256 amountIn, uint256 minAmountOut, address recipient)
        external
        returns (uint256 amountOut)
    {
        // consume WETH from caller (approved), pay THSND from holder's allowance
        amountOut = amountIn * 1_000_000; // 1 WETH-wei -> 1e6 THSND-wei, arbitrary
        if (amountOut < minAmountOut) amountOut = minAmountOut;
        thsnd.transferFrom(thsndHolder, recipient, amountOut);
    }
}

// ================================================================ tests
contract MilliVaultTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    MockERC20 usdc;
    MockERC20 weth;
    MockFeed wethFeed;
    MockAdapter adapter;
    AgentVault vault;
    FeeSink sink;
    THSND thsnd;
    LatticeLock lattice;
    BurnEngine engine;
    MockBurnRouter burnRouter;

    address guardian = address(0xA11);
    address executor = address(0xE1);
    address alice = address(0xA1CE);
    address bob = address(0xB0B);
    address treasury = address(0x7EA);

    uint256 constant USDC_1 = 1e6;

    function setUp() public {
        usdc = new MockERC20("USDC", 6);
        weth = new MockERC20("WETH", 18);
        wethFeed = new MockFeed(2000e8, 8); // WETH = $2000
        adapter = new MockAdapter(usdc, weth, wethFeed);

        thsnd = new THSND(address(this));
        lattice = new LatticeLock(address(thsnd), address(weth));
        engine = new BurnEngine(address(thsnd));
        burnRouter = new MockBurnRouter(thsnd, address(this));
        thsnd.approve(address(burnRouter), type(uint256).max);
        engine.setRoute(address(weth), address(burnRouter));
        engine.setKeeper(address(this), true);

        sink = new FeeSink(address(usdc), address(weth), address(lattice), address(engine), treasury);
        vault = new AgentVault(address(usdc), guardian, executor, address(sink));
        sink.setVault(address(vault));
        sink.setKeeper(address(this), true);
        lattice.setFeeNotifier(address(sink));

        vm.startPrank(guardian);
        vault.setAsset(address(weth), address(wethFeed), true);
        vault.setAdapter(address(adapter), true);
        vault.setDepositCaps(1e30, 1e30); // lift launch caps for mechanics tests; defaults tested separately
        vm.stopPrank();

        usdc.mint(alice, 1_000_000 * USDC_1);
        usdc.mint(bob, 1_000_000 * USDC_1);

        // a locker exists so notifyReward works end-to-end
        thsnd.transfer(alice, 1_000e18);
        vm.startPrank(alice);
        thsnd.approve(address(lattice), type(uint256).max);
        lattice.lock(1_000e18, 208 weeks);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- helpers
    function _dep(address who, uint256 amt) internal returns (uint256 shares) {
        vm.startPrank(who);
        usdc.approve(address(vault), amt);
        shares = vault.deposit(amt, who);
        vm.stopPrank();
    }

    function assertEq(uint256 a, uint256 b, string memory m) internal pure {
        require(a == b, m);
    }

    function assertApprox(uint256 a, uint256 b, uint256 tolBps, string memory m) internal pure {
        uint256 diff = a > b ? a - b : b - a;
        require(diff * 10_000 <= (b == 0 ? 1 : b) * tolBps, m);
    }

    // ---------------------------------------------------------------- share math
    function test_DepositMintsExpectedShares() public {
        uint256 shares = _dep(alice, 100 * USDC_1);
        assertApprox(shares, 100e18, 1, "1 USDC should mint ~1e18 shares at genesis");
        assertEq(vault.totalAssets(), 100 * USDC_1, "NAV");
    }

    function test_RedeemRoundTripMinusExitFee() public {
        uint256 shares = _dep(alice, 100 * USDC_1);
        uint256 balBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        uint256 net = vault.redeem(shares, alice, alice);
        // 0.25% exit fee
        assertApprox(net, 100 * USDC_1 * 9975 / 10_000, 2, "net of exit fee");
        assertEq(usdc.balanceOf(alice) - balBefore, net, "received");
        assertApprox(usdc.balanceOf(address(sink)), 100 * USDC_1 * 25 / 10_000, 2, "sink got fee");
    }

    function test_TwoDepositorsProportional() public {
        _dep(alice, 100 * USDC_1);
        // NAV doubles via donation (simulates PnL)
        usdc.mint(address(vault), 100 * USDC_1);
        uint256 bobShares = _dep(bob, 100 * USDC_1);
        // bob should get ~half of alice's shares
        assertApprox(bobShares, 50e18, 5, "bob shares at 2x pps");
    }

    function test_InflationAttackBlunted() public {
        // attacker deposits dust then donates to skew pps before victim deposit
        _dep(alice, 1); // 1e-6 USDC
        usdc.mint(address(vault), 10_000 * USDC_1); // big donation
        uint256 bobShares = _dep(bob, 100 * USDC_1);
        require(bobShares > 0, "victim must not be zeroed");
        vm.prank(bob);
        uint256 back = vault.redeem(bobShares, bob, bob);
        // bob keeps >= ~98% of his deposit (offset makes the attack uneconomic)
        require(back >= 98 * USDC_1, "victim loss too large");
    }

    // ---------------------------------------------------------------- trading rails
    function test_TradeHappyPathAndNAV() public {
        _dep(alice, 1_000 * USDC_1);
        vm.prank(executor);
        uint256 out = vault.trade(address(adapter), address(usdc), address(weth), 100 * USDC_1, 1);
        require(out > 0, "got WETH");
        assertApprox(vault.totalAssets(), 1_000 * USDC_1, 5, "NAV preserved at fair swap");
    }

    function test_TradeReverts_NotExecutor() public {
        _dep(alice, 1_000 * USDC_1);
        vm.expectRevert(bytes("MV: not executor"));
        vault.trade(address(adapter), address(usdc), address(weth), 100 * USDC_1, 1);
    }

    function test_TradeReverts_Paused_ButWithdrawWorks() public {
        _dep(alice, 1_000 * USDC_1);
        vm.prank(guardian);
        vault.setTradingPaused(true);
        vm.prank(executor);
        vm.expectRevert(bytes("MV: trading paused"));
        vault.trade(address(adapter), address(usdc), address(weth), 100 * USDC_1, 1);
        // withdrawals immune to the breaker
        uint256 balBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        uint256 shares = vault.withdraw(500 * USDC_1, alice, alice);
        require(shares > 0, "shares burned");
        assertEq(usdc.balanceOf(alice) - balBefore, 500 * USDC_1, "net received while paused");
    }

    function test_TradeReverts_PerTradeCap() public {
        _dep(alice, 1_000 * USDC_1);
        vm.prank(executor);
        vm.expectRevert(bytes("MV: per-trade cap"));
        vault.trade(address(adapter), address(usdc), address(weth), 200 * USDC_1, 1); // >10%
    }

    function test_TradeReverts_DailyCap() public {
        _dep(alice, 1_000 * USDC_1);
        vm.prank(guardian);
        vault.setCaps(1_000, 2_500, 100, 2_000, 1 days); // daily cap = 25% NAV = 250 USDC
        vm.startPrank(executor);
        vault.trade(address(adapter), address(usdc), address(weth), 100 * USDC_1, 1); // t=100
        vault.trade(address(adapter), address(usdc), address(weth), 100 * USDC_1, 1); // t=200
        vm.expectRevert(bytes("MV: daily cap"));
        vault.trade(address(adapter), address(usdc), address(weth), 100 * USDC_1, 1); // t=300 > 250
        vm.stopPrank();
    }

    function test_DailyCapResetsNextDay() public {
        _dep(alice, 1_000 * USDC_1);
        vm.prank(guardian);
        vault.setCaps(1_000, 2_500, 100, 2_000, 1 days);
        vm.startPrank(executor);
        vault.trade(address(adapter), address(usdc), address(weth), 100 * USDC_1, 1);
        vault.trade(address(adapter), address(usdc), address(weth), 100 * USDC_1, 1);
        vm.stopPrank();
        vm.warp(block.timestamp + 1 days);
        vm.prank(executor);
        vault.trade(address(adapter), address(usdc), address(weth), 100 * USDC_1, 1); // fresh window
    }

    function test_TradeReverts_ValueSlippage() public {
        _dep(alice, 1_000 * USDC_1);
        adapter.setHaircut(200); // 2% > 1% cap
        vm.prank(executor);
        vm.expectRevert(bytes("MV: value slippage"));
        vault.trade(address(adapter), address(usdc), address(weth), 100 * USDC_1, 1);
    }

    function test_TradeReverts_UnlistedTokenAndAdapter() public {
        _dep(alice, 1_000 * USDC_1);
        MockERC20 rogue = new MockERC20("RGE", 18);
        vm.prank(executor);
        vm.expectRevert(bytes("MV: tokenOut unlisted"));
        vault.trade(address(adapter), address(usdc), address(rogue), 10 * USDC_1, 1);
        vm.prank(executor);
        vm.expectRevert(bytes("MV: bad adapter"));
        vault.trade(address(0xDEAD), address(usdc), address(weth), 10 * USDC_1, 1);
    }

    function test_CashBuffer_BlocksDeepBuys_AllowsSells() public {
        _dep(alice, 1_000 * USDC_1);
        vm.prank(guardian);
        vault.setCaps(2_000, 10_000, 100, 2_000, 1 days); // perTrade 20%, buffer 20%
        vm.startPrank(executor);
        for (uint256 i = 0; i < 5; i++) {
            vault.trade(address(adapter), address(usdc), address(weth), 150 * USDC_1, 1); // USDC: 1000→250
        }
        // next buy would leave ~100 USDC < 20% buffer
        vm.expectRevert(bytes("MV: cash buffer"));
        vault.trade(address(adapter), address(usdc), address(weth), 150 * USDC_1, 1);
        // selling back to USDC always allowed (still per-trade capped, so sell a slice)
        uint256 wbal = weth.balanceOf(address(vault));
        vault.trade(address(adapter), address(weth), address(usdc), wbal / 8, 1);
        vm.stopPrank();
    }

    function test_StaleFeed_BlocksTrade_WithdrawStillWorksWhenCash() public {
        vm.warp(block.timestamp + 3 days); // move off genesis so staleness math can't underflow
        _dep(alice, 1_000 * USDC_1);
        wethFeed.setStale(block.timestamp - 2 days);
        vm.prank(executor);
        vm.expectRevert(bytes("MV: stale feed"));
        vault.trade(address(adapter), address(usdc), address(weth), 100 * USDC_1, 1);
        // all-cash vault: NAV needs no feed, withdraw fine
        vm.prank(alice);
        vault.withdraw(100 * USDC_1, alice, alice);
    }

    function test_EmergencyUnwind_OnlyPausedOnlyGuardianToUSDC() public {
        _dep(alice, 1_000 * USDC_1);
        vm.prank(executor);
        vault.trade(address(adapter), address(usdc), address(weth), 100 * USDC_1, 1);
        vm.prank(guardian);
        vm.expectRevert(bytes("MV: pause first"));
        vault.emergencyUnwind(address(adapter), address(weth), 1e16, 1);
        vm.prank(guardian);
        vault.setTradingPaused(true);
        vm.prank(executor);
        vm.expectRevert(bytes("MV: not guardian"));
        vault.emergencyUnwind(address(adapter), address(weth), 1e16, 1);
        uint256 wbal = weth.balanceOf(address(vault)); // read BEFORE prank (prank binds to next call)
        vm.prank(guardian);
        vault.emergencyUnwind(address(adapter), address(weth), wbal, 1);
        assertEq(weth.balanceOf(address(vault)), 0, "fully unwound");
    }

    // ---------------------------------------------------------------- fees
    function test_ManagementFeeStreams() public {
        _dep(alice, 1_000 * USDC_1);
        uint256 supply0 = vault.totalSupply();
        vm.warp(block.timestamp + 365 days);
        vault.crystallize(); // triggers accrue
        uint256 sinkShares = vault.balanceOf(address(sink));
        // 2% of supply over a year (of the growing supply — approx within 3%)
        assertApprox(sinkShares, supply0 * 200 / 10_000, 300, "mgmt dilution ~2%");
    }

    function test_PerformanceFeeHWM_NoDoubleCharge() public {
        _dep(alice, 1_000 * USDC_1);
        // +20% PnL via donation
        usdc.mint(address(vault), 200 * USDC_1);
        vault.crystallize();
        uint256 sinkAfter1 = vault.balanceOf(address(sink));
        require(sinkAfter1 > 0, "perf fee minted");
        // crystallize again with no new profit — nothing further
        vault.crystallize();
        assertEq(vault.balanceOf(address(sink)), sinkAfter1, "no double charge");
        // value of sink shares ~ 15% of 200 USDC profit (standard post-mint dilution ≈2.4%)
        uint256 sinkValue = vault.convertToAssets(sinkAfter1);
        assertApprox(sinkValue, 30 * USDC_1, 300, "perf ~= 15% of profit");
    }

    function test_PerfFee_NotChargedUnderHWM() public {
        _dep(alice, 1_000 * USDC_1);
        usdc.mint(address(vault), 200 * USDC_1);
        vault.crystallize();
        uint256 s1 = vault.balanceOf(address(sink));
        // drawdown below HWM, then partial recovery still below HWM
        vm.prank(address(vault));
        usdc.transfer(address(0xD0), 300 * USDC_1); // simulate loss
        vault.crystallize();
        assertEq(vault.balanceOf(address(sink)), s1, "no fee in drawdown");
        usdc.mint(address(vault), 50 * USDC_1); // recover a bit, still < HWM
        vault.crystallize();
        assertEq(vault.balanceOf(address(sink)), s1, "no fee under HWM");
    }

    function test_FeeBounds() public {
        vm.prank(guardian);
        vm.expectRevert(bytes("MV: fee bounds"));
        vault.setFees(301, 1_500, 25);
        vm.prank(executor);
        vm.expectRevert(bytes("MV: not guardian"));
        vault.setFees(100, 1_000, 10);
    }

    // ---------------------------------------------------------------- fee sink end-to-end
    function test_SinkDistribute_LockersBurnTreasury() public {
        _dep(alice, 10_000 * USDC_1);
        // accrue a year of mgmt fees then convert
        vm.warp(block.timestamp + 365 days);
        vault.crystallize();
        sink.redeemShares(0); // all
        uint256 pot = usdc.balanceOf(address(sink));
        require(pot > 0, "pot funded");

        uint256 burnedBefore = thsnd.totalBurned();
        sink.distribute(address(adapter), 1);

        // lockers: WETH landed in LatticeLock and is claimable by alice
        uint256 earned = lattice.earned(alice);
        require(earned > 0, "locker earns WETH");
        // treasury got its USDC slice
        assertApprox(usdc.balanceOf(treasury), pot * 2_000 / 10_000, 5, "treasury 20%");
        // burn engine holds WETH → execute burns THSND
        require(weth.balanceOf(address(engine)) > 0, "engine funded");
        engine.execute(address(weth), 1);
        require(thsnd.totalBurned() > burnedBefore, "THSND burned");
    }

    function test_SinkSplitBounds() public {
        vm.expectRevert(bytes("FS: lockers floor"));
        sink.setSplit(3_000, 4_000, 3_000);
        vm.expectRevert(bytes("FS: sum"));
        sink.setSplit(5_000, 3_000, 1_000);
        vm.expectRevert(bytes("FS: treasury ceiling"));
        sink.setSplit(4_000, 2_500, 3_500);
        sink.setSplit(6_000, 3_000, 1_000); // valid
    }

    // ---------------------------------------------------------------- guardian limits
    function test_RemoveAssetRequiresZeroBalance() public {
        _dep(alice, 1_000 * USDC_1);
        vm.prank(executor);
        vault.trade(address(adapter), address(usdc), address(weth), 100 * USDC_1, 1);
        vm.prank(guardian);
        vm.expectRevert(bytes("MV: balance not zero"));
        vault.setAsset(address(weth), address(wethFeed), false);
    }

    function test_LaunchDepositCaps_Defaults() public {
        // fresh vault keeps the shipped defaults: 25k vault / 2k wallet
        AgentVault fresh = new AgentVault(address(usdc), guardian, executor, address(sink));
        vm.startPrank(alice);
        usdc.approve(address(fresh), type(uint256).max);
        fresh.deposit(2_000 * USDC_1, alice); // exactly at wallet cap: ok
        vm.expectRevert(bytes("MV: wallet cap"));
        fresh.deposit(1 * USDC_1, alice);
        vm.stopPrank();
        // fill toward the vault cap with distinct wallets
        for (uint256 i = 1; i <= 11; i++) {
            address w = address(uint160(0xF000 + i));
            usdc.mint(w, 2_000 * USDC_1);
            vm.startPrank(w);
            usdc.approve(address(fresh), type(uint256).max);
            if (i <= 11 && fresh.totalAssets() + 2_000 * USDC_1 <= 25_000 * USDC_1) {
                fresh.deposit(2_000 * USDC_1, w);
            } else {
                vm.expectRevert(bytes("MV: vault cap"));
                fresh.deposit(2_000 * USDC_1, w);
            }
            vm.stopPrank();
        }
        require(fresh.totalAssets() <= 25_000 * USDC_1, "vault cap held");
        // guardian can raise; others cannot
        vm.prank(executor);
        vm.expectRevert(bytes("MV: not guardian"));
        fresh.setDepositCaps(100_000 * USDC_1, 5_000 * USDC_1);
        vm.prank(guardian);
        fresh.setDepositCaps(100_000 * USDC_1, 5_000 * USDC_1);
        vm.startPrank(alice);
        fresh.deposit(3_000 * USDC_1, alice); // now allowed under raised wallet cap
        vm.stopPrank();
    }

    function test_PreviewsMatchActions() public {
        _dep(alice, 500 * USDC_1);
        usdc.mint(address(vault), 137 * USDC_1); // odd pps
        uint256 pDep = vault.previewDeposit(50 * USDC_1);
        uint256 got = _dep(bob, 50 * USDC_1);
        assertEq(got, pDep, "previewDeposit");
        uint256 pRed = vault.previewRedeem(got);
        vm.prank(bob);
        uint256 net = vault.redeem(got, bob, bob);
        assertEq(net, pRed, "previewRedeem");
    }
}
