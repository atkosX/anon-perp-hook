// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {MarginAccount} from "../src/MarginAccount.sol";
import {MockERC20} from "./MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MarginAccountTest is Test {
    MarginAccount marginAccount;
    MockERC20 usdc;
    
    address user1 = address(0x1111);
    address user2 = address(0x2222);
    address authorizedContract = address(0x3333);
    
    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC");
        marginAccount = new MarginAccount(address(usdc));
        
        // Authorize a contract for testing
        vm.prank(marginAccount.owner());
        marginAccount.addAuthorizedContract(authorizedContract);
    }
    
    function testDeposit() public {
        uint256 amount = 1000e6; // 1000 USDC
        
        // Give user USDC
        deal(address(usdc), user1, amount);
        
        // Approve margin account
        vm.prank(user1);
        IERC20(address(usdc)).approve(address(marginAccount), amount);
        
        // Deposit
        vm.prank(user1);
        marginAccount.deposit(amount);
        
        // Verify balance
        assertEq(marginAccount.getAvailableBalance(user1), amount);
        assertEq(marginAccount.getTotalBalance(user1), amount);
    }
    
    function testWithdraw() public {
        uint256 depositAmount = 1000e6;
        uint256 withdrawAmount = 500e6;
        
        // Setup: deposit first
        deal(address(usdc), user1, depositAmount);
        vm.prank(user1);
        IERC20(address(usdc)).approve(address(marginAccount), depositAmount);
        vm.prank(user1);
        marginAccount.deposit(depositAmount);
        
        // Withdraw
        vm.prank(user1);
        marginAccount.withdraw(withdrawAmount);
        
        // Verify balance
        assertEq(marginAccount.getAvailableBalance(user1), depositAmount - withdrawAmount);
        assertEq(IERC20(address(usdc)).balanceOf(user1), withdrawAmount);
    }
    
    function testLockMargin() public {
        uint256 amount = 1000e6;
        
        // Setup: deposit first
        deal(address(usdc), user1, amount);
        vm.prank(user1);
        IERC20(address(usdc)).approve(address(marginAccount), amount);
        vm.prank(user1);
        marginAccount.deposit(amount);
        
        // Lock margin (only authorized contracts can do this)
        vm.prank(authorizedContract);
        marginAccount.lockMargin(user1, amount);
        
        // Verify locked
        assertEq(marginAccount.getLockedBalance(user1), amount);
        assertEq(marginAccount.getAvailableBalance(user1), 0);
    }
    
    function testUnlockMargin() public {
        uint256 amount = 1000e6;
        
        // Setup: deposit and lock
        deal(address(usdc), user1, amount);
        vm.prank(user1);
        IERC20(address(usdc)).approve(address(marginAccount), amount);
        vm.prank(user1);
        marginAccount.deposit(amount);
        
        vm.prank(authorizedContract);
        marginAccount.lockMargin(user1, amount);
        
        // Unlock
        vm.prank(authorizedContract);
        marginAccount.unlockMargin(user1, amount);
        
        // Verify unlocked
        assertEq(marginAccount.getLockedBalance(user1), 0);
        assertEq(marginAccount.getAvailableBalance(user1), amount);
    }
    
    function testTransferBetweenUsers() public {
        uint256 amount = 1000e6;
        
        // Setup: user1 deposits
        deal(address(usdc), user1, amount);
        vm.prank(user1);
        IERC20(address(usdc)).approve(address(marginAccount), amount);
        vm.prank(user1);
        marginAccount.deposit(amount);
        
        // Transfer from user1 to user2 (only authorized contracts)
        vm.prank(authorizedContract);
        marginAccount.transferBetweenUsers(user1, user2, amount);
        
        // Verify transfer
        assertEq(marginAccount.getAvailableBalance(user1), 0);
        assertEq(marginAccount.getAvailableBalance(user2), amount);
    }
    
    function test_RevertWhen_LockMarginUnauthorized() public {
        uint256 amount = 1000e6;
        
        deal(address(usdc), user1, amount);
        vm.prank(user1);
        IERC20(address(usdc)).approve(address(marginAccount), amount);
        vm.prank(user1);
        marginAccount.deposit(amount);
        
        // Try to lock from unauthorized address (should fail)
        vm.prank(user2);
        vm.expectRevert();
        marginAccount.lockMargin(user1, amount);
    }
    
    function test_RevertWhen_LockMarginInsufficientBalance() public {
        uint256 depositAmount = 500e6;
        uint256 lockAmount = 1000e6;
        
        deal(address(usdc), user1, depositAmount);
        vm.prank(user1);
        IERC20(address(usdc)).approve(address(marginAccount), depositAmount);
        vm.prank(user1);
        marginAccount.deposit(depositAmount);
        
        // Try to lock more than available (should fail)
        vm.prank(authorizedContract);
        vm.expectRevert();
        marginAccount.lockMargin(user1, lockAmount);
    }
}

