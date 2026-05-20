// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "oz-v4/token/ERC20/ERC20.sol";

/// @notice Minimal USDC mock for source-bridge tests.
/// @dev    Has a `burn(uint256)` callable by minters to mirror FiatToken's
///         burn semantics, used by burnLockedUSDC.
contract MockUSDC is ERC20 {
    mapping(address => bool) public isMinter;
    mapping(address => uint256) public minterAllowance;

    constructor() ERC20("USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @dev Simulate FiatToken.burn — caller must be a minter, burns their balance.
    function burn(uint256 amount) external {
        require(isMinter[msg.sender] || msg.sender == owner(), "not minter");
        _burn(msg.sender, amount);
    }

    function setMinter(address minter, bool _isMinter) external {
        isMinter[minter] = _isMinter;
    }

    function owner() public view returns (address) {
        return address(this); // tests don't need a real owner
    }
}
