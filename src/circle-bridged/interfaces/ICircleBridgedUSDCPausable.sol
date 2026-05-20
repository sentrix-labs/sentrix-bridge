// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ICircleBridgedUSDCPausable
/// @notice Pause interface required by Circle Bridged USDC Standard for BOTH
///         the source-chain bridge AND the destination-chain bridge.
///
/// @dev    Source: bridged_USDC_standard.md §"Ability to pause USDC bridging".
///         "The bridge contracts must be able to pause bridging, enabling a
///         finalization of the supply of the bridged token with that supply
///         being fully backed by an amount of native USDC on the source chain."
///
///         Pause is the FIRST step in Circle's upgrade choreography:
///         1. Pause bridging on both sides.
///         2. Allow in-flight transfers to finalize.
///         3. Reconcile supply.
///         4. Circle calls burnLockedUSDC() and transferUSDCRoles().
///         5. Upgrade FiatToken implementation to native USDC.
interface ICircleBridgedUSDCPausable {
    /// @notice Pause USDC bridging. Used at upgrade time and emergency.
    function pauseBridging() external;

    /// @notice Unpause USDC bridging.
    function unpauseBridging() external;

    /// @notice Whether bridging is currently paused.
    function bridgingPaused() external view returns (bool);

    event BridgingPaused(address indexed caller);
    event BridgingUnpaused(address indexed caller);
}
