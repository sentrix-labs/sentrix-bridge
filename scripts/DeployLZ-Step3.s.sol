// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

import {Treasury} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/Treasury.sol";
import {PriceFeed} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/PriceFeed.sol";

/// @notice Step-3 deployment of supporting contracts on Sentrix testnet.
///         Deploys Treasury + PriceFeed (non-upgradeable for testnet — PriceFeed's
///         `Proxied` modifier is bypassed by calling initialize directly on the
///         implementation; acceptable for testnet, must be re-deployed with a real
///         proxy before any mainnet rollout).
///
///         The actual broadcast is via `cast send --create` per the runbook
///         (forge script fork-sim still trips on Sentrix RPC).
///         This script's purpose is to (a) get the artifacts compiled so the
///         deployment one-liner has bytecode + ABI available, and (b) document
///         the constructor + initializer signatures for future reference.
contract DeployLZStep3 is Script {
    function run() external pure {
        revert("Use cast send --create per docs/runbook-step3-broadcast.md");
    }
}
