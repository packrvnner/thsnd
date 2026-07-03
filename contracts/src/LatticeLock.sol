// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// ---------------------------------------------------------------------
///  LatticeLock — vMUY staking + protocol fee share
///
///  Lock $MUY for 1 week .. 4 years:
///    vMUY (voting power) = amount * lockDuration / MAX_LOCK   (fixed at lock time)
///  Fee share: protocol fees (e.g. WETH) pushed in via notifyReward()
///  are streamed pro-rata to vMUY weight (Synthetix accumulator pattern).
///
///  vMUY is non-transferable by construction (it is not a token; it is
///  a weight in this contract). Locks are non-custodial: principal is
///  always withdrawable at expiry, no admin path can touch it.
/// ---------------------------------------------------------------------
contract LatticeLock {
    uint256 public constant MIN_LOCK = 1 weeks;
    uint256 public constant MAX_LOCK = 4 * 365 days;

    IERC20 public immutable muy;
    IERC20 public immutable rewardToken; // e.g. WETH fee revenue from MUY Lattice

    address public owner;
    address public feeNotifier; // MuyFeeHook / treasury bot allowed to push fees

    struct Lock {
        uint128 amount;   // MUY locked
        uint128 power;    // vMUY, fixed at lock time
        uint64 end;       // unlock timestamp
    }

    mapping(address => Lock) public locks;
    uint256 public totalPower;   // sum of all vMUY
    uint256 public totalLocked;  // sum of all locked MUY

    // -------- Synthetix-style reward accounting (scaled 1e18) --------
    uint256 public rewardPerPowerStored;
    mapping(address => uint256) public userRewardPerPowerPaid;
    mapping(address => uint256) public rewards;

    event Locked(address indexed user, uint256 amount, uint256 power, uint256 end);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);
    event RewardNotified(uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "LL: not owner");
        _;
    }

    constructor(address _muy, address _rewardToken) {
        muy = IERC20(_muy);
        rewardToken = IERC20(_rewardToken);
        owner = msg.sender;
    }

    // ---------------------------------------------------------------- Admin
    function setFeeNotifier(address n) external onlyOwner {
        feeNotifier = n;
    }

    function transferOwnership(address n) external onlyOwner {
        require(n != address(0), "LL: zero owner");
        owner = n;
    }

    // ---------------------------------------------------------------- Lock / withdraw
    /// @notice Create or top up a lock. Topping up requires the same-or-later end;
    ///         new power is added for the added amount at the remaining duration.
    function lock(uint256 amount, uint256 duration) external {
        require(amount > 0, "LL: zero amount");
        require(duration >= MIN_LOCK && duration <= MAX_LOCK, "LL: bad duration");

        _updateReward(msg.sender);

        Lock storage l = locks[msg.sender];
        uint256 newEnd = block.timestamp + duration;
        if (l.amount > 0) {
            require(newEnd >= l.end, "LL: cannot shorten lock");
        }

        uint256 addedPower = (amount * duration) / MAX_LOCK;
        require(addedPower > 0, "LL: dust lock");

        l.amount += uint128(amount);
        l.power += uint128(addedPower);
        l.end = uint64(newEnd);

        totalPower += addedPower;
        totalLocked += amount;

        require(muy.transferFrom(msg.sender, address(this), amount), "LL: transfer failed");
        emit Locked(msg.sender, amount, addedPower, newEnd);
    }

    /// @notice Withdraw full principal after expiry. Claims pending fees too.
    function withdraw() external {
        Lock memory l = locks[msg.sender];
        require(l.amount > 0, "LL: no lock");
        require(block.timestamp >= l.end, "LL: still locked");

        _updateReward(msg.sender);

        totalPower -= l.power;
        totalLocked -= l.amount;
        delete locks[msg.sender];

        _payReward(msg.sender);
        require(muy.transfer(msg.sender, l.amount), "LL: transfer failed");
        emit Withdrawn(msg.sender, l.amount);
    }

    /// @notice Claim accrued fee share without touching the lock.
    function claim() external {
        _updateReward(msg.sender);
        _payReward(msg.sender);
    }

    // ---------------------------------------------------------------- Fees in
    /// @notice Push protocol fees to all current lockers, pro-rata by vMUY.
    /// @dev Caller must have transferred/approved `amount` of rewardToken.
    function notifyReward(uint256 amount) external {
        require(msg.sender == feeNotifier || msg.sender == owner, "LL: not notifier");
        require(totalPower > 0, "LL: no lockers");
        require(rewardToken.transferFrom(msg.sender, address(this), amount), "LL: transfer failed");
        rewardPerPowerStored += (amount * 1e18) / totalPower;
        emit RewardNotified(amount);
    }

    // ---------------------------------------------------------------- Views
    function votingPower(address user) external view returns (uint256) {
        Lock memory l = locks[user];
        return block.timestamp >= l.end ? 0 : l.power; // expired locks lose governance weight
    }

    function earned(address user) public view returns (uint256) {
        Lock memory l = locks[user];
        return rewards[user] + (uint256(l.power) * (rewardPerPowerStored - userRewardPerPowerPaid[user])) / 1e18;
    }

    // ---------------------------------------------------------------- Internal
    function _updateReward(address user) internal {
        rewards[user] = earned(user);
        userRewardPerPowerPaid[user] = rewardPerPowerStored;
    }

    function _payReward(address user) internal {
        uint256 r = rewards[user];
        if (r > 0) {
            rewards[user] = 0;
            require(rewardToken.transfer(user, r), "LL: reward transfer failed");
            emit RewardPaid(user, r);
        }
    }
}
