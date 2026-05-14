// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "oz-v4/token/ERC20/IERC20.sol";
import {SafeERC20} from "oz-v4/token/ERC20/utils/SafeERC20.sol";

import {ICircleBridgedUSDCSource} from "../interfaces/ICircleBridgedUSDCSource.sol";
import {ICircleBridgedUSDCPausable} from "../interfaces/ICircleBridgedUSDCPausable.sol";

/// @title SentrixUSDCSourceBridge
/// @notice Upgradeable source-chain bridge for Sentrix Bridged USDC, compliant
///         with Circle's Bridged USDC Standard hooks.
///
/// @dev    SCAFFOLD — see SCAFFOLD NOTES below.
///
///         This contract is the source-chain (e.g. Sepolia, then Ethereum
///         mainnet) leg of the Sentrix bridge for USDC. It locks real USDC
///         and instructs the Sentrix-side bridge to mint the same amount of
///         bridged USDC.
///
///         WHAT THIS CONTRACT MUST DO (per Circle Standard):
///         1. Be upgradeable (UUPS or Transparent proxy).
///         2. Lock USDC and emit a Deposit event the off-chain or
///            Hyperlane-driven relayer picks up.
///         3. Release USDC on verified withdrawal from Sentrix.
///         4. Be pausable (Circle requirement).
///         5. Expose `burnLockedUSDC()` (Circle hook).
///         6. Expose `transferUSDCRoles(address)` (Circle hook).
///
///         WHAT IS NOT FINAL IN THIS SCAFFOLD:
///         - Hyperlane integration is OUT (this is Phase 1 testnet — relayer-
///           driven). Phase 2 wires Hyperlane Mailbox + ISM for the cross-
///           chain message verification. Until then, `release` is gated by
///           OPERATOR_ROLE (SentrixSafe in Phase 1 (currently 1-of-1);
///           multisig recommended once co-signers recruited at Phase 3b+).
///         - The mint-allowance / cap is NOT enforced here — it lives on the
///           destination FiatToken via masterMinter. This contract is supply-
///           generating but not supply-restricting.
///         - `burnLockedUSDC` requires the bridge to be a configured minter
///           on Ethereum USDC at upgrade time. Circle grants this
///           "zero-allowance minter" role temporarily.
///
///         SECURITY NOTE: This is a TRUSTED bridge in Phase 1. Production
///         requires Hyperlane MultisigIsm or equivalent message verification.
///         Operator must NOT deploy to mainnet until Phase 2 wiring complete.
contract SentrixUSDCSourceBridge is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ICircleBridgedUSDCSource,
    ICircleBridgedUSDCPausable
{
    using SafeERC20 for IERC20;

    // ----------------------------------------------------------------- //
    //                              ROLES
    // ----------------------------------------------------------------- //

    /// @notice Can pause/unpause bridging. Phase 1: SentrixSafe (currently 1-of-1). Phase 3b+:
    ///         multisig recommended. See docs/stablecoin/BOOTSTRAP_ROLE_HOLDER.md.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Can release locked USDC on verified Sentrix burn.
    ///         PHASE 1: held by SentrixSafe (currently 1-of-1).
    ///         PHASE 2: held by Hyperlane message handler.
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Held by Circle-specified address near upgrade time. Allows
    ///         calling `burnLockedUSDC`. SEPARATE from CIRCLE_ROLE_TRANSFER
    ///         per spec: "this address will not necessarily be the same
    ///         address that is specified to call `transferUSDCRoles`".
    bytes32 public constant CIRCLE_BURN_ROLE = keccak256("CIRCLE_BURN_ROLE");

    /// @notice Held by Circle-specified address near upgrade time. Allows
    ///         calling `transferUSDCRoles`.
    bytes32 public constant CIRCLE_ROLE_TRANSFER_ROLE = keccak256("CIRCLE_ROLE_TRANSFER_ROLE");

    // ----------------------------------------------------------------- //
    //                              STORAGE
    // ----------------------------------------------------------------- //

    /// @notice The real USDC token this bridge locks. Set at initialization;
    ///         cannot change (would void Bridged USDC Standard alignment).
    IERC20 public usdc;

    /// @notice Total USDC currently locked (sum of deposits - releases - burnt).
    uint256 public totalLocked;

    /// @notice Monotonic deposit id.
    uint256 public lastDepositId;

    /// @notice Per-depositor nonce.
    mapping(address => uint256) public depositNonce;

    /// @notice Sentrix chain id (e.g. 7120 testnet, 7119 mainnet). Used for
    ///         event payload only; the actual destination is the configured
    ///         destination bridge address.
    uint256 public sentrixChainId;

    // ----------------------------------------------------------------- //
    //                              EVENTS
    // ----------------------------------------------------------------- //

    /// @notice Emitted when a user deposits USDC for bridging to Sentrix.
    event Deposit(
        uint256 indexed depositId,
        uint256 indexed sentrixChainId,
        address indexed depositor,
        address recipient,
        uint256 amount,
        uint256 nonce
    );

    /// @notice Emitted when locked USDC is released back to a user (after
    ///         verified burn on Sentrix).
    event Release(
        uint256 indexed withdrawalId,
        address indexed recipient,
        uint256 amount
    );

    // ----------------------------------------------------------------- //
    //                            INITIALIZER
    // ----------------------------------------------------------------- //

    /// @param _usdc            The real USDC ERC20 contract on this chain.
    /// @param _sentrixChainId  Destination chain id (7120 testnet / 7119 mainnet).
    /// @param _admin           DEFAULT_ADMIN_ROLE holder (operator EOA for Phase 1; multisig at Phase 3b+).
    /// @param _operator        OPERATOR_ROLE holder (Phase 1: SentrixSafe (currently 1-of-1); Phase 2: Hyperlane handler).
    /// @param _pauser          PAUSER_ROLE holder (operator EOA for Phase 1; multisig recommended at scale).
    ///
    /// @dev Circle's burn and role-transfer roles are NOT granted here. They
    ///      are granted by the admin near upgrade time at Circle's request.
    function initialize(
        IERC20 _usdc,
        uint256 _sentrixChainId,
        address _admin,
        address _operator,
        address _pauser
    ) external initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        require(address(_usdc) != address(0), "usdc=0");
        require(_sentrixChainId != 0, "sentrixChainId=0");
        require(_admin != address(0), "admin=0");
        require(_operator != address(0), "operator=0");
        require(_pauser != address(0), "pauser=0");

        usdc = _usdc;
        sentrixChainId = _sentrixChainId;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _operator);
        _grantRole(PAUSER_ROLE, _pauser);
    }

    // ----------------------------------------------------------------- //
    //                          USER ENTRY
    // ----------------------------------------------------------------- //

    /// @notice Lock USDC for bridging to Sentrix. Pull-pattern — caller must
    ///         have approved this contract for `amount` first.
    function deposit(address recipient, uint256 amount)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 depositId)
    {
        require(recipient != address(0), "recipient=0");
        require(amount > 0, "amount=0");

        depositId = ++lastDepositId;
        uint256 nonce = ++depositNonce[msg.sender];
        totalLocked += amount;

        emit Deposit({
            depositId: depositId,
            sentrixChainId: sentrixChainId,
            depositor: msg.sender,
            recipient: recipient,
            amount: amount,
            nonce: nonce
        });

        usdc.safeTransferFrom(msg.sender, address(this), amount);
    }

    // ----------------------------------------------------------------- //
    //                       OPERATOR / BRIDGE ENTRY
    // ----------------------------------------------------------------- //

    /// @notice Release locked USDC to a user after a verified burn on Sentrix.
    /// @dev    PHASE 1: gated by OPERATOR_ROLE (operator EOA, single-sig bootstrap).
    ///         PHASE 2: gated by Hyperlane Mailbox message handler.
    function release(uint256 withdrawalId, address recipient, uint256 amount)
        external
        whenNotPaused
        onlyRole(OPERATOR_ROLE)
        nonReentrant
    {
        require(recipient != address(0), "recipient=0");
        require(amount > 0, "amount=0");
        require(amount <= totalLocked, "exceeds locked");

        totalLocked -= amount;

        emit Release(withdrawalId, recipient, amount);

        usdc.safeTransfer(recipient, amount);
    }

    // ----------------------------------------------------------------- //
    //              CIRCLE BRIDGED USDC STANDARD HOOKS
    // ----------------------------------------------------------------- //

    /// @inheritdoc ICircleBridgedUSDCSource
    function burnLockedUSDC() external override onlyRole(CIRCLE_BURN_ROLE) {
        // At Circle upgrade time, this bridge is granted a temporary
        // zero-allowance minter role on the native USDC contract on this
        // chain. That role lets the bridge burn its OWN balance (no new
        // mint authority). We call USDC.burn(amount) — the native USDC
        // contract is itself a FiatToken-style contract that exposes
        // `burn(uint256)` for minters.
        //
        // Per spec §"Ability to burn locked USDC": amount burnt MUST equal
        // the total bridged supply finalized after the supply lock. The
        // amount here is just the bridge's current balance; off-chain
        // process MUST reconcile against destination total supply.
        uint256 balance = usdc.balanceOf(address(this));
        require(balance > 0, "nothing to burn");

        // FiatToken.burn(uint256) — assumes this bridge has the minter role
        // (zero-allowance) granted by Circle.
        // Static-call the burn signature.
        (bool ok, ) = address(usdc).call(
            abi.encodeWithSignature("burn(uint256)", balance)
        );
        require(ok, "burn failed");

        // Bookkeeping — locked balance accounted as burnt.
        totalLocked = 0;

        emit LockedUSDCBurned(msg.sender, balance);
    }

    /// @inheritdoc ICircleBridgedUSDCSource
    function transferUSDCRoles(address newOwner)
        external
        override
        onlyRole(CIRCLE_ROLE_TRANSFER_ROLE)
    {
        require(newOwner != address(0), "newOwner=0");

        // On the SENTRIX side (destination), this bridge does NOT hold the
        // FiatToken proxy admin or owner directly — those are held by a
        // EOA (or later multisig) that operator controls. The transfer happens via a
        // CROSS-CHAIN message to the destination bridge, which then performs
        // the role transfer on the destination FiatToken.
        //
        // PHASE 1: this is documented behaviour only; cross-chain handover
        //          requires Hyperlane wiring (Phase 2) or operator manual
        //          coordination.
        // PHASE 2: emit a Hyperlane message to destination bridge which
        //          executes the transfer on the FiatToken proxy +
        //          implementation owner.

        emit USDCRolesTransferred(msg.sender, newOwner);

        // Placeholder — actual cross-chain dispatch implemented in Phase 2.
        revert("Phase 2: Hyperlane wiring required for cross-chain role transfer");
    }

    // ----------------------------------------------------------------- //
    //                            PAUSING
    // ----------------------------------------------------------------- //

    /// @inheritdoc ICircleBridgedUSDCPausable
    function pauseBridging() external override onlyRole(PAUSER_ROLE) {
        _pause();
        emit BridgingPaused(msg.sender);
    }

    /// @inheritdoc ICircleBridgedUSDCPausable
    function unpauseBridging() external override onlyRole(PAUSER_ROLE) {
        _unpause();
        emit BridgingUnpaused(msg.sender);
    }

    /// @inheritdoc ICircleBridgedUSDCPausable
    function bridgingPaused() external view override returns (bool) {
        return paused();
    }

    // ----------------------------------------------------------------- //
    //                         STORAGE GAP
    // ----------------------------------------------------------------- //

    /// @dev Reserve storage slots for future upgrades. Required for
    ///      upgradeable contracts.
    uint256[40] private __gap;
}
