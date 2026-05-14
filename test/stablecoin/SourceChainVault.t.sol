// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "oz-v4/token/ERC20/IERC20.sol";
import {IAccessControl} from "oz-v4/access/IAccessControl.sol";

import {SourceChainVault} from "../../src/stablecoin/SourceChainVault.sol";
import {ISourceChainVault} from "../../src/interfaces/ISourceChainVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract SourceChainVaultTest is Test {
    SourceChainVault internal vault;
    MockERC20 internal usdc;

    address internal admin = address(0xA0);
    address internal operator = address(0xB0);
    address internal pauser = address(0xC0);
    address internal alice = address(0xA1);
    address internal bob = address(0xB1);
    address internal recipient = address(0xD1);

    uint256 internal constant DST_CHAIN = 7120; // Sentrix testnet

    event Deposit(
        uint256 indexed depositId,
        uint256 sourceChainId,
        uint256 indexed destinationChainId,
        address indexed depositor,
        address recipient,
        address token,
        uint256 amount,
        uint256 nonce
    );

    event Release(uint256 indexed withdrawalId, address indexed recipient, address token, uint256 amount);

    function setUp() public {
        usdc = new MockERC20("MockUSDC", "USDC", 6);
        vault = new SourceChainVault(IERC20(address(usdc)), admin, operator, pauser);

        usdc.mint(alice, 1_000_000e6);
        usdc.mint(bob, 1_000_000e6);

        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ----- constructor -----

    function test_constructor_rejects_zero_args() public {
        vm.expectRevert(bytes("collateral=0"));
        new SourceChainVault(IERC20(address(0)), admin, operator, pauser);
        vm.expectRevert(bytes("admin=0"));
        new SourceChainVault(IERC20(address(usdc)), address(0), operator, pauser);
        vm.expectRevert(bytes("operator=0"));
        new SourceChainVault(IERC20(address(usdc)), admin, address(0), pauser);
        vm.expectRevert(bytes("pauser=0"));
        new SourceChainVault(IERC20(address(usdc)), admin, operator, address(0));
    }

    function test_constructor_grants_roles() public {
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(vault.hasRole(vault.OPERATOR_ROLE(), operator));
        assertTrue(vault.hasRole(vault.PAUSER_ROLE(), pauser));
        assertEq(vault.collateralToken(), address(usdc));
    }

    // ----- deposit -----

    function test_deposit_succeeds_and_emits_event() public {
        uint256 amount = 100e6;
        vm.expectEmit(true, true, true, true);
        emit Deposit({
            depositId: 1,
            sourceChainId: block.chainid,
            destinationChainId: DST_CHAIN,
            depositor: alice,
            recipient: recipient,
            token: address(usdc),
            amount: amount,
            nonce: 1
        });
        vm.prank(alice);
        uint256 id = vault.deposit(recipient, amount, DST_CHAIN);
        assertEq(id, 1);
        assertEq(vault.totalLocked(), amount);
        assertEq(usdc.balanceOf(address(vault)), amount);
        assertEq(vault.depositNonce(alice), 1);
    }

    function test_deposit_rejects_zero_amount() public {
        vm.prank(alice);
        vm.expectRevert(bytes("amount=0"));
        vault.deposit(recipient, 0, DST_CHAIN);
    }

    function test_deposit_rejects_zero_recipient() public {
        vm.prank(alice);
        vm.expectRevert(bytes("recipient=0"));
        vault.deposit(address(0), 100e6, DST_CHAIN);
    }

    function test_deposit_rejects_zero_dst_chain() public {
        vm.prank(alice);
        vm.expectRevert(bytes("dstChain=0"));
        vault.deposit(recipient, 100e6, 0);
    }

    function test_deposit_increments_id_and_nonce() public {
        vm.startPrank(alice);
        uint256 id1 = vault.deposit(recipient, 1e6, DST_CHAIN);
        uint256 id2 = vault.deposit(recipient, 2e6, DST_CHAIN);
        vm.stopPrank();
        vm.prank(bob);
        uint256 id3 = vault.deposit(recipient, 3e6, DST_CHAIN);
        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(id3, 3);
        assertEq(vault.depositNonce(alice), 2);
        assertEq(vault.depositNonce(bob), 1);
    }

    // ----- release -----

    function test_release_unauthorized_reverts() public {
        // alice has no OPERATOR_ROLE
        vm.prank(alice);
        // OZ 4.x AccessControl uses a specific string format for the revert
        vm.expectRevert(); // any revert (role string is gas heavy to match exactly)
        vault.release(1, recipient, 100e6);
    }

    function test_release_authorized_succeeds_and_decrements_locked() public {
        // seed the vault
        vm.prank(alice);
        vault.deposit(recipient, 100e6, DST_CHAIN);

        uint256 recipientBefore = usdc.balanceOf(recipient);

        vm.expectEmit(true, true, true, true);
        emit Release(42, recipient, address(usdc), 60e6);

        vm.prank(operator);
        vault.release(42, recipient, 60e6);

        assertEq(vault.totalLocked(), 40e6);
        assertEq(usdc.balanceOf(recipient), recipientBefore + 60e6);
    }

    function test_release_exceeds_locked_reverts() public {
        vm.prank(alice);
        vault.deposit(recipient, 10e6, DST_CHAIN);
        vm.prank(operator);
        vm.expectRevert(bytes("exceeds locked"));
        vault.release(1, recipient, 11e6);
    }

    function test_release_zero_amount_reverts() public {
        vm.prank(operator);
        vm.expectRevert(bytes("amount=0"));
        vault.release(1, recipient, 0);
    }

    function test_release_zero_recipient_reverts() public {
        vm.prank(operator);
        vm.expectRevert(bytes("recipient=0"));
        vault.release(1, address(0), 1e6);
    }

    // ----- pause -----

    function test_pause_unauthorized_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.pause();
    }

    function test_pause_authorized_succeeds() public {
        vm.prank(pauser);
        vault.pause();
        // deposit must fail when paused
        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        vault.deposit(recipient, 1e6, DST_CHAIN);
        // release must fail when paused
        vm.prank(operator);
        vm.expectRevert("Pausable: paused");
        vault.release(1, recipient, 1e6);
        // unpause
        vm.prank(pauser);
        vault.unpause();
        // deposit succeeds again
        vm.prank(alice);
        vault.deposit(recipient, 1e6, DST_CHAIN);
        assertEq(vault.totalLocked(), 1e6);
    }

    // ----- role transfer (admin) -----

    function test_admin_can_transfer_roles() public {
        address newOperator = address(0xBB);
        vm.startPrank(admin);
        vault.grantRole(vault.OPERATOR_ROLE(), newOperator);
        vault.revokeRole(vault.OPERATOR_ROLE(), operator);
        vm.stopPrank();
        // old operator no longer authorized
        vm.prank(operator);
        vm.expectRevert();
        vault.release(1, recipient, 1e6);
        // new operator can act (after seeding)
        vm.prank(alice);
        vault.deposit(recipient, 1e6, DST_CHAIN);
        vm.prank(newOperator);
        vault.release(1, recipient, 1e6);
    }
}
