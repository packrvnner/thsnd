// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {THSND} from "../src/THSND.sol";
import {LatticeLock} from "../src/LatticeLock.sol";
import {BurnEngine, ISwapRouter} from "../src/BurnEngine.sol";
import {TierRegistry} from "../src/TierRegistry.sol";

contract MockToken {
    string public name;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name) { name = _name; }
    function mint(address to, uint256 amt) external { balanceOf[to] += amt; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        allowance[f][msg.sender] -= a; balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

/// Mock router: swaps 1 asset -> 2 MUY (pretends deep liquidity).
contract MockRouter is ISwapRouter {
    THSND public muy;
    constructor(THSND _muy) { muy = _muy; }
    function swapExactInput(address, address, uint256 amountIn, uint256 minOut, address recipient)
        external
        returns (uint256 out)
    {
        out = amountIn * 2;
        require(out >= minOut, "router: slippage");
        muy.transfer(recipient, out); // router pre-funded with MUY in setUp
    }
}

contract THSNDTest is Test {
    THSND muy;
    LatticeLock lock;
    BurnEngine engine;
    TierRegistry tiers;
    MockToken weth;
    MockToken collateral;
    MockRouter router;

    address treasury = makeAddr("treasury");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address keeper = makeAddr("keeper");

    function setUp() public {
        muy = new THSND(treasury);
        weth = new MockToken("WETH");
        collateral = new MockToken("cbBTC");
        lock = new LatticeLock(address(muy), address(weth));
        engine = new BurnEngine(address(muy));
        tiers = new TierRegistry(address(muy), address(lock));
        router = new MockRouter(muy);

        engine.setKeeper(keeper, true);
        engine.setRoute(address(collateral), address(router));
        lock.setFeeNotifier(address(this));

        vm.startPrank(treasury);
        muy.transfer(alice, 2_000_000e18);
        muy.transfer(bob, 500_000e18);
        muy.transfer(address(router), 10_000_000e18); // router "liquidity"
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- Token
    function test_genesisSupplyAndNoMint() public view {
        assertEq(muy.totalSupply(), 1_000_000_000e18);
        // no mint function exists — nothing to test beyond compilation.
    }

    function test_burnReducesSupplyForever() public {
        vm.prank(alice);
        muy.burn(1_000e18);
        assertEq(muy.totalSupply(), 1_000_000_000e18 - 1_000e18);
        assertEq(muy.totalBurned(), 1_000e18);
    }

    function testFuzz_transfer(uint96 amt) public {
        vm.assume(amt <= 2_000_000e18);
        vm.prank(alice);
        muy.transfer(bob, amt);
        assertEq(muy.balanceOf(bob), 500_000e18 + amt);
    }

    // ---------------------------------------------------------------- LatticeLock
    function test_lockGrantsPowerAndFeeShare() public {
        vm.startPrank(alice);
        muy.approve(address(lock), 1_000_000e18);
        lock.lock(1_000_000e18, lock.MAX_LOCK());
        vm.stopPrank();

        assertEq(lock.votingPower(alice), 1_000_000e18); // max lock = 1:1

        // push 10 WETH of fees
        weth.mint(address(this), 10e18);
        weth.approve(address(lock), 10e18);
        lock.notifyReward(10e18);

        assertEq(lock.earned(alice), 10e18); // sole locker gets everything
        vm.prank(alice);
        lock.claim();
        assertEq(weth.balanceOf(alice), 10e18);
    }

    function test_cannotWithdrawEarly() public {
        vm.startPrank(alice);
        muy.approve(address(lock), 100e18);
        lock.lock(100e18, 52 weeks);
        vm.expectRevert("LL: still locked");
        lock.withdraw();
        vm.stopPrank();
    }

    function test_withdrawAfterExpiry() public {
        vm.startPrank(alice);
        muy.approve(address(lock), 100e18);
        lock.lock(100e18, 1 weeks);
        vm.stopPrank();

        skip(1 weeks + 1);
        uint256 before = muy.balanceOf(alice);
        vm.prank(alice);
        lock.withdraw();
        assertEq(muy.balanceOf(alice), before + 100e18);
        assertEq(lock.totalPower(), 0);
    }

    // ---------------------------------------------------------------- BurnEngine
    function test_liquidationSliceBuysAndBurns() public {
        // Strata liquidation pushes 1.5% slice of seized collateral:
        collateral.mint(address(engine), 15e18);

        uint256 supplyBefore = muy.totalSupply();
        vm.prank(keeper);
        uint256 burned = engine.execute(address(collateral), 25e18);

        assertEq(burned, 30e18); // mock: 2x
        assertEq(muy.totalSupply(), supplyBefore - 30e18);
        assertEq(engine.totalMuyBurned(), 30e18);
    }

    function test_engineRejectsUnroutedAssetAndNonKeeper() public {
        MockToken junk = new MockToken("JUNK");
        junk.mint(address(engine), 1e18);
        vm.prank(keeper);
        vm.expectRevert("BE: no route");
        engine.execute(address(junk), 1);

        collateral.mint(address(engine), 1e18);
        vm.prank(alice);
        vm.expectRevert("BE: not keeper");
        engine.execute(address(collateral), 1);
    }

    function test_muyCanNeverLeaveEngineExceptByBurn() public {
        vm.prank(treasury);
        muy.transfer(address(engine), 1_000e18);
        vm.expectRevert("BE: THSND only burns");
        engine.sweep(address(muy), address(this));

        uint256 supplyBefore = muy.totalSupply();
        engine.burnDirect();
        assertEq(muy.totalSupply(), supplyBefore - 1_000e18);
    }

    // ---------------------------------------------------------------- Tiers
    function test_tiers() public view {
        // bob: 500,000 wallet MUY -> tier 2 (>=100k, <1M)
        assertEq(tiers.tierOf(bob), 2);
        assertEq(tiers.discountOf(bob), 5_000);
        // alice: 2,000,000 wallet -> tier 3
        assertEq(tiers.tierOf(alice), 3);
        assertEq(tiers.discountOf(alice), 10_000);
    }

    function test_lockCountsDouble() public {
        address carol = makeAddr("carol");
        vm.prank(treasury);
        muy.transfer(carol, 5_000e18);
        vm.startPrank(carol);
        muy.approve(address(lock), 5_000e18);
        lock.lock(5_000e18, 52 weeks);
        vm.stopPrank();
        // 0 wallet + 5,000 * 2 = 10,000 effective -> tier 1
        assertEq(tiers.effectiveBalance(carol), 10_000e18);
        assertEq(tiers.tierOf(carol), 1);
    }
}
