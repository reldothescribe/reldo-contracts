// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ReldoVesting
/// @notice Holds $RELDO tokens and releases them linearly over 6 months
/// @dev No admin keys, no complexity - just math and time
contract ReldoVesting {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public immutable beneficiary;
    uint256 public immutable start;
    uint256 public immutable duration;
    uint256 public totalAllocation;
    uint256 public released;

    event TokensDeposited(address indexed depositor, uint256 amount);
    event TokensReleased(uint256 amount);

    constructor(address _token, address _beneficiary, uint256 _duration) {
        require(_token != address(0), "token = zero");
        require(_beneficiary != address(0), "beneficiary = zero");
        require(_duration > 0, "duration = 0");

        token = IERC20(_token);
        beneficiary = _beneficiary;
        start = block.timestamp;
        duration = _duration;
    }

    /// @notice Deposit tokens to fund the vesting
    function deposit(uint256 amount) external {
        require(amount > 0, "amount = 0");
        totalAllocation += amount;
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit TokensDeposited(msg.sender, amount);
    }

    /// @notice Returns how many tokens have vested so far
    function vested() public view returns (uint256) {
        if (totalAllocation == 0) return 0;
        if (block.timestamp >= start + duration) {
            return totalAllocation;
        }
        return (totalAllocation * (block.timestamp - start)) / duration;
    }

    /// @notice Returns how many tokens are available to release right now
    function releasable() public view returns (uint256) {
        return vested() - released;
    }

    /// @notice Release vested tokens to the beneficiary. Anyone can call this.
    function release() external {
        uint256 amount = releasable();
        require(amount > 0, "nothing to release");
        released += amount;
        token.safeTransfer(beneficiary, amount);
        emit TokensReleased(amount);
    }

    /// @notice View function for UI - returns all state in one call
    function status() external view returns (
        uint256 _totalAllocation,
        uint256 _vested,
        uint256 _released,
        uint256 _releasable,
        uint256 _start,
        uint256 _duration,
        uint256 _remaining
    ) {
        _totalAllocation = totalAllocation;
        _vested = vested();
        _released = released;
        _releasable = releasable();
        _start = start;
        _duration = duration;
        _remaining = block.timestamp >= start + duration ? 0 : (start + duration) - block.timestamp;
    }
}
