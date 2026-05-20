// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console2} from "forge-std/Script.sol";
import {StaticMessageIdMultisigIsmFactory} from "../hyperlane/hyperlane-monorepo/solidity/contracts/isms/multisig/StaticMultisigIsm.sol";

/// @notice Deploy Hyperlane StaticMessageIdMultisigIsmFactory for testnet use.
/// Mainnet deployment is blocked unless explicitly overridden.
contract DeployMessageIdMultisigIsmFactory is Script {
    function run() external {
        if (block.chainid == 1 || block.chainid == 7119 || block.chainid == 8453) {
            require(
                vm.envOr("ALLOW_MAINNET_ISM_DEPLOY", false),
                "Mainnet ISM factory deploy blocked"
            );
        }
        require(block.chainid == 7120, "Factory deploy script is Sentrix Testnet only");

        uint256 deployerPk = vm.envUint("DEPLOYER_PK");
        vm.startBroadcast(deployerPk);
        StaticMessageIdMultisigIsmFactory factory = new StaticMessageIdMultisigIsmFactory();
        vm.stopBroadcast();

        console2.log("StaticMessageIdMultisigIsmFactory deployed:");
        console2.log("  chain:", block.chainid);
        console2.log("  factory:", address(factory));
        console2.log("  implementation:", factory.implementation());
    }
}
