// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {SentrixUSDCSourceBridge} from "../../src/circle-bridged/source/SentrixUSDCSourceBridge.sol";
import {ICircleBridgedUSDCSource} from "../../src/circle-bridged/interfaces/ICircleBridgedUSDCSource.sol";
import {ICircleBridgedUSDCPausable} from "../../src/circle-bridged/interfaces/ICircleBridgedUSDCPausable.sol";
import {MockUSDC} from "../../src/circle-bridged/mocks/MockUSDC.sol";

contract SentrixUSDCSourceBridgeTest is Test {
    SentrixUSDCSourceBridge internal impl;
    SentrixUSDCSourceBridge internal bridge; // proxy-wrapped
    MockUSDC internal usdc;

    address internal admin = address(0xA0);
    address internal operator = address(0xB0);
    address internal pauser = address(0xC0);
    address internal circleBurnCaller = address(0xCC1);
    address internal circleRoleTransferCaller = address(0xCC2);
    address internal alice = address(0xA1);
    address internal bob = address(0xB1);

    uint256 internal constant SENTRIX_CHAIN_ID = 7120;

    event Deposit(
        uint256 indexed depositId,
        uint256 indexed sentrixChainId,
        address indexed depositor,
        address recipient,
        uint256 amount,
        uint256 nonce
    );
    event Release(uint256 indexed withdrawalId, address indexed recipient, uint256 amount);
    event BridgingPaused(address indexed caller);
    event LockedUSDCBurned(address indexed caller, uint256 amount);
    event USDCRolesTransferred(address indexed caller, address indexed newOwner);

    function setUp() public {
        usdc = new MockUSDC();
        impl = new SentrixUSDCSourceBridge();

        // Deploy proxy + initialize
        bytes memory initData = abi.encodeWithSelector(
            SentrixUSDCSourceBridge.initialize.selector,
            address(usdc),
            SENTRIX_CHAIN_ID,
            admin,
            operator,
            pauser
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        bridge = SentrixUSDCSourceBridge(address(proxy));

        // Seed alice
        usdc.mint(alice, 1_000_000e6);
        vm.prank(alice);
        usdc.approve(address(bridge), type(uint256).max);
    }

    // ----- initialization -----

    function test_initialize_rejects_zero_args() public {
        SentrixUSDCSourceBridge fresh = new SentrixUSDCSourceBridge();
        bytes memory bad;

        bad = abi.encodeWithSelector(fresh.initialize.selector, address(0), SENTRIX_CHAIN_ID, admin, operator, pauser);
        vm.expectRevert();
        new ERC1967Proxy(address(fresh), bad);

        bad = abi.encodeWithSelector(fresh.initialize.selector, address(usdc), 0, admin, operator, pauser);
        vm.expectRevert();
        new ERC1967Proxy(address(fresh), bad);
    }

    function test_initialize_grants_roles() public {
        assertTrue(bridge.hasRole(bridge.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(bridge.hasRole(bridge.OPERATOR_ROLE(), operator));
        assertTrue(bridge.hasRole(bridge.PAUSER_ROLE(), pauser));
        assertFalse(bridge.hasRole(bridge.CIRCLE_BURN_ROLE(), circleBurnCaller));
        assertFalse(bridge.hasRole(bridge.CIRCLE_ROLE_TRANSFER_ROLE(), circleRoleTransferCaller));
    }

    function test_cannot_initialize_twice() public {
        vm.expectRevert();
        bridge.initialize(usdc, SENTRIX_CHAIN_ID, admin, operator, pauser);
    }

    // ----- deposit -----

    function test_deposit_locks_usdc_and_emits() public {
        vm.expectEmit(true, true, true, true);
        emit Deposit({
            depositId: 1,
            sentrixChainId: SENTRIX_CHAIN_ID,
            depositor: alice,
            recipient: bob,
            amount: 100e6,
            nonce: 1
        });
        vm.prank(alice);
        uint256 id = bridge.deposit(bob, 100e6);
        assertEq(id, 1);
        assertEq(bridge.totalLocked(), 100e6);
        assertEq(usdc.balanceOf(address(bridge)), 100e6);
        assertEq(bridge.depositNonce(alice), 1);
    }

    function test_deposit_rejects_zero_amount() public {
        vm.prank(alice);
        vm.expectRevert(bytes("amount=0"));
        bridge.deposit(bob, 0);
    }

    function test_deposit_rejects_zero_recipient() public {
        vm.prank(alice);
        vm.expectRevert(bytes("recipient=0"));
        bridge.deposit(address(0), 1e6);
    }

    function test_deposit_paused_reverts() public {
        vm.prank(pauser);
        bridge.pauseBridging();
        vm.prank(alice);
        vm.expectRevert(); // Pausable: paused
        bridge.deposit(bob, 1e6);
    }

    // ----- release -----

    function test_release_unauthorized_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        bridge.release(1, bob, 1e6);
    }

    function test_release_authorized_succeeds() public {
        vm.prank(alice);
        bridge.deposit(bob, 100e6);

        vm.expectEmit(true, true, false, true);
        emit Release(99, bob, 60e6);

        vm.prank(operator);
        bridge.release(99, bob, 60e6);

        assertEq(bridge.totalLocked(), 40e6);
        assertEq(usdc.balanceOf(bob), 60e6);
    }

    function test_release_exceeds_locked_reverts() public {
        vm.prank(alice);
        bridge.deposit(bob, 10e6);
        vm.prank(operator);
        vm.expectRevert(bytes("exceeds locked"));
        bridge.release(1, bob, 11e6);
    }

    function test_release_paused_reverts() public {
        vm.prank(alice);
        bridge.deposit(bob, 100e6);
        vm.prank(pauser);
        bridge.pauseBridging();
        vm.prank(operator);
        vm.expectRevert();
        bridge.release(1, bob, 1e6);
    }

    // ----- pause -----

    function test_pause_unauthorized_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        bridge.pauseBridging();
    }

    function test_pause_emits_and_blocks_deposit() public {
        vm.expectEmit(true, false, false, true);
        emit BridgingPaused(pauser);
        vm.prank(pauser);
        bridge.pauseBridging();
        assertTrue(bridge.bridgingPaused());
    }

    // ----- Circle hooks: burnLockedUSDC -----

    function test_burnLockedUSDC_unauthorized_reverts() public {
        // alice has no CIRCLE_BURN_ROLE
        vm.prank(alice);
        vm.expectRevert();
        bridge.burnLockedUSDC();
    }

    function test_burnLockedUSDC_works_after_circle_grants_role_and_sets_bridge_as_minter() public {
        // seed locked supply
        vm.prank(alice);
        bridge.deposit(bob, 500e6);

        // Circle grants the burn role to its specified address
        bytes32 burnRole = bridge.CIRCLE_BURN_ROLE();
        vm.prank(admin);
        bridge.grantRole(burnRole, circleBurnCaller);

        // Circle also grants the bridge zero-allowance minter role on USDC
        // (simulated; on real chain this is done by Circle via FiatToken.configureMinter)
        usdc.setMinter(address(bridge), true);

        // Circle calls burnLockedUSDC
        vm.expectEmit(true, false, false, true);
        emit LockedUSDCBurned(circleBurnCaller, 500e6);

        vm.prank(circleBurnCaller);
        bridge.burnLockedUSDC();

        assertEq(bridge.totalLocked(), 0);
        assertEq(usdc.balanceOf(address(bridge)), 0);
    }

    function test_burnLockedUSDC_no_balance_reverts() public {
        bytes32 burnRole = bridge.CIRCLE_BURN_ROLE();
        vm.prank(admin);
        bridge.grantRole(burnRole, circleBurnCaller);
        vm.prank(circleBurnCaller);
        vm.expectRevert(bytes("nothing to burn"));
        bridge.burnLockedUSDC();
    }

    // ----- Circle hooks: transferUSDCRoles (Phase 1 scaffold reverts) -----

    function test_transferUSDCRoles_unauthorized_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        bridge.transferUSDCRoles(address(0xDEAD));
    }

    function test_transferUSDCRoles_phase1_reverts_with_documented_message() public {
        bytes32 rtRole = bridge.CIRCLE_ROLE_TRANSFER_ROLE();
        vm.prank(admin);
        bridge.grantRole(rtRole, circleRoleTransferCaller);

        vm.prank(circleRoleTransferCaller);
        vm.expectRevert(bytes("Phase 2: Hyperlane wiring required for cross-chain role transfer"));
        bridge.transferUSDCRoles(address(0xDEAD));
    }

    function test_transferUSDCRoles_zero_newOwner_reverts() public {
        bytes32 rtRole = bridge.CIRCLE_ROLE_TRANSFER_ROLE();
        vm.prank(admin);
        bridge.grantRole(rtRole, circleRoleTransferCaller);

        vm.prank(circleRoleTransferCaller);
        vm.expectRevert(bytes("newOwner=0"));
        bridge.transferUSDCRoles(address(0));
    }

    // ----- role transfer -----

    function test_admin_can_grant_and_revoke_operator() public {
        address newOp = address(0xBE);
        bytes32 opRole = bridge.OPERATOR_ROLE();
        vm.prank(admin);
        bridge.grantRole(opRole, newOp);
        assertTrue(bridge.hasRole(opRole, newOp));

        vm.prank(admin);
        bridge.revokeRole(opRole, newOp);
        assertFalse(bridge.hasRole(opRole, newOp));
    }
}
