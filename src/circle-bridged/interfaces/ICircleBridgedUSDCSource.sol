// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ICircleBridgedUSDCSource
/// @notice Interface that a source-chain bridge MUST implement to be
///         compatible with Circle's Bridged USDC Standard upgrade path.
///
/// @dev    Source: https://github.com/circlefin/stablecoin-evm/blob/master/doc/bridged_USDC_standard.md
///
///         The Circle Bridged USDC Standard requires the source-chain bridge
///         contract to be upgradeable and to expose two specific functions
///         that Circle will call during the eventual bridge-to-native upgrade.
///         This interface fixes their EXACT signatures.
///
///         Bridge implementers MUST:
///         1. Be upgradeable (Circle requirement).
///         2. Implement `burnLockedUSDC()` and `transferUSDCRoles(address)`
///            with these exact signatures.
///         3. Restrict each function to a Circle-specified address (set near
///            upgrade time).
///         4. Be able to pause USDC bridging (separate function — see
///            ICircleBridgedUSDCPausable).
///
///         These functions MAY be implemented as no-ops initially and
///         activated only when Circle requests the upgrade — per Circle's own
///         recommendation: "Circle recommends deferring adding this
///         functionality to a later time through a contract upgrade after
///         Circle and the third-party team have jointly agreed to proceed with
///         an upgrade."
interface ICircleBridgedUSDCSource {
    // ---------------------------------------------------------------- //
    //   CIRCLE-MANDATED FUNCTIONS (exact signatures from the standard)
    // ---------------------------------------------------------------- //

    /// @notice Burns the bridge's locked USDC equal to the finalized bridged
    ///         supply on the destination chain.
    /// @dev    Called by a Circle-specified address (granted via role) at
    ///         upgrade time. The bridge holds a temporary zero-allowance
    ///         minter role on native USDC for the purpose of burning.
    ///
    ///         REQUIREMENT (from spec):
    ///         1. Be only callable by an address that Circle specifies closer
    ///            to the time of the upgrade.
    ///         2. Burn an amount of USDC held by the bridge that equals the
    ///            total supply of bridged USDC finalized by the supply lock.
    function burnLockedUSDC() external;

    /// @notice Transfers the FiatToken contract's `owner` role (and proxy
    ///         `admin` if held by the bridge) to a Circle-controlled address.
    /// @dev    Called by a Circle-specified address (may be different from
    ///         the burn caller) at upgrade time.
    ///
    ///         REQUIREMENT (from spec):
    ///         1. Be only callable by an address that Circle specifies closer
    ///            to the time of the upgrade.
    ///         2. Transfer the Implementation Owner role to `owner`.
    ///         3. Transfer the ProxyAdmin role to the caller (if assigned to
    ///            the bridge).
    ///
    ///         Additionally, the bridge implementer is expected to REMOVE all
    ///         configured minters on the FiatToken before (or concurrently
    ///         with) this transfer.
    function transferUSDCRoles(address owner) external;

    // ---------------------------------------------------------------- //
    //                           EVENTS
    // ---------------------------------------------------------------- //

    /// @notice Emitted when locked USDC is burned during the Circle upgrade.
    event LockedUSDCBurned(address indexed caller, uint256 amount);

    /// @notice Emitted when FiatToken roles are transferred to Circle.
    event USDCRolesTransferred(address indexed caller, address indexed newOwner);
}
