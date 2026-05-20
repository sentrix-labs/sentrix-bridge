// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console2} from "forge-std/Script.sol";
import {SentrixBridgedUSDC} from "../../src/stablecoin/SentrixBridgedUSDC.sol";

/// @notice Deploy SentrixBridgedUSDC (sUSDC). Use on Sentrix testnet (7120)
///         or mainnet (7119).
///
/// Env required:
///   - DEPLOYER_PK
///   - TOKEN_ADMIN        (DEFAULT_ADMIN_ROLE; multisig recommended)
///   - TOKEN_MINTER_ADMIN (MINTER_ADMIN_ROLE; can update mint allowances)
///   - TOKEN_PAUSER       (PAUSER_ROLE)
///   - INITIAL_MINTER     (BRIDGE_MINTER_ROLE; bridge contract OR relayer EOA)
///   - INITIAL_ALLOWANCE  (initial cap for INITIAL_MINTER, in 6-decimal units)
///
/// Mainnet guard: refuses chainid 7119 unless ALLOW_MAINNET_DEPLOY=1.
contract DeploySentrixBridgedUSDC is Script {
    function run() external returns (address token) {
        if (block.chainid == 7119) {
            require(
                vm.envOr("ALLOW_MAINNET_DEPLOY", false),
                "Mainnet deploy requires ALLOW_MAINNET_DEPLOY=1"
            );
        }

        address admin = vm.envAddress("TOKEN_ADMIN");
        address minterAdmin = vm.envAddress("TOKEN_MINTER_ADMIN");
        address pauser = vm.envAddress("TOKEN_PAUSER");
        address initialMinter = vm.envAddress("INITIAL_MINTER");
        uint256 initialAllowance = vm.envUint("INITIAL_ALLOWANCE");

        require(admin != address(0), "TOKEN_ADMIN=0");
        require(minterAdmin != address(0), "TOKEN_MINTER_ADMIN=0");
        require(pauser != address(0), "TOKEN_PAUSER=0");
        require(initialMinter != address(0), "INITIAL_MINTER=0");

        uint256 pk = vm.envUint("DEPLOYER_PK");
        vm.startBroadcast(pk);
        SentrixBridgedUSDC deployed = new SentrixBridgedUSDC(
            admin,
            minterAdmin,
            pauser,
            initialMinter,
            initialAllowance
        );
        vm.stopBroadcast();

        token = address(deployed);
        console2.log("SentrixBridgedUSDC:", token);
        console2.log("  admin:           ", admin);
        console2.log("  minterAdmin:     ", minterAdmin);
        console2.log("  pauser:          ", pauser);
        console2.log("  initialMinter:   ", initialMinter);
        console2.log("  initialAllowance:", initialAllowance);
    }
}
