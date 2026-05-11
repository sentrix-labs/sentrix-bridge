// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

import {EndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import {SendUln302} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/uln302/SendUln302.sol";
import {ReceiveUln302} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/uln302/ReceiveUln302.sol";

/// @notice Step-1 minimum deployment of LayerZero V2 core contracts to Sentrix testnet.
///         Deploys EndpointV2 + SendUln302 + ReceiveUln302 only. PriceFeed (upgradeable
///         proxy pattern), Executor, Treasury, and DVN registration are Step-2+ work.
///
///         EID note: LayerZero assigns EIDs centrally. 40998 is a placeholder for
///         Sentrix Testnet (chain 7120) until LayerZero Labs assigns the official ID
///         through their chain integration process. The eid is immutable in
///         EndpointV2.constructor — once deployed, redeploy is required to change it.
///
///         Usage:
///           forge script scripts/DeployLZ-SentrixTestnet.s.sol:DeployLZSentrixTestnet \
///             --rpc-url sentrix_testnet \
///             --private-key $DEPLOYER_PK \
///             --broadcast \
///             --legacy
contract DeployLZSentrixTestnet is Script {
    // Placeholder EID for Sentrix Testnet. Coordinate with LayerZero Labs to claim
    // an official EID before any cross-chain wiring.
    uint32 constant SENTRIX_TESTNET_EID = 40998;

    // SendUln302 gas accounting params — values mirror LZ's documented defaults
    // for new chains. Treasury isn't wired here so these are placeholders that
    // make the contract deployable; refine when Treasury comes online.
    uint256 constant TREASURY_GAS_LIMIT = 1_000_000;
    uint256 constant TREASURY_GAS_FOR_FEE_CAP = 1_000_000_000;

    function run() external {
        address deployer = vm.addr(vm.envUint("DEPLOYER_PK"));
        console2.log("Deployer:", deployer);
        console2.log("Chain ID:", block.chainid);
        require(block.chainid == 7120, "DeployLZSentrixTestnet: expected chain 7120 (Sentrix Testnet)");

        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));

        // 1. EndpointV2 — owner = deployer, can transfer later to SentrixSafe.
        EndpointV2 endpoint = new EndpointV2(SENTRIX_TESTNET_EID, deployer);
        console2.log("EndpointV2 deployed:", address(endpoint));

        // 2. SendUln302 — outbound message library, references endpoint.
        SendUln302 sendLib = new SendUln302(
            address(endpoint),
            TREASURY_GAS_LIMIT,
            TREASURY_GAS_FOR_FEE_CAP
        );
        console2.log("SendUln302 deployed:", address(sendLib));

        // 3. ReceiveUln302 — inbound message library, references endpoint.
        ReceiveUln302 receiveLib = new ReceiveUln302(address(endpoint));
        console2.log("ReceiveUln302 deployed:", address(receiveLib));

        // 4. Register libraries in the endpoint registry. Required before
        //    setSendLibrary / setReceiveLibrary can point an OApp at them.
        endpoint.registerLibrary(address(sendLib));
        endpoint.registerLibrary(address(receiveLib));
        console2.log("Libraries registered in EndpointV2");

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Sentrix Testnet LayerZero V2 deployment complete ===");
        console2.log("  EID:          ", SENTRIX_TESTNET_EID);
        console2.log("  EndpointV2:   ", address(endpoint));
        console2.log("  SendUln302:   ", address(sendLib));
        console2.log("  ReceiveUln302:", address(receiveLib));
        console2.log("");
        console2.log("Next: PriceFeed (upgradeable), Executor, Treasury, then DVN wiring.");
        console2.log("Then submit chain integration request to LayerZero Labs with these addresses.");
    }
}
