// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {PositionManager} from "../src/PositionManager.sol";
import {PositionFactory} from "../src/PositionFactory.sol";
import {PositionNFT} from "../src/PositionNFT.sol";
import {MarketManager} from "../src/MarketManager.sol";
import {MarginAccount} from "../src/MarginAccount.sol";
import {PositionLib} from "../src/libraries/PositionLib.sol";
import {MockERC20} from "./MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PositionManagerTest is Test {
    MarginAccount marginAccount;
    PositionFactory positionFactory;
    PositionNFT positionNFT;
    MarketManager marketManager;
    PositionManager positionManager;
    MockERC20 usdc;
    
    address user1 = address(0x1111);
    address user2 = address(0x2222);
    
    bytes32 constant ETH_USDC_MARKET = keccak256("ETH/USDC");
    uint256 constant TEST_MARGIN = 1000e6; // 1000 USDC
    int256 constant TEST_SIZE = 1e18; // 1 ETH
    uint256 constant TEST_PRICE = 2000e18; // $2000
    
    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC");
        marginAccount = new MarginAccount(address(usdc));
        positionFactory = new PositionFactory(address(usdc), address(marginAccount));
        positionNFT = new PositionNFT();
        marketManager = new MarketManager();
        positionManager = new PositionManager(
            address(positionFactory),
            address(positionNFT),
            address(marketManager)
        );
        
        // Configure relationships
        positionNFT.setFactory(address(positionFactory));
        positionFactory.setPositionNFT(address(positionNFT));
        marginAccount.addAuthorizedContract(address(positionFactory));
        
        // Authorize PositionManager in factory (needed for updatePosition calls)
        vm.prank(positionFactory.owner());
        positionFactory.addAuthorizedContract(address(positionManager));
        
        // PositionManager.updatePosition calls factory.updatePosition which requires authorization
        // So we need to authorize PositionManager in the factory
        vm.prank(positionFactory.owner());
        positionFactory.addAuthorizedContract(address(positionManager));
        
        // Setup market
        marketManager.addMarket(
            ETH_USDC_MARKET,
            address(0x123), // Mock ETH
            address(usdc),
            address(0x456)  // Mock pool
        );
        
        positionFactory.addMarket(
            ETH_USDC_MARKET,
            address(0x123),
            address(usdc),
            address(0x456)
        );
        
        // Setup user with margin
        usdc.mint(user1, 10000e6);
        vm.prank(user1);
        usdc.approve(address(marginAccount), type(uint256).max);
        vm.prank(user1);
        marginAccount.deposit(5000e6);
    }
    
    function testOpenPosition() public {
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_SIZE,
            TEST_PRICE,
            TEST_MARGIN
        );
        
        // Verify position
        assertGt(tokenId, 0);
        assertEq(positionNFT.ownerOf(tokenId), user1);
        
        // Verify position data
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        assertEq(position.owner, user1);
        assertEq(position.margin, TEST_MARGIN);
        assertEq(position.sizeBase, TEST_SIZE);
        assertEq(position.entryPrice, TEST_PRICE);
    }
    
    function testUpdatePosition() public {
        // Open position first
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_SIZE,
            TEST_PRICE,
            TEST_MARGIN
        );
        
        // Update position
        // Note: PositionManager.updatePosition has onlyAuthorized modifier
        // This means only authorized contracts (like the hook) can call it
        // For user-initiated updates, we need to authorize the caller or use a different approach
        // Since uniperp allows direct user calls, let's authorize user1's address as a contract
        // (In production, the hook would handle this)
        int256 newSize = TEST_SIZE / 2;
        uint256 newMargin = TEST_MARGIN / 2;
        
        // Authorize user1's address in PositionManager (simulating hook authorization)
        // In real scenario, the hook would be authorized and handle user updates
        vm.prank(positionManager.owner());
        positionManager.addAuthorizedContract(user1);
        
        // Now user1 can call updatePosition
        vm.prank(user1);
        bool success = positionManager.updatePosition(tokenId, newSize, newMargin);
        assertTrue(success);
        
        // Verify update
        PositionLib.Position memory updated = positionManager.getPosition(tokenId);
        assertEq(updated.sizeBase, newSize);
        assertEq(updated.margin, newMargin);
    }
    
    function testClosePosition() public {
        // Open position first
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_SIZE,
            TEST_PRICE,
            TEST_MARGIN
        );
        
        // Close position
        uint256 exitPrice = TEST_PRICE + 100e18; // Profit scenario
        vm.prank(user1);
        positionManager.closePosition(tokenId, exitPrice);
        
        // Verify position was deleted and NFT burned
        vm.expectRevert();
        positionNFT.ownerOf(tokenId);
    }
    
    function testAddMargin() public {
        // Open position first
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_SIZE,
            TEST_PRICE,
            TEST_MARGIN
        );
        
        // Add more margin
        uint256 additionalMargin = 500e6;
        usdc.mint(user1, additionalMargin);
        vm.prank(user1);
        usdc.approve(address(marginAccount), additionalMargin);
        vm.prank(user1);
        marginAccount.deposit(additionalMargin);
        
        vm.prank(user1);
        positionManager.addMargin(tokenId, additionalMargin);
        
        // Verify margin increased
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        assertEq(position.margin, TEST_MARGIN + additionalMargin);
    }
    
    function testRemoveMargin() public {
        // Open position first
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_SIZE,
            TEST_PRICE,
            TEST_MARGIN
        );
        
        // Remove margin
        uint256 removeAmount = 200e6;
        vm.prank(user1);
        positionManager.removeMargin(tokenId, removeAmount);
        
        // Verify margin decreased
        PositionLib.Position memory position = positionManager.getPosition(tokenId);
        assertEq(position.margin, TEST_MARGIN - removeAmount);
    }
    
    function test_RevertWhen_OpenPositionInsufficientMargin() public {
        // Try to open with more margin than available
        uint256 excessiveMargin = 10000e6; // More than deposited
        
        vm.prank(user1);
        vm.expectRevert();
        positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_SIZE,
            TEST_PRICE,
            excessiveMargin
        );
    }
    
    function test_RevertWhen_UpdatePositionNotOwner() public {
        // Open position as user1
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            ETH_USDC_MARKET,
            TEST_SIZE,
            TEST_PRICE,
            TEST_MARGIN
        );
        
        // Try to update as user2 (should fail)
        vm.prank(user2);
        vm.expectRevert();
        positionManager.updatePosition(tokenId, TEST_SIZE / 2, TEST_MARGIN / 2);
    }
}

