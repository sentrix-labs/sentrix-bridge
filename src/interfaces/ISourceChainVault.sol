// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/// @title ISourceChainVault
/// @notice Interface for the source-chain vault that locks ERC20 collateral
///         before a bridged-mint event is relayed to Sentrix Chain.
/// @dev    Implementation lives in src/stablecoin/SourceChainVault.sol.
interface ISourceChainVault {
    /// @notice Emitted when a user deposits collateral for cross-chain mint.
    /// @param  depositId         Monotonic id, unique per vault instance.
    /// @param  sourceChainId     block.chainid of this vault's chain.
    /// @param  destinationChainId Target chain id (e.g. Sentrix 7119 / 7120).
    /// @param  depositor         msg.sender on the source chain.
    /// @param  recipient         Address on destination chain that receives bridged tokens.
    /// @param  token             ERC20 token locked.
    /// @param  amount            Amount of token (token-native decimals).
    /// @param  nonce             Per-depositor monotonic nonce.
    event Deposit(
        uint256 indexed depositId,
        uint256 sourceChainId,
        uint256 indexed destinationChainId,
        address indexed depositor,
        address recipient,
        address token,
        uint256 amount,
        uint256 nonce
    );

    /// @notice Emitted when an authorized operator releases locked collateral
    ///         back to a user (during a withdrawal from Sentrix).
    event Release(
        uint256 indexed withdrawalId,
        address indexed recipient,
        address token,
        uint256 amount
    );

    /// @notice Lock `amount` of the configured collateral token; emits Deposit.
    /// @dev    Reverts on zero amount or zero recipient. Pull-pattern: caller
    ///         must approve this vault for `amount` first.
    function deposit(address recipient, uint256 amount, uint256 destinationChainId)
        external
        returns (uint256 depositId);

    /// @notice Authorized release of locked collateral. Called by the bridge
    ///         operator/multisig after verifying a burn-and-withdraw on Sentrix.
    /// @dev    Idempotency (no double-release on the same withdrawalId) is the
    ///         operator's off-chain responsibility — see BRIDGE_RELAYER_DESIGN.md.
    function release(uint256 withdrawalId, address recipient, uint256 amount) external;

    /// @notice Total amount currently locked in the vault.
    function totalLocked() external view returns (uint256);

    /// @notice Immutable collateral token address.
    function collateralToken() external view returns (address);
}
