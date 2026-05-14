// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {SentrixBridgedUSDC} from "../../src/stablecoin/SentrixBridgedUSDC.sol";

contract SentrixBridgedUSDCTest is Test {
    SentrixBridgedUSDC internal token;

    address internal admin = address(0xA0);
    address internal minterAdmin = address(0xA1);
    address internal pauser = address(0xA2);
    address internal bridgeMinter = address(0xB0);
    address internal alice = address(0xC1);
    address internal bob = address(0xC2);
    address internal recipient = address(0xD0);

    uint256 internal constant INITIAL_ALLOWANCE = 10_000e6; // 10k sUSDC cap
    uint256 internal constant DST_CHAIN = 1; // Ethereum mainnet for example
    uint256 internal constant SRC_CHAIN = 1; // example source

    event BridgeMint(
        uint256 indexed depositId,
        uint256 indexed sourceChainId,
        address indexed recipient,
        uint256 amount
    );

    event WithdrawRequested(
        uint256 indexed withdrawalId,
        uint256 sentrixChainId,
        uint256 indexed destinationChainId,
        address indexed sender,
        address recipient,
        uint256 amount,
        uint256 nonce
    );

    event MintAllowanceSet(address indexed minter, uint256 newAllowance, uint256 previousAllowance);

    function setUp() public {
        token = new SentrixBridgedUSDC(admin, minterAdmin, pauser, bridgeMinter, INITIAL_ALLOWANCE);
    }

    // ----- constructor -----

    function test_constructor_metadata_and_roles() public {
        assertEq(token.name(), "Sentrix Bridged USDC");
        assertEq(token.symbol(), "sUSDC");
        assertEq(token.decimals(), 6);
        assertEq(token.totalSupply(), 0);
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ADMIN_ROLE(), minterAdmin));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), pauser));
        assertTrue(token.hasRole(token.BRIDGE_MINTER_ROLE(), bridgeMinter));
        assertEq(token.mintAllowance(bridgeMinter), INITIAL_ALLOWANCE);
    }

    function test_constructor_rejects_zero_args() public {
        vm.expectRevert(bytes("admin=0"));
        new SentrixBridgedUSDC(address(0), minterAdmin, pauser, bridgeMinter, INITIAL_ALLOWANCE);
        vm.expectRevert(bytes("minterAdmin=0"));
        new SentrixBridgedUSDC(admin, address(0), pauser, bridgeMinter, INITIAL_ALLOWANCE);
        vm.expectRevert(bytes("pauser=0"));
        new SentrixBridgedUSDC(admin, minterAdmin, address(0), bridgeMinter, INITIAL_ALLOWANCE);
        vm.expectRevert(bytes("initialMinter=0"));
        new SentrixBridgedUSDC(admin, minterAdmin, pauser, address(0), INITIAL_ALLOWANCE);
    }

    // ----- mint -----

    function test_unauthorized_mint_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        token.bridgeMint(1, SRC_CHAIN, recipient, 1e6);
    }

    function test_authorized_minter_can_mint_and_emits() public {
        vm.expectEmit(true, true, true, true);
        emit BridgeMint(7, SRC_CHAIN, recipient, 100e6);
        vm.prank(bridgeMinter);
        token.bridgeMint(7, SRC_CHAIN, recipient, 100e6);
        assertEq(token.balanceOf(recipient), 100e6);
        assertEq(token.totalSupply(), 100e6);
        assertEq(token.mintAllowance(bridgeMinter), INITIAL_ALLOWANCE - 100e6);
    }

    function test_mint_zero_amount_reverts() public {
        vm.prank(bridgeMinter);
        vm.expectRevert(bytes("amount=0"));
        token.bridgeMint(1, SRC_CHAIN, recipient, 0);
    }

    function test_mint_zero_recipient_reverts() public {
        vm.prank(bridgeMinter);
        vm.expectRevert(bytes("recipient=0"));
        token.bridgeMint(1, SRC_CHAIN, address(0), 1e6);
    }

    function test_mint_allowance_enforced() public {
        vm.prank(bridgeMinter);
        token.bridgeMint(1, SRC_CHAIN, recipient, INITIAL_ALLOWANCE);
        assertEq(token.mintAllowance(bridgeMinter), 0);

        // next mint should fail
        vm.prank(bridgeMinter);
        vm.expectRevert(bytes("mint allowance exceeded"));
        token.bridgeMint(2, SRC_CHAIN, recipient, 1);
    }

    function test_minter_with_role_but_zero_allowance_cannot_mint() public {
        address otherMinter = address(0xBE);
        bytes32 minterRole = token.BRIDGE_MINTER_ROLE();
        vm.prank(admin);
        token.grantRole(minterRole, otherMinter);
        // role granted but allowance is 0
        vm.prank(otherMinter);
        vm.expectRevert(bytes("mint allowance exceeded"));
        token.bridgeMint(1, SRC_CHAIN, recipient, 1);
    }

    // ----- setMintAllowance -----

    function test_setMintAllowance_unauthorized_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        token.setMintAllowance(bridgeMinter, 1e6);
    }

    function test_setMintAllowance_authorized_succeeds_and_emits() public {
        vm.expectEmit(true, true, true, true);
        emit MintAllowanceSet(bridgeMinter, 5_000e6, INITIAL_ALLOWANCE);
        vm.prank(minterAdmin);
        token.setMintAllowance(bridgeMinter, 5_000e6);
        assertEq(token.mintAllowance(bridgeMinter), 5_000e6);
    }

    function test_setMintAllowance_zero_minter_reverts() public {
        vm.prank(minterAdmin);
        vm.expectRevert(bytes("minter=0"));
        token.setMintAllowance(address(0), 1);
    }

    function test_setMintAllowance_can_revoke_to_zero() public {
        vm.prank(minterAdmin);
        token.setMintAllowance(bridgeMinter, 0);
        assertEq(token.mintAllowance(bridgeMinter), 0);
        // minter role still present but cannot mint
        vm.prank(bridgeMinter);
        vm.expectRevert(bytes("mint allowance exceeded"));
        token.bridgeMint(1, SRC_CHAIN, recipient, 1);
    }

    // ----- burn-for-withdrawal -----

    function test_burnForWithdrawal_succeeds_and_emits() public {
        // seed
        vm.prank(bridgeMinter);
        token.bridgeMint(1, SRC_CHAIN, alice, 500e6);

        vm.expectEmit(true, true, true, true);
        emit WithdrawRequested({
            withdrawalId: 1,
            sentrixChainId: block.chainid,
            destinationChainId: DST_CHAIN,
            sender: alice,
            recipient: recipient,
            amount: 200e6,
            nonce: 1
        });

        vm.prank(alice);
        uint256 wid = token.burnForWithdrawal(recipient, 200e6, DST_CHAIN);

        assertEq(wid, 1);
        assertEq(token.balanceOf(alice), 300e6);
        assertEq(token.totalSupply(), 300e6);
        assertEq(token.withdrawalNonce(alice), 1);
    }

    function test_burnForWithdrawal_zero_amount_reverts() public {
        vm.prank(alice);
        vm.expectRevert(bytes("amount=0"));
        token.burnForWithdrawal(recipient, 0, DST_CHAIN);
    }

    function test_burnForWithdrawal_zero_recipient_reverts() public {
        vm.prank(alice);
        vm.expectRevert(bytes("recipient=0"));
        token.burnForWithdrawal(address(0), 1e6, DST_CHAIN);
    }

    function test_burnForWithdrawal_zero_dst_chain_reverts() public {
        vm.prank(alice);
        vm.expectRevert(bytes("dstChain=0"));
        token.burnForWithdrawal(recipient, 1e6, 0);
    }

    function test_burnForWithdrawal_no_balance_reverts() public {
        // alice has 0 balance — ERC20 will revert
        vm.prank(alice);
        vm.expectRevert();
        token.burnForWithdrawal(recipient, 1e6, DST_CHAIN);
    }

    // ----- pause -----

    function test_pause_unauthorized_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        token.pause();
    }

    function test_pause_blocks_mint_burn_transfer() public {
        // seed
        vm.prank(bridgeMinter);
        token.bridgeMint(1, SRC_CHAIN, alice, 100e6);

        vm.prank(pauser);
        token.pause();

        // mint blocked — whenNotPaused modifier fires before _mint
        vm.prank(bridgeMinter);
        vm.expectRevert("Pausable: paused");
        token.bridgeMint(2, SRC_CHAIN, alice, 1);

        // burn blocked — whenNotPaused modifier fires before _burn
        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        token.burnForWithdrawal(recipient, 1, DST_CHAIN);

        // plain ERC20 transfer blocked via ERC20Pausable._beforeTokenTransfer
        vm.prank(alice);
        vm.expectRevert("ERC20Pausable: token transfer while paused");
        token.transfer(bob, 1);

        // unpause restores
        vm.prank(pauser);
        token.unpause();

        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 1);
    }

    // ----- role transfer -----

    function test_admin_can_grant_revoke_minter() public {
        address newMinter = address(0xBB);
        bytes32 minterRole = token.BRIDGE_MINTER_ROLE();

        vm.prank(admin);
        token.grantRole(minterRole, newMinter);

        // grant allowance
        vm.prank(minterAdmin);
        token.setMintAllowance(newMinter, 1_000e6);

        // new minter can mint
        vm.prank(newMinter);
        token.bridgeMint(1, SRC_CHAIN, recipient, 100e6);
        assertEq(token.balanceOf(recipient), 100e6);

        // revoke
        vm.prank(admin);
        token.revokeRole(minterRole, newMinter);
        // can't mint anymore
        vm.prank(newMinter);
        vm.expectRevert();
        token.bridgeMint(2, SRC_CHAIN, recipient, 1);
    }
}
