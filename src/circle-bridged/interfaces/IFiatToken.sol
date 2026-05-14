// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "oz-v4/token/ERC20/IERC20.sol";

/// @title IFiatToken
/// @notice ABI-level interface for interacting with Circle's deployed
///         FiatToken (V2_2) contract. The FiatToken itself is compiled with
///         solc 0.6.12 per Circle Bridged USDC Standard; we interact with the
///         deployed bytecode via this 0.8-compatible interface.
///
/// @dev    Source: https://github.com/circlefin/stablecoin-evm/blob/master/contracts/v2/FiatTokenV2_2.sol
///         + parents FiatTokenV2_1, FiatTokenV2, FiatTokenV1.
///
///         Mirrors `hyperlane-monorepo/solidity/contracts/token/interfaces/IFiatToken.sol`
///         so HypFiatToken adapter integration is straightforward.
interface IFiatToken is IERC20 {
    // ----- minter mechanics (FiatTokenV1) -----

    /// @notice Mints fiat tokens to an address.
    /// @dev    Caller must be a configured minter (`isMinter`), must not be
    ///         blacklisted, and amount must be <= minterAllowance.
    function mint(address _to, uint256 _amount) external returns (bool);

    /// @notice Allows a minter to burn some of its own tokens.
    /// @dev    Caller must be a minter and must not be blacklisted.
    function burn(uint256 _amount) external;

    function minterAllowance(address _minter) external view returns (uint256);
    function isMinter(address _minter) external view returns (bool);

    // ----- masterMinter mechanics -----

    function masterMinter() external view returns (address);

    /// @notice Configure a minter and its allowance.
    /// @dev    Only callable by masterMinter.
    function configureMinter(address _minter, uint256 _minterAllowedAmount)
        external
        returns (bool);

    /// @notice Remove a minter (sets allowance to 0).
    /// @dev    Only callable by masterMinter.
    function removeMinter(address _minter) external returns (bool);

    // ----- pause -----

    function pauser() external view returns (address);
    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);

    // ----- blacklist -----

    function blacklister() external view returns (address);
    function blacklist(address _account) external;
    function unBlacklist(address _account) external;
    function isBlacklisted(address _account) external view returns (bool);

    // ----- rescuer -----

    function rescuer() external view returns (address);
    function rescueERC20(IERC20 tokenContract, address to, uint256 amount) external;

    // ----- owner / role transfer -----

    function owner() external view returns (address);

    /// @notice Transfers the `owner` role.
    /// @dev    Only callable by current owner. After transfer, new owner can
    ///         re-assign masterMinter, pauser, blacklister, rescuer (NOT admin
    ///         — admin is a proxy-level role separate from owner).
    function transferOwnership(address newOwner) external;

    function updateMasterMinter(address _newMasterMinter) external;
    function updatePauser(address _newPauser) external;
    function updateBlacklister(address _newBlacklister) external;
    function updateRescuer(address _newRescuer) external;

    // ----- metadata -----

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

/// @title IFiatTokenProxy
/// @notice Proxy-level admin interface (separate from owner).
/// @dev    Source: circlefin/stablecoin-evm/contracts/upgradeability/AdminUpgradeabilityProxy.sol
///         Only callable when caller IS the admin (proxy intercepts calls).
interface IFiatTokenProxy {
    function admin() external view returns (address);
    function implementation() external view returns (address);
    function changeAdmin(address newAdmin) external;
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}
