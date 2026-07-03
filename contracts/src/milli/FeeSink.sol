// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// ---------------------------------------------------------------------
///  FeeSink — MILLI fee splitter
///
///  Receives: mTHSND shares (mgmt + performance dilution) and USDC (exit
///  fees). A keeper converts and distributes on a fixed split:
///
///    lockersBps  → USDC→WETH → LatticeLock.notifyReward()   (vTHSND lockers)
///    burnBps     → USDC→WETH → BurnEngine (its keeper buys+burns THSND)
///    treasuryBps → USDC      → treasury Safe (ops)
///
///  Deployment wiring (from the Safe):
///   - LatticeLock.setFeeNotifier(feeSink)
///   - BurnEngine.setRoute(WETH, aeroAdapter)  + setKeeper(agent keeper)
///  Split is owner-tunable within: lockers >= 40%, burn >= 10%, treasury <= 30%.
/// ---------------------------------------------------------------------

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
}

interface IVaultShares {
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
    function balanceOf(address) external view returns (uint256);
}

interface IRouteAdapter {
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) external returns (uint256 out);
}

interface ILatticeLock {
    function notifyReward(uint256 amount) external;
}

contract FeeSink {
    address public owner;      // treasury Safe
    address public treasury;   // ops receiver (usually same Safe)
    mapping(address => bool) public isKeeper;

    IERC20 public immutable usdc;
    IERC20 public immutable weth;
    IVaultShares public agentVault;          // mTHSND
    ILatticeLock public immutable lattice;   // vTHSND fee stream
    address public immutable burnEngine;

    uint16 public lockersBps = 5_000;  // 50%
    uint16 public burnBps = 3_000;     // 30%
    uint16 public treasuryBps = 2_000; // 20%

    event Redeemed(uint256 shares, uint256 usdcOut);
    event Distributed(uint256 usdcIn, uint256 wethToLockers, uint256 wethToBurn, uint256 usdcToTreasury);
    event SplitSet(uint16 lockers, uint16 burn, uint16 treasury);
    event KeeperSet(address keeper, bool enabled);
    event VaultSet(address vault);

    modifier onlyOwner() {
        require(msg.sender == owner, "FS: not owner");
        _;
    }

    modifier onlyKeeper() {
        require(isKeeper[msg.sender] || msg.sender == owner, "FS: not keeper");
        _;
    }

    constructor(address _usdc, address _weth, address _lattice, address _burnEngine, address _treasury) {
        require(_usdc != address(0) && _weth != address(0) && _lattice != address(0) && _burnEngine != address(0) && _treasury != address(0), "FS: zero addr");
        owner = msg.sender;
        usdc = IERC20(_usdc);
        weth = IERC20(_weth);
        lattice = ILatticeLock(_lattice);
        burnEngine = _burnEngine;
        treasury = _treasury;
    }

    // ---------------------------------------------------------------- Admin
    function setVault(address v) external onlyOwner {
        require(v != address(0), "FS: zero vault");
        agentVault = IVaultShares(v);
        emit VaultSet(v);
    }

    function setKeeper(address k, bool enabled) external onlyOwner {
        isKeeper[k] = enabled;
        emit KeeperSet(k, enabled);
    }

    function setSplit(uint16 _lockers, uint16 _burn, uint16 _treasury) external onlyOwner {
        require(_lockers + _burn + _treasury == 10_000, "FS: sum");
        require(_lockers >= 4_000, "FS: lockers floor");
        require(_burn >= 1_000, "FS: burn floor");
        require(_treasury <= 3_000, "FS: treasury ceiling");
        lockersBps = _lockers;
        burnBps = _burn;
        treasuryBps = _treasury;
        emit SplitSet(_lockers, _burn, _treasury);
    }

    function setTreasury(address t) external onlyOwner {
        require(t != address(0), "FS: zero treasury");
        treasury = t;
    }

    function transferOwnership(address n) external onlyOwner {
        require(n != address(0), "FS: zero owner");
        owner = n;
    }

    // ---------------------------------------------------------------- Ops
    /// @notice Convert accumulated mTHSND fee shares to USDC (at NAV, no slippage).
    function redeemShares(uint256 shares) external onlyKeeper returns (uint256 usdcOut) {
        if (shares == 0) shares = agentVault.balanceOf(address(this));
        require(shares > 0, "FS: no shares");
        usdcOut = agentVault.redeem(shares, address(this), address(this));
        emit Redeemed(shares, usdcOut);
    }

    /// @notice Split and distribute the entire USDC pot.
    /// @param adapter whitelisted route adapter for USDC→WETH
    /// @param minWethTotal slippage floor for the combined WETH leg
    function distribute(address adapter, uint256 minWethTotal) external onlyKeeper {
        uint256 pot = usdc.balanceOf(address(this));
        require(pot > 0, "FS: empty pot");

        uint256 tPart = pot * treasuryBps / 10_000;
        uint256 wethLeg = pot - tPart;

        uint256 wethOut = 0;
        if (wethLeg > 0) {
            require(usdc.approve(adapter, wethLeg), "FS: approve");
            wethOut = IRouteAdapter(adapter).swap(address(usdc), address(weth), wethLeg, minWethTotal);
            require(usdc.approve(adapter, 0), "FS: unapprove");
        }

        // lockers : burn share of the WETH leg (relative to their combined bps)
        uint256 lockersWeth = wethOut * lockersBps / (lockersBps + burnBps);
        uint256 burnWeth = wethOut - lockersWeth;

        if (lockersWeth > 0) {
            require(weth.approve(address(lattice), lockersWeth), "FS: lattice approve");
            lattice.notifyReward(lockersWeth); // requires Safe: lattice.setFeeNotifier(this)
        }
        if (burnWeth > 0) {
            require(weth.transfer(burnEngine, burnWeth), "FS: burn transfer");
            // BurnEngine keeper calls execute(WETH, minTHSNDOut) → market-buy + burn
        }
        if (tPart > 0) {
            require(usdc.transfer(treasury, tPart), "FS: treasury transfer");
        }
        emit Distributed(pot, lockersWeth, burnWeth, tPart);
    }
}
