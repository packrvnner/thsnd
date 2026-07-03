// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// ---------------------------------------------------------------------
///  MuyVesting — onchain team/investor vesting
///
///  One contract per beneficiary. Cliff + linear:
///    - Before `start + cliff`: nothing releasable.
///    - After cliff: vests linearly from `start` until `start + duration`.
///
///  Irrevocable by design: no admin, no clawback, no pause. Once funded,
///  the schedule is the schedule. Publish these addresses pre-launch —
///  this is what makes the "premium" positioning credible.
///
///  Deploy → transfer the allocation of MUY to this contract → done.
///  Anyone can call release(); tokens only ever go to the beneficiary.
/// ---------------------------------------------------------------------
contract MuyVesting {
    IERC20 public immutable token;
    address public immutable beneficiary;
    uint64 public immutable start;
    uint64 public immutable cliff;     // seconds after start
    uint64 public immutable duration;  // total vesting length, >= cliff

    uint256 public released;

    event Released(uint256 amount);

    constructor(address _token, address _beneficiary, uint64 _start, uint64 _cliff, uint64 _duration) {
        require(_token != address(0) && _beneficiary != address(0), "MV: zero address");
        require(_duration > 0 && _cliff <= _duration, "MV: bad schedule");
        token = IERC20(_token);
        beneficiary = _beneficiary;
        start = _start;
        cliff = _cliff;
        duration = _duration;
    }

    /// @notice Total allocation = current balance + already released.
    function totalAllocation() public view returns (uint256) {
        return token.balanceOf(address(this)) + released;
    }

    /// @notice Amount vested at `timestamp` (0 before cliff, linear after).
    function vestedAmount(uint64 timestamp) public view returns (uint256) {
        if (timestamp < start + cliff) return 0;
        uint256 total = totalAllocation();
        if (timestamp >= start + duration) return total;
        return (total * (timestamp - start)) / duration;
    }

    function releasable() public view returns (uint256) {
        return vestedAmount(uint64(block.timestamp)) - released;
    }

    /// @notice Release vested tokens to the beneficiary. Callable by anyone.
    function release() external {
        uint256 amount = releasable();
        require(amount > 0, "MV: nothing vested");
        released += amount;
        require(token.transfer(beneficiary, amount), "MV: transfer failed");
        emit Released(amount);
    }
}
