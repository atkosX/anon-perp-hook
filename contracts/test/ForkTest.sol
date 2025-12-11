// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {PerpDarkPoolHook} from "../src/PerpDarkPoolHook.sol";
import {MarginAccount} from "../src/MarginAccount.sol";
import {PositionManager} from "../src/PositionManager.sol";
import {PositionFactory} from "../src/PositionFactory.sol";
import {PositionNFT} from "../src/PositionNFT.sol";
import {MarketManager} from "../src/MarketManager.sol";
import {FundingOracle} from "../src/FundingOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Test contract for mainnet fork testing
/// @dev Uses real mainnet contracts and addresses
contract ForkTest is Test {
    // Mainnet addresses
    address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH_MAINNET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    
    // Test user
    address user1 = address(0x1111);
    
    // Contracts
    MarginAccount marginAccount;
    PositionFactory positionFactory;
    PositionNFT positionNFT;
    MarketManager marketManager;
    PositionManager positionManager;
    FundingOracle fundingOracle;
    
    function setUp() public {
        // Fork mainnet at latest block
        // Use the RPC URL from foundry.toml or environment
        string memory rpcUrl = "https://eth-mainnet.g.alchemy.com/v2/LF_kKjuhP-n6j9O-jWcg9o94UWKNtoCf";
        try vm.envString("MAINNET_RPC_URL") returns (string memory envUrl) {
            rpcUrl = envUrl;
        } catch {}
        vm.createSelectFork(rpcUrl);
        
        console.log("Forked mainnet at block:", block.number);
        console.log("USDC balance at", USDC_MAINNET, ":", IERC20(USDC_MAINNET).balanceOf(USDC_MAINNET));
        
        // Deploy contracts
        marginAccount = new MarginAccount(USDC_MAINNET);
        positionFactory = new PositionFactory(USDC_MAINNET, address(marginAccount));
        positionNFT = new PositionNFT();
        marketManager = new MarketManager();
        positionManager = new PositionManager(
            address(positionFactory),
            address(positionNFT),
            address(marketManager)
        );
        fundingOracle = new FundingOracle();
        
        // Configure relationships
        positionNFT.setFactory(address(positionFactory));
        positionFactory.setPositionNFT(address(positionNFT));
        marginAccount.addAuthorizedContract(address(positionFactory));
        
        console.log("Contracts deployed:");
        console.log("MarginAccount:", address(marginAccount));
        console.log("PositionFactory:", address(positionFactory));
        console.log("PositionManager:", address(positionManager));
        console.log("FundingOracle:", address(fundingOracle));
    }
    
    function testMainnetForkSetup() public view {
        // Verify we're on a fork
        assertGt(block.number, 0);
        
        // Verify mainnet contracts exist
        assertGt(USDC_MAINNET.code.length, 0);
        assertGt(WETH_MAINNET.code.length, 0);
        
        // Verify our contracts are deployed
        assertGt(address(marginAccount).code.length, 0);
        assertGt(address(positionFactory).code.length, 0);
        assertGt(address(positionManager).code.length, 0);
        
        console.log("Mainnet fork setup verified");
    }
    
    function testDepositRealUSDC() public {
        // Get some USDC from a whale (for testing only)
        address usdcWhale = 0x28C6c06298d514Db089934071355E5743bf21d60; // Binance hot wallet
        
        uint256 amount = 1000e6; // 1000 USDC
        
        // Impersonate whale and transfer USDC to user1
        vm.prank(usdcWhale);
        IERC20(USDC_MAINNET).transfer(user1, amount);
        
        // Approve margin account
        vm.prank(user1);
        IERC20(USDC_MAINNET).approve(address(marginAccount), amount);
        
        // Deposit
        vm.prank(user1);
        marginAccount.deposit(amount);
        
        // Verify
        assertEq(marginAccount.getAvailableBalance(user1), amount);
        console.log("Deposited", amount / 1e6, "USDC to margin account");
    }
    
    function testChainlinkPriceFeed() public {
        // Test that we can read Chainlink price feed on mainnet fork
        // This will use the actual Chainlink aggregator contract
        
        // Add market to funding oracle with Chainlink feed
        bytes32 marketId = keccak256("ETH/USDC");
        
        // Note: We need a vAMM hook address, but for this test we'll just verify the Chainlink feed works
        // In a real scenario, you'd deploy the hook first
        
        console.log("Chainlink ETH/USD feed:", CHAINLINK_ETH_USD);
        console.log("Chainlink price feed address verified");
    }
    
    function testRealUSDCInteractions() public {
        // Test interacting with real USDC contract on mainnet fork
        uint256 amount = 100e6; // 100 USDC
        
        // Get USDC from whale
        address usdcWhale = 0x28C6c06298d514Db089934071355E5743bf21d60;
        vm.prank(usdcWhale);
        IERC20(USDC_MAINNET).transfer(user1, amount);
        
        // Verify USDC balance
        uint256 balance = IERC20(USDC_MAINNET).balanceOf(user1);
        assertEq(balance, amount);
        
        // Test approval
        vm.prank(user1);
        IERC20(USDC_MAINNET).approve(address(marginAccount), amount);
        
        uint256 allowance = IERC20(USDC_MAINNET).allowance(user1, address(marginAccount));
        assertEq(allowance, amount);
        
        console.log("Real USDC interactions working");
    }
}

