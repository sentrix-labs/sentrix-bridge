// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console2} from "forge-std/Script.sol";

/// @notice Hyperlane v3 StaticMessageIdMultisigIsm minimal interface.
/// Constructor pattern follows the v3 factory: deploy a fresh ISM with
/// (validators[], threshold) immutable. ISM ABI is intentionally narrow —
/// the on-chain swap step is a separate call to `setInterchainSecurityModule(address)`
/// on the warp/recipient contract per `docs/multisigism-setup.md`.
interface IMultisigIsmFactory {
    function deploy(address[] calldata validators, uint8 threshold) external returns (address ism);
}

interface IRecipientWithIsm {
    function setInterchainSecurityModule(address) external;
    function interchainSecurityModule() external view returns (address);
}

/// @notice Deploy a MultisigIsm on the current chain via the operator's
/// chosen factory. Hyperlane Labs' canonical factory address per chain
/// is in the Hyperlane registry. Two modes:
///   - Deploy-only (default) — just deploy the ISM, print the address.
///     Selected when DEPLOY_ONLY=1 OR when SWAP_TARGETS is unset.
///     Operator manually swaps target contracts via `cast send` later.
///     If DEPLOY_ONLY=1 is set explicitly AND SWAP_TARGETS is also set,
///     the script REVERTS — belt-and-suspenders against accidental swap.
///   - Swap mode — set SWAP_TARGETS comma-separated AND leave DEPLOY_ONLY
///     unset (or "0"). Calls setInterchainSecurityModule on each target
///     post-deploy in the same broadcast. Use only when validator set
///     is final.
///
/// Required env:
///   - MULTISIG_ISM_FACTORY: factory address (per-chain, from registry)
///   - MULTISIG_ISM_VALIDATORS: comma-separated validator EOAs
///   - MULTISIG_ISM_THRESHOLD: m of n (uint8)
///   - SWAP_TARGETS: optional comma-separated recipient addresses
///   - DEPLOY_ONLY: optional; "1" forces deploy-only and refuses any swap
///   - DEPLOYER_PK: deployment signer env
///
/// Network guard: defaults to Sentrix Testnet (7120) and Base Sepolia (84532).
/// Mainnet deployment is blocked unless an explicit mainnet override is set.
contract DeployMultisigIsm is Script {
    function run() external {
        if (block.chainid == 1 || block.chainid == 7119 || block.chainid == 8453) {
            require(
                vm.envOr("ALLOW_MAINNET_ISM_DEPLOY", false),
                "Mainnet ISM deploy requires explicit ALLOW_MAINNET_ISM_DEPLOY=1"
            );
        }
        if (block.chainid != 7120 && block.chainid != 84532) {
            require(
                vm.envOr("ALLOW_OTHER_TESTNET_ISM_DEPLOY", false),
                "ISM deploy path is limited to Sentrix Testnet/Base Sepolia by default"
            );
        }

        address factory = vm.envAddress("MULTISIG_ISM_FACTORY");
        require(factory != address(0), "MULTISIG_ISM_FACTORY required");

        address[] memory validators = vm.envAddress("MULTISIG_ISM_VALIDATORS", ",");
        require(validators.length > 0, "MULTISIG_ISM_VALIDATORS required (comma-separated EOAs)");

        uint8 threshold = uint8(vm.envUint("MULTISIG_ISM_THRESHOLD"));
        require(threshold > 0 && threshold <= validators.length, "threshold must be 1..N");

        // Resolve mode BEFORE broadcasting. DEPLOY_ONLY=1 is an explicit
        // operator commitment — refuse swap even if SWAP_TARGETS is set
        // in the same env (e.g. leftover from a prior shell). When
        // DEPLOY_ONLY is unset, we default to deploy-only and only swap
        // if SWAP_TARGETS is provided.
        bool deployOnly = vm.envOr("DEPLOY_ONLY", false);
        string memory targetsStr = vm.envOr("SWAP_TARGETS", string(""));
        bool hasTargets = bytes(targetsStr).length > 0;
        if (deployOnly && hasTargets) {
            revert("DEPLOY_ONLY=1 set but SWAP_TARGETS also provided; refusing to swap. Unset one.");
        }

        uint256 deployerPk = vm.envUint("DEPLOYER_PK");
        vm.startBroadcast(deployerPk);

        // Deploy ISM via factory.
        address ism = IMultisigIsmFactory(factory).deploy(validators, threshold);
        console2.log("MultisigIsm deployed:");
        console2.log("  chain:", block.chainid);
        console2.log("  factory:", factory);
        console2.log("  ism:", ism);
        console2.log("  threshold:", threshold);
        console2.log("  validators (count):", validators.length);
        for (uint256 i = 0; i < validators.length; i++) {
            console2.log("    validator[i]:", validators[i]);
        }

        // Optional swap targets — only run if explicitly requested AND
        // DEPLOY_ONLY did not force deploy-only mode (checked above).
        if (hasTargets) {
            address[] memory targets = vm.envAddress("SWAP_TARGETS", ",");
            console2.log("Swapping ISM on", targets.length, "target(s):");
            for (uint256 i = 0; i < targets.length; i++) {
                address t = targets[i];
                console2.log("  target:", t);
                address before_ism = IRecipientWithIsm(t).interchainSecurityModule();
                console2.log("    pre-ism:", before_ism);
                IRecipientWithIsm(t).setInterchainSecurityModule(ism);
                address after_ism = IRecipientWithIsm(t).interchainSecurityModule();
                console2.log("    post-ism:", after_ism);
                require(after_ism == ism, "ISM swap verify failed");
            }
        } else {
            console2.log("SWAP_TARGETS unset; skipping on-chain swap (deploy-only mode)");
        }

        vm.stopBroadcast();
    }
}
