// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "oz-v4/token/ERC20/IERC20.sol";
import {SourceChainVault} from "../../src/stablecoin/SourceChainVault.sol";

/// @notice Deploy the source-chain vault. Use on Sepolia / Ethereum mainnet.
///
/// Env required:
///   - DEPLOYER_PK
///   - COLLATERAL_TOKEN   (USDC address on source chain)
///   - VAULT_ADMIN        (multisig recommended)
///   - VAULT_OPERATOR     (multisig REQUIRED for production)
///   - VAULT_PAUSER       (multisig recommended)
///
/// Mainnet guard: refuses chainid 1 unless ALLOW_MAINNET_DEPLOY=1.
contract DeploySourceChainVault is Script {
    function run() external returns (address vault) {
        if (block.chainid == 1) {
            require(
                vm.envOr("ALLOW_MAINNET_DEPLOY", false),
                "Mainnet deploy requires ALLOW_MAINNET_DEPLOY=1"
            );
        }

        address collateral = vm.envAddress("COLLATERAL_TOKEN");
        address admin = vm.envAddress("VAULT_ADMIN");
        address operator = vm.envAddress("VAULT_OPERATOR");
        address pauser = vm.envAddress("VAULT_PAUSER");

        require(collateral != address(0), "COLLATERAL_TOKEN=0");
        require(admin != address(0), "VAULT_ADMIN=0");
        require(operator != address(0), "VAULT_OPERATOR=0");
        require(pauser != address(0), "VAULT_PAUSER=0");

        uint256 pk = vm.envUint("DEPLOYER_PK");
        vm.startBroadcast(pk);
        SourceChainVault deployed = new SourceChainVault(IERC20(collateral), admin, operator, pauser);
        vm.stopBroadcast();

        vault = address(deployed);
        console2.log("SourceChainVault:", vault);
        console2.log("  collateral:", collateral);
        console2.log("  admin:     ", admin);
        console2.log("  operator:  ", operator);
        console2.log("  pauser:    ", pauser);
    }
}
