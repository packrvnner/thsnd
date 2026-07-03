// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// ---------------------------------------------------------------------
///  MILLI — AgentVault (mTHSND)
///
///  ERC-4626 vault, asset = USDC. An off-chain agent trades the portfolio
///  24/7 through a whitelisted, capped `trade()` — every holding and every
///  trade is public by construction because the portfolio IS this address.
///
///  Trust invariants (enforced by code, disclosed on thsnd.xyz/#docs):
///   - Deposits and withdrawals can NEVER be paused. The circuit breaker
///     halts trading only.
///   - The executor (agent key) can only swap whitelisted assets through
///     whitelisted adapters within caps. It cannot transfer assets out.
///   - The guardian (treasury Safe) manages whitelists/caps/executor and
///     the trading pause. It has no path to depositor funds.
///   - Fees are deterministic: management (streamed), performance (high-
///     water mark), exit. Bounds are hard-capped in code.
///
///  Known v1 limitations (accepted + disclosed, revisit at audit):
///   - NAV depends on Chainlink feeds while non-USDC assets are held; a
///     stale feed blocks trading and can distort withdrawal NAV. The cash
///     buffer + emergencyUnwind are the mitigations.
///   - Withdrawals draw from the USDC balance; the buffer requirement
///     keeps an exit lane open but a full-vault exit may require unwind.
/// ---------------------------------------------------------------------

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IPriceFeed {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function decimals() external view returns (uint8);
}

interface IRouteAdapter {
    /// @notice Pulls `amountIn` of tokenIn from msg.sender, swaps, sends >= minOut of tokenOut back to msg.sender.
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) external returns (uint256 out);
}

