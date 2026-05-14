// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {AccessControl} from "oz-v4/access/AccessControl.sol";
import {Pausable} from "oz-v4/security/Pausable.sol";
import {ReentrancyGuard} from "oz-v4/security/ReentrancyGuard.sol";
import {SafeERC20} from "oz-v4/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "oz-v4/token/ERC20/IERC20.sol";

import {ISourceChainVault} from "../interfaces/ISourceChainVault.sol";

/// @title SourceChainVault
/// @notice Locks ERC20 collateral on the source chain before a bridged-mint
///         event is relayed to Sentrix Chain. Authorized operator can release
///         locked collateral after verifying a burn-and-withdraw on Sentrix.
///
/// @dev    SAFETY MODEL
///         - This contract is the trusted-party leg of the bridge. Off-chain
///           relayer is responsible for: (1) confirming source-chain finality
///           before triggering the mint on Sentrix, (2) confirming the burn
///           on Sentrix before triggering release on this vault, (3) ensuring
///           no withdrawalId is processed twice (idempotency).
///         - Reorg protection is enforced off-chain via configurable
///           confirmation depth per source chain. See BRIDGE_RELAYER_DESIGN.md.
///         - This contract does NOT verify any cross-chain proof on-chain.
///           The OPERATOR_ROLE multisig is the single source of truth for
///           release authorization in the PoC.
///         - For production, replace OPERATOR_ROLE manual release with a
///           proven message-verification path (Hyperlane MultisigIsm,
///           LayerZero DVN aggregation, or Wormhole NTT guardian set).
contract SourceChainVault is ISourceChainVault, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------- //
    //                                ROLES                                 //
    // -------------------------------------------------------------------- //

    /// @notice Can pause/unpause. Multisig recommended.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Can release locked collateral after off-chain verification.
    ///         Multisig REQUIRED in production.
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // -------------------------------------------------------------------- //
    //                              STORAGE                                 //
    // -------------------------------------------------------------------- //

    /// @notice The single ERC20 token this vault accepts. Immutable to avoid
    ///         token-swap rug class.
    IERC20 public immutable collateral;

    /// @notice Monotonic per-vault deposit id (incremented before emission).
    uint256 public lastDepositId;

    /// @notice Per-depositor nonce, monotonic. Used for off-chain dedup.
    mapping(address => uint256) public depositNonce;

    /// @notice Total currently locked (sum of deposits - released). Diverges
    ///         from token.balanceOf(this) if anyone sends tokens directly;
    ///         off-chain monitoring should alert on the divergence.
    uint256 internal _totalLocked;

    // -------------------------------------------------------------------- //
    //                            CONSTRUCTOR                               //
    // -------------------------------------------------------------------- //

    /// @param _collateral     Immutable ERC20 this vault locks.
    /// @param _admin          Initial DEFAULT_ADMIN_ROLE holder (multisig).
    /// @param _operator       Initial OPERATOR_ROLE (multisig REQUIRED in prod).
    /// @param _pauser         Initial PAUSER_ROLE.
    constructor(IERC20 _collateral, address _admin, address _operator, address _pauser) {
        require(address(_collateral) != address(0), "collateral=0");
        require(_admin != address(0), "admin=0");
        require(_operator != address(0), "operator=0");
        require(_pauser != address(0), "pauser=0");

        collateral = _collateral;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _operator);
        _grantRole(PAUSER_ROLE, _pauser);
    }

    // -------------------------------------------------------------------- //
    //                           USER ENTRY                                 //
    // -------------------------------------------------------------------- //

    /// @inheritdoc ISourceChainVault
    function deposit(address recipient, uint256 amount, uint256 destinationChainId)
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256 depositId)
    {
        require(recipient != address(0), "recipient=0");
        require(amount > 0, "amount=0");
        require(destinationChainId != 0, "dstChain=0");

        // CEI: state -> external call
        depositId = ++lastDepositId;
        uint256 nonce = ++depositNonce[msg.sender];
        _totalLocked += amount;

        emit Deposit({
            depositId: depositId,
            sourceChainId: block.chainid,
            destinationChainId: destinationChainId,
            depositor: msg.sender,
            recipient: recipient,
            token: address(collateral),
            amount: amount,
            nonce: nonce
        });

        collateral.safeTransferFrom(msg.sender, address(this), amount);
    }

    // -------------------------------------------------------------------- //
    //                         OPERATOR ENTRY                               //
    // -------------------------------------------------------------------- //

    /// @inheritdoc ISourceChainVault
    function release(uint256 withdrawalId, address recipient, uint256 amount)
        external
        override
        whenNotPaused
        onlyRole(OPERATOR_ROLE)
        nonReentrant
    {
        require(recipient != address(0), "recipient=0");
        require(amount > 0, "amount=0");
        require(amount <= _totalLocked, "exceeds locked");

        _totalLocked -= amount;

        emit Release(withdrawalId, recipient, address(collateral), amount);

        collateral.safeTransfer(recipient, amount);
    }

    // -------------------------------------------------------------------- //
    //                         ADMIN / PAUSE                                //
    // -------------------------------------------------------------------- //

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // -------------------------------------------------------------------- //
    //                               VIEW                                   //
    // -------------------------------------------------------------------- //

    /// @inheritdoc ISourceChainVault
    function totalLocked() external view override returns (uint256) {
        return _totalLocked;
    }

    /// @inheritdoc ISourceChainVault
    function collateralToken() external view override returns (address) {
        return address(collateral);
    }
}
