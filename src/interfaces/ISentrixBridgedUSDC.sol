// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/// @title ISentrixBridgedUSDC
/// @notice Interface for the bridged stablecoin token deployed on Sentrix Chain.
/// @dev    THIS IS NOT OFFICIAL CIRCLE USDC. See SECURITY_NOTES.md.
interface ISentrixBridgedUSDC {
    /// @notice Emitted on a successful bridge-mint (after off-chain proof).
    event BridgeMint(
        uint256 indexed depositId,
        uint256 indexed sourceChainId,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Emitted on a user-initiated burn-for-withdrawal.
    /// @param  withdrawalId       Monotonic id, unique per token instance.
    /// @param  sentrixChainId     block.chainid of Sentrix (this chain).
    /// @param  destinationChainId Target chain id where collateral will release.
    /// @param  sender             msg.sender (token holder burning).
    /// @param  recipient          Address on destination chain receiving collateral.
    /// @param  amount             Amount burned (6 decimals).
    /// @param  nonce              Per-sender monotonic nonce.
    event WithdrawRequested(
        uint256 indexed withdrawalId,
        uint256 sentrixChainId,
        uint256 indexed destinationChainId,
        address indexed sender,
        address recipient,
        uint256 amount,
        uint256 nonce
    );

    /// @notice Mint `amount` tokens to `recipient`. Restricted to BRIDGE_MINTER_ROLE.
    function bridgeMint(uint256 depositId, uint256 sourceChainId, address recipient, uint256 amount) external;

    /// @notice Burn `amount` from msg.sender and emit WithdrawRequested.
    function burnForWithdrawal(address recipient, uint256 amount, uint256 destinationChainId)
        external
        returns (uint256 withdrawalId);

    /// @notice Remaining mint allowance for a specific minter (anti-unlimited-mint).
    function mintAllowance(address minter) external view returns (uint256);
}