contract AgentVault {
    // ---------------------------------------------------------------- ERC-20 (shares)
    string public constant name = "MILLI Agent Vault";
    string public constant symbol = "mTHSND";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // 4626 virtual-offset inflation defense: USDC is 6 dec, shares 18 dec.
    uint256 private constant OFFSET = 1e12;

    // ---------------------------------------------------------------- Roles
    address public guardian;      // treasury Safe
    address public executor;      // agent hot key — trade() only
    address public feeSink;       // receives fee shares + exit fees
    bool public tradingPaused;

    // ---------------------------------------------------------------- Portfolio
    IERC20 public immutable usdc;

    struct AssetCfg {
        IPriceFeed feed;   // Chainlink-style USD feed
        uint8 assetDec;
        uint8 feedDec;
        bool listed;
    }
    address[] public assetList;
    mapping(address => AssetCfg) public assets;
    mapping(address => bool) public adapters;

    // ---------------------------------------------------------------- Caps (bps of NAV unless noted)
    uint16 public perTradeBps = 1_000;      // max 10% NAV per trade
    uint16 public dailyTurnoverBps = 5_000; // max 50% NAV per day
    uint16 public maxSlippageBps = 100;     // oracle-value slippage, 1%
    uint16 public cashBufferBps = 2_000;    // keep >= 20% NAV in USDC after buys
    uint32 public maxFeedAge = 1 days;
    mapping(uint256 => uint256) public turnoverByDay; // day => USDC value traded

    // hard ceilings (immutable safety rails on the guardian itself)
    uint16 public constant MAX_MGMT_BPS = 300;    // 3%/yr
    uint16 public constant MAX_PERF_BPS = 3_000;  // 30%
    uint16 public constant MAX_EXIT_BPS = 100;    // 1%
    uint16 public constant MAX_SLIPPAGE_CEIL = 300;
    uint16 public constant MAX_PER_TRADE_CEIL = 2_500;

    // ---------------------------------------------------------------- Launch caps (inflow control — protects strangers from unaudited code;
    // withdrawals are never gated. Guardian raises these as the track record and audit land.)
    uint256 public depositCap = 25_000e6;   // max vault TVL accepting new deposits (USDC, 6d)
    uint256 public perWalletCap = 2_000e6;  // max value a single receiver may hold (USDC, 6d)

    // ---------------------------------------------------------------- Fees
    uint16 public mgmtFeeBps = 200;  // 2%/yr, streamed as share dilution
    uint16 public perfFeeBps = 1_500; // 15% over high-water mark
    uint16 public exitFeeBps = 25;   // 0.25%
    uint64 public lastAccrual;       // mgmt fee timestamp
    uint256 public highWaterMark;    // assets (6d) per 1e18 shares

    // ---------------------------------------------------------------- Events
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Trade(address indexed adapter, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, uint256 valueIn6);
    event ManagementAccrued(uint256 feeShares);
    event Crystallized(uint256 ppsBefore, uint256 hwm, uint256 feeShares);
    event ExitFeePaid(address indexed owner, uint256 feeAssets);
    event AssetSet(address indexed token, address feed, bool listed);
    event AdapterSet(address indexed adapter, bool allowed);
    event CapsSet(uint16 perTrade, uint16 daily, uint16 slippage, uint16 buffer, uint32 feedAge);
    event FeesSet(uint16 mgmt, uint16 perf, uint16 exitFee);
    event RolesSet(address guardian, address executor, address feeSink);
    event TradingPaused(bool paused);
    event EmergencyUnwind(address indexed tokenIn, uint256 amountIn, uint256 usdcOut);

    // ---------------------------------------------------------------- Modifiers
    uint256 private _lock = 1;
    modifier nonReentrant() {
        require(_lock == 1, "MV: reentrancy");
        _lock = 2;
        _;
        _lock = 1;
    }

    modifier onlyGuardian() {
        require(msg.sender == guardian, "MV: not guardian");
        _;
    }

    modifier accrue() {
        _accrueManagement();
        _;
    }

    constructor(address _usdc, address _guardian, address _executor, address _feeSink) {
        require(_usdc != address(0) && _guardian != address(0) && _feeSink != address(0), "MV: zero addr");
        usdc = IERC20(_usdc);
        guardian = _guardian;
        executor = _executor;
        feeSink = _feeSink;
        lastAccrual = uint64(block.timestamp);
        highWaterMark = 1e6; // 1 USDC per 1e18 shares at genesis
    }

    // ================================================================ ERC-20
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        if (a != type(uint256).max) {
            require(a >= amount, "MV: allowance");
            allowance[from][msg.sender] = a - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "MV: to zero");
        uint256 b = balanceOf[from];
        require(b >= amount, "MV: balance");
        unchecked {
            balanceOf[from] = b - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        uint256 b = balanceOf[from];
        require(b >= amount, "MV: burn balance");
        unchecked {
            balanceOf[from] = b - amount;
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }

    // ================================================================ NAV
    /// @notice Total portfolio value in USDC terms (6 decimals). USDC counts 1:1.
    function totalAssets() public view returns (uint256 nav) {
        nav = usdc.balanceOf(address(this));
        uint256 n = assetList.length;
        for (uint256 i = 0; i < n; i++) {
            address t = assetList[i];
            uint256 bal = IERC20(t).balanceOf(address(this));
            if (bal == 0) continue;
            nav += _value6(t, bal);
        }
    }

    function _price(address token) internal view returns (uint256 px, uint8 feedDec) {
        AssetCfg memory c = assets[token];
        require(c.listed, "MV: unlisted");
        (, int256 answer,, uint256 updatedAt,) = c.feed.latestRoundData();
        require(answer > 0, "MV: bad price");
        require(block.timestamp - updatedAt <= maxFeedAge, "MV: stale feed");
        return (uint256(answer), c.feedDec);
    }

    /// @dev USD value (6 dec) of `amount` of `token`. USDC is identity.
    function _value6(address token, uint256 amount) internal view returns (uint256) {
        if (token == address(usdc)) return amount;
        AssetCfg memory c = assets[token];
        (uint256 px, uint8 fd) = _price(token);
        // amount(assetDec) * px(feedDec) -> 6 dec
        return amount * px / (10 ** (uint256(c.assetDec) + fd - 6));
    }

    // ================================================================ ERC-4626 core
    function asset() external view returns (address) {
        return address(usdc);
    }

    function convertToShares(uint256 assets_) public view returns (uint256) {
        return assets_ * (totalSupply + OFFSET) / (totalAssets() + 1);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return shares * (totalAssets() + 1) / (totalSupply + OFFSET);
    }

    function previewDeposit(uint256 assets_) public view returns (uint256) {
        return convertToShares(assets_);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        return _ceilDiv(shares * (totalAssets() + 1), totalSupply + OFFSET);
    }

    /// @notice `assets_` here is the NET amount the receiver wants out.
    function previewWithdraw(uint256 assets_) public view returns (uint256 shares) {
        uint256 gross = _grossFromNet(assets_);
        return _ceilDiv(gross * (totalSupply + OFFSET), totalAssets() + 1);
    }

    function previewRedeem(uint256 shares) public view returns (uint256 netAssets) {
        uint256 gross = convertToAssets(shares);
        return gross - (gross * exitFeeBps / 10_000);
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf[owner];
    }

    function deposit(uint256 assets_, address receiver) external nonReentrant accrue returns (uint256 shares) {
        require(assets_ > 0, "MV: zero assets");
        shares = convertToShares(assets_);
        require(shares > 0, "MV: zero shares");
        _checkCaps(receiver, assets_);
        _safeTransferFrom(address(usdc), msg.sender, address(this), assets_);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets_, shares);
    }

    function mint(uint256 shares, address receiver) external nonReentrant accrue returns (uint256 assets_) {
        require(shares > 0, "MV: zero shares");
        assets_ = previewMint(shares);
        _checkCaps(receiver, assets_);
        _safeTransferFrom(address(usdc), msg.sender, address(this), assets_);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets_, shares);
    }

    function _checkCaps(address receiver, uint256 assetsIn) internal view {
        require(totalAssets() + assetsIn <= depositCap, "MV: vault cap");
        require(convertToAssets(balanceOf[receiver]) + assetsIn <= perWalletCap, "MV: wallet cap");
    }

    /// @notice Withdraw a NET `assets_` of USDC (exit fee added on top, in shares burned).
    function withdraw(uint256 assets_, address receiver, address owner) external nonReentrant accrue returns (uint256 shares) {
        shares = previewWithdraw(assets_);
        _spendShares(owner, shares);
        uint256 gross = _grossFromNet(assets_);
        _payout(owner, receiver, gross, assets_, shares);
    }

    function redeem(uint256 shares, address receiver, address owner) external nonReentrant accrue returns (uint256 netAssets) {
        require(shares > 0, "MV: zero shares");
        uint256 gross = convertToAssets(shares); // MUST price before burning
        netAssets = gross - (gross * exitFeeBps / 10_000);
        _spendShares(owner, shares);
        _payout(owner, receiver, gross, netAssets, shares);
    }

    function _spendShares(address owner, uint256 shares) internal {
        if (msg.sender != owner) {
            uint256 a = allowance[owner][msg.sender];
            if (a != type(uint256).max) {
                require(a >= shares, "MV: allowance");
                allowance[owner][msg.sender] = a - shares;
            }
        }
        _burn(owner, shares);
    }

    function _payout(address owner, address receiver, uint256 gross, uint256 net, uint256 shares) internal {
        uint256 fee = gross - net;
        require(usdc.balanceOf(address(this)) >= gross, "MV: insufficient liquid USDC");
        if (fee > 0) {
            _safeTransfer(address(usdc), feeSink, fee);
            emit ExitFeePaid(owner, fee);
        }
        _safeTransfer(address(usdc), receiver, net);
        emit Withdraw(msg.sender, receiver, owner, net, shares);
    }

    function _grossFromNet(uint256 net) internal view returns (uint256) {
        return _ceilDiv(net * 10_000, 10_000 - exitFeeBps);
    }

    // ================================================================ Fees
    function _accrueManagement() internal {
        uint256 dt = block.timestamp - lastAccrual;
        if (dt == 0) return;
        lastAccrual = uint64(block.timestamp);
        if (totalSupply == 0 || mgmtFeeBps == 0) return;
        // dilution: sink receives feeBps/yr of supply, pro-rated
        uint256 feeShares = totalSupply * mgmtFeeBps * dt / (365 days * 10_000);
        if (feeShares > 0) {
            _mint(feeSink, feeShares);
            emit ManagementAccrued(feeShares);
        }
    }

    /// @notice Crystallize performance fee above the high-water mark. Permissionless.
    function crystallize() external nonReentrant accrue {
        if (totalSupply == 0) return;
        uint256 pps = convertToAssets(1e18); // USDC(6d) per 1e18 shares
        if (pps > highWaterMark && perfFeeBps > 0) {
            uint256 profitAssets = (pps - highWaterMark) * totalSupply / 1e18;
            uint256 feeAssets = profitAssets * perfFeeBps / 10_000;
            // mint sink shares worth feeAssets at pre-mint pps (standard dilution approx)
            uint256 feeShares = feeAssets * 1e18 / pps;
            if (feeShares > 0) _mint(feeSink, feeShares);
            emit Crystallized(pps, highWaterMark, feeShares);
        }
        highWaterMark = _max(highWaterMark, pps);
    }

    // ================================================================ Trading
    function trade(address adapter, address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut)
        external
        nonReentrant
        accrue
        returns (uint256 out)
    {
        require(msg.sender == executor, "MV: not executor");
        require(!tradingPaused, "MV: trading paused");
        out = _swap(adapter, tokenIn, tokenOut, amountIn, minOut);
    }

    /// @notice Guardian escape hatch: while trading is paused, sell any held asset to USDC.
    function emergencyUnwind(address adapter, address tokenIn, uint256 amountIn, uint256 minOut)
        external
        nonReentrant
        accrue
        onlyGuardian
        returns (uint256 out)
    {
        require(tradingPaused, "MV: pause first");
        require(tokenIn != address(usdc), "MV: already cash");
        out = _swap(adapter, tokenIn, address(usdc), amountIn, minOut);
        emit EmergencyUnwind(tokenIn, amountIn, out);
    }

    function _swap(address adapter, address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut)
        internal
        returns (uint256 out)
    {
        require(adapters[adapter], "MV: bad adapter");
        require(tokenIn != tokenOut, "MV: same token");
        require(tokenIn == address(usdc) || assets[tokenIn].listed, "MV: tokenIn unlisted");
        require(tokenOut == address(usdc) || assets[tokenOut].listed, "MV: tokenOut unlisted");
        require(amountIn > 0 && minOut > 0, "MV: zero amounts");

        uint256 nav = totalAssets();
        uint256 valueIn6 = _value6(tokenIn, amountIn);

        // caps
        require(valueIn6 <= nav * perTradeBps / 10_000, "MV: per-trade cap");
        uint256 day = block.timestamp / 1 days;
        turnoverByDay[day] += valueIn6;
        require(turnoverByDay[day] <= nav * dailyTurnoverBps / 10_000, "MV: daily cap");

        // execute through adapter (pull model)
        uint256 beforeOut = IERC20(tokenOut).balanceOf(address(this));
        _safeApprove(tokenIn, adapter, amountIn);
        IRouteAdapter(adapter).swap(tokenIn, tokenOut, amountIn, minOut);
        _safeApprove(tokenIn, adapter, 0);
        out = IERC20(tokenOut).balanceOf(address(this)) - beforeOut;
        require(out >= minOut, "MV: minOut");

        // oracle-value slippage floor — the executor cannot quietly bleed the vault
        uint256 valueOut6 = _value6(tokenOut, out);
        require(valueOut6 >= valueIn6 * (10_000 - maxSlippageBps) / 10_000, "MV: value slippage");

        // cash buffer: buys must leave an exit lane; sells INTO USDC are always fine
        if (tokenOut != address(usdc)) {
            require(usdc.balanceOf(address(this)) >= totalAssets() * cashBufferBps / 10_000, "MV: cash buffer");
        }
        emit Trade(adapter, tokenIn, tokenOut, amountIn, out, valueIn6);
    }

    // ================================================================ Guardian
    function setAsset(address token, address feed, bool listed) external onlyGuardian {
        require(token != address(usdc) && token != address(0), "MV: bad token");
        if (listed) {
            uint8 fd = IPriceFeed(feed).decimals();
            uint8 ad = IERC20(token).decimals();
            require(uint256(ad) + fd >= 6, "MV: dec range");
            if (!assets[token].listed) assetList.push(token);
            assets[token] = AssetCfg(IPriceFeed(feed), ad, fd, true);
        } else {
            require(IERC20(token).balanceOf(address(this)) == 0, "MV: balance not zero");
            assets[token].listed = false;
            uint256 n = assetList.length;
            for (uint256 i = 0; i < n; i++) {
                if (assetList[i] == token) {
                    assetList[i] = assetList[n - 1];
                    assetList.pop();
                    break;
                }
            }
        }
        emit AssetSet(token, feed, listed);
    }

    function setAdapter(address adapter, bool allowed) external onlyGuardian {
        require(adapter != address(0), "MV: zero adapter");
        adapters[adapter] = allowed;
        emit AdapterSet(adapter, allowed);
    }

    function setCaps(uint16 _perTrade, uint16 _daily, uint16 _slippage, uint16 _buffer, uint32 _feedAge) external onlyGuardian {
        require(_perTrade > 0 && _perTrade <= MAX_PER_TRADE_CEIL, "MV: perTrade");
        require(_daily >= _perTrade && _daily <= 10_000, "MV: daily");
        require(_slippage > 0 && _slippage <= MAX_SLIPPAGE_CEIL, "MV: slippage");
        require(_buffer <= 5_000, "MV: buffer");
        require(_feedAge >= 1 hours && _feedAge <= 2 days, "MV: feedAge");
        perTradeBps = _perTrade;
        dailyTurnoverBps = _daily;
        maxSlippageBps = _slippage;
        cashBufferBps = _buffer;
        maxFeedAge = _feedAge;
        emit CapsSet(_perTrade, _daily, _slippage, _buffer, _feedAge);
    }

    function setFees(uint16 _mgmt, uint16 _perf, uint16 _exit) external onlyGuardian {
        require(_mgmt <= MAX_MGMT_BPS && _perf <= MAX_PERF_BPS && _exit <= MAX_EXIT_BPS, "MV: fee bounds");
        _accrueManagement(); // settle at old rate first
        mgmtFeeBps = _mgmt;
        perfFeeBps = _perf;
        exitFeeBps = _exit;
        emit FeesSet(_mgmt, _perf, _exit);
    }

    function setRoles(address _guardian, address _executor, address _feeSink) external onlyGuardian {
        require(_guardian != address(0) && _feeSink != address(0), "MV: zero addr");
        guardian = _guardian;
        executor = _executor;
        feeSink = _feeSink;
        emit RolesSet(_guardian, _executor, _feeSink);
    }

    function setTradingPaused(bool p) external onlyGuardian {
        tradingPaused = p;
        emit TradingPaused(p);
    }

    event DepositCapsSet(uint256 vaultCap, uint256 walletCap);

    /// @notice Inflow control only — never affects existing depositors or withdrawals.
    function setDepositCaps(uint256 _vaultCap, uint256 _walletCap) external onlyGuardian {
        require(_walletCap <= _vaultCap, "MV: wallet>vault");
        depositCap = _vaultCap;
        perWalletCap = _walletCap;
        emit DepositCapsSet(_vaultCap, _walletCap);
    }

    // ================================================================ Views / utils
    function assetCount() external view returns (uint256) {
        return assetList.length;
    }

    function pricePerShare() external view returns (uint256) {
        return convertToAssets(1e18);
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a + b - 1) / b;
    }

    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "MV: transfer failed");
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "MV: transferFrom failed");
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "MV: approve failed");
    }
}
