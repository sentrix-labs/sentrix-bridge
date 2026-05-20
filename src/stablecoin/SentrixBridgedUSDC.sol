// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {AccessControl} from "oz-v4/access/AccessControl.sol";
import {ERC20} from "oz-v4/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "oz-v4/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "oz-v4/token/ERC20/extensions/ERC20Pausable.sol";

import {ISentrixBridgedUSDC} from "../interfaces/ISentrixBridgedUSDC.sol";

/// @title SentrixBridgedUSDC (sUSDC)
/// @notice Bridged stablecoin ERC20 on Sentrix Chain. NOT OFFICIAL CIRCLE USDC.
///         Backed 1:1 by USDC locked in a SourceChainVault on the source chain.
///
/// @dev    SAFETY MODEL
///         - Trusted-party bridge. Mint authority lives in BRIDGE_MINTER_ROLE.
///           Off-chain relayer is the source of truth for "USDC was locked on
///           source chain, mint here".
///         - Per-minter allowance cap. No unlimited-mint allowed by default.
///         - Pausable. Pausing freezes transfers, mints, and burns.
///         - 6 decimals to match USDC convention.
///         - Non-upgradeable. For Circle-Bridged-USDC-Standard compatibility
///           (which requires UUPS proxy + specific role layout for Circle to
///           later take ownership), use Circle's official FiatTokenV2_2 from
///           https://github.com/circlefin/stablecoin-evm — see README.
///         - This contract is intentionally minimal. For a Circle-Standard
///           token, the role architecture differs (masterMinter, controller,
///           pauser, blacklister, rescuer).
contract SentrixBridgedUSDC is ISentrixBridgedUSDC, ERC20Pausable, ERC20Burnable, AccessControl {
    // -------------------------------------------------------------------- //
    //                                ROLES                                 //
    // -------------------------------------------------------------------- //

    /// @notice Can call bridgeMint. Capped by per-minter allowance.
    bytes32 public constant BRIDGE_MINTER_ROLE = keccak256("BRIDGE_MINTER_ROLE");

    /// @notice Can update minter allowances. Multisig recommended.
    bytes32 public constant MINTER_ADMIN_ROLE = keccak256("MINTER_ADMIN_ROLE");

    /// @notice Can pause/unpause.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // -------------------------------------------------------------------- //
    //                              STORAGE                                 //
    // -------------------------------------------------------------------- //

    /// @notice Remaining mint allowance per authorized minter. Decremented on
    ///         every bridgeMint(). MINTER_ADMIN_ROLE replenishes.
    mapping(address => uint256) public mintAllowance;

    /// @notice Monotonic withdrawal id per token instance.
    uint256 public lastWithdrawalId;

    /// @notice Per-sender nonce, monotonic. Used for off-chain dedup.
    mapping(address => uint256) public withdrawalNonce;

    // -------------------------------------------------------------------- //
    //                              EVENTS                                  //
    // -------------------------------------------------------------------- //

    event MintAllowanceSet(address indexed minter, uint256 newAllowance, uint256 previousAllowance);

    // -------------------------------------------------------------------- //
    //                            CONSTRUCTOR                               //
    // -------------------------------------------------------------------- //

    /// @param _admin           Initial DEFAULT_ADMIN_ROLE (multisig).
    /// @param _minterAdmin     Initial MINTER_ADMIN_ROLE.
    /// @param _pauser          Initial PAUSER_ROLE.
    /// @param _initialMinter   Initial BRIDGE_MINTER_ROLE holder (bridge contract or relayer EOA).
    /// @param _initialAllowance Initial mint allowance for _initialMinter (e.g. testnet cap).
    constructor(
        address _admin,
        address _minterAdmin,
        address _pauser,
        address _initialMinter,
        uint256 _initialAllowance
    ) ERC20("Sentrix Bridged USDC", "sUSDC") {
        require(_admin != address(0), "admin=0");
        require(_minterAdmin != address(0), "minterAdmin=0");
        require(_pauser != address(0), "pauser=0");
        require(_initialMinter != address(0), "initialMinter=0");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MINTER_ADMIN_ROLE, _minterAdmin);
        _grantRole(PAUSER_ROLE, _pauser);
        _grantRole(BRIDGE_MINTER_ROLE, _initialMinter);

        if (_initialAllowance > 0) {
            mintAllowance[_initialMinter] = _initialAllowance;
            emit MintAllowanceSet(_initialMinter, _initialAllowance, 0);
        }
    }

    /// @notice 6 decimals to match USDC convention. Constant.
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    // -------------------------------------------------------------------- //
    //                          BRIDGE MINT/BURN                            //
    // -------------------------------------------------------------------- //

    /// @inheritdoc ISentrixBridgedUSDC
    function bridgeMint(uint256 depositId, uint256 sourceChainId, address recipient, uint256 amount)
        external
        override
        onlyRole(BRIDGE_MINTER_ROLE)
        whenNotPaused
    {
        require(recipient != address(0), "recipient=0");
        require(amount > 0, "amount=0");

        uint256 remaining = mintAllowance[msg.sender];
        require(amount <= remaining, "mint allowance exceeded");
        mintAllowance[msg.sender] = remaining - amount;

        emit BridgeMint(depositId, sourceChainId, recipient, amount);

        _mint(recipient, amount);
    }

    /// @inheritdoc ISentrixBridgedUSDC
    function burnForWithdrawal(address recipient, uint256 amount, uint256 destinationChainId)
        external
        override
        whenNotPaused
        returns (uint256 withdrawalId)
    {
        require(recipient != address(0), "recipient=0");
        require(amount > 0, "amount=0");
        require(destinationChainId != 0, "dstChain=0");

        withdrawalId = ++lastWithdrawalId;
        uint256 nonce = ++withdrawalNonce[msg.sender];

        emit WithdrawRequested({
            withdrawalId: withdrawalId,
            sentrixChainId: block.chainid,
            destinationChainId: destinationChainId,
            sender: msg.sender,
            recipient: recipient,
            amount: amount,
            nonce: nonce
        });

        _burn(msg.sender, amount);
    }

    // -------------------------------------------------------------------- //
    //                        MINTER CONFIG ADMIN                           //
    // -------------------------------------------------------------------- //

    /// @notice Set the mint allowance for a specific minter. Use to grant,
    ///         revoke (set 0), or replenish.
    /// @dev    The role itself is separate from the allowance — even if a
    ///         minter has BRIDGE_MINTER_ROLE, they can't mint with zero
    ///         allowance.
    function setMintAllowance(address minter, uint256 newAllowance) external onlyRole(MINTER_ADMIN_ROLE) {
        require(minter != address(0), "minter=0");
        uint256 previous = mintAllowance[minter];
        mintAllowance[minter] = newAllowance;
        emit MintAllowanceSet(minter, newAllowance, previous);
    }

    // -------------------------------------------------------------------- //
    //                              PAUSE                                   //
    // -------------------------------------------------------------------- //

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // -------------------------------------------------------------------- //
    //                       SUPER FUNCTION RESOLUTION                      //
    // -------------------------------------------------------------------- //

    /// @dev Required override because ERC20Pausable also defines _beforeTokenTransfer.
    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._beforeTokenTransfer(from, to, amount);
    }
}
