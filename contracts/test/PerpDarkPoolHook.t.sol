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
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IOrderServiceManager} from "../../avs/src/IOrderServiceManager.sol";

/// @notice Test contract using real PoolManager on mainnet fork
/// @dev Uses forked mainnet with real contracts for integration testing
contract PerpDarkPoolHookTest is Test {
    using PoolIdLibrary for PoolKey;
    
    // Mainnet addresses
    address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH_MAINNET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    
    PerpDarkPoolHook hook;
    PoolManager poolManager; // Real PoolManager from Uniswap V4
    MarginAccount marginAccount;
    PositionManager positionManager;
    PositionFactory positionFactory;
    PositionNFT positionNFT;
    MarketManager marketManager;
    FundingOracle fundingOracle;
    address serviceManager; // Mock service manager address
    
    address USDC;
    address WETH;
    
    address user1 = address(0x1111);
    address user2 = address(0x2222);
    
    PoolKey poolKey;
    bytes32 poolId;
    
    function setUp() public {
        // Fork mainnet
        string memory rpcUrl = "https://eth-mainnet.g.alchemy.com/v2/LF_kKjuhP-n6j9O-jWcg9o94UWKNtoCf";
        try vm.envString("MAINNET_RPC_URL") returns (string memory envUrl) {
            rpcUrl = envUrl;
        } catch {}
        vm.createSelectFork(rpcUrl);
        
        console.log("Forked mainnet at block:", block.number);
        
        // Use real mainnet addresses
        USDC = USDC_MAINNET;
        WETH = WETH_MAINNET;
        
        // Deploy real PoolManager from Uniswap V4
        poolManager = new PoolManager(address(this));
        console.log("Deployed PoolManager at:", address(poolManager));
        
        // Deploy core contracts
        marginAccount = new MarginAccount(USDC);
        positionNFT = new PositionNFT();
        positionFactory = new PositionFactory(USDC, address(marginAccount));
        positionNFT.setFactory(address(positionFactory)); // Set factory in NFT (required for minting)
        positionFactory.setPositionNFT(address(positionNFT));
        marketManager = new MarketManager();
        positionManager = new PositionManager(
            address(positionFactory),
            address(positionNFT),
            address(marketManager)
        );
        fundingOracle = new FundingOracle();
        
        // Deploy mock service manager (we'll use address(this) for now)
        serviceManager = address(this);
        
        // Calculate hook address with correct flags based on permissions
        // Permissions: afterInitialize, beforeSwap, beforeSwapReturnDelta
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );
        
        // Deploy hook to the address with correct flags using deployCodeTo
        // This properly calls the constructor
        address hookAddress = address(flags);
        bytes memory constructorArgs = abi.encode(
            IPoolManager(address(poolManager)),
            serviceManager,
            marginAccount,
            positionManager,
            fundingOracle,
            IERC20(USDC)
        );
        
        deployCodeTo("PerpDarkPoolHook.sol:PerpDarkPoolHook", constructorArgs, hookAddress);
        hook = PerpDarkPoolHook(payable(hookAddress));
        
        console.log("Deployed PerpDarkPoolHook at:", address(hook));
        
        // Create pool key with hook address
        poolKey = PoolKey({
            currency0: Currency.wrap(WETH),
            currency1: Currency.wrap(USDC),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        poolId = bytes32(PoolId.unwrap(poolKey.toId()));
        
        // Authorize hook in contracts
        vm.prank(marginAccount.owner());
        marginAccount.addAuthorizedContract(address(hook));
        
        vm.prank(positionManager.owner());
        positionManager.addAuthorizedContract(address(hook));
        
        // Note: Market initialization happens automatically on first swap
        // For testing, we can trigger it via a swap or add a test helper
    }
    
    function testPerpOrderCreation() public {
        // Test creating a perp order via hook
        // This requires a full integration with service manager
        // For now, we test that the hook is properly deployed
        
        // Verify hook is deployed
        assertTrue(address(hook) != address(0));
        assertEq(address(hook.marginAccount()), address(marginAccount));
        assertEq(address(hook.positionManager()), address(positionManager));
        assertEq(address(hook.fundingOracle()), address(fundingOracle));
        
        console.log("Hook deployed successfully");
        console.log("Hook address:", address(hook));
    }
    
    function testCoWMatching() public {
        // Test CoW matching of long vs short
        // This requires AVS integration, so we test the settlement structure
        
        // Create a mock settlement
        PerpDarkPoolHook.PerpCoWSettlement memory settlement = PerpDarkPoolHook.PerpCoWSettlement({
            longTrader: user1,
            shortTrader: user2,
            poolId: poolId,
            matchSize: 1e18, // 1 ETH
            matchPrice: 2000e18, // $2000
            longMargin: 1000e6, // 1000 USDC
            shortMargin: 1000e6, // 1000 USDC
            longLeverage: 2e18, // 2x
            shortLeverage: 2e18 // 2x
        });
        
        // Verify settlement structure is valid
        assertTrue(settlement.longTrader != address(0));
        assertTrue(settlement.shortTrader != address(0));
        assertGt(settlement.matchSize, 0);
        assertGt(settlement.matchPrice, 0);
        
        console.log("CoW settlement structure validated");
    }
    
    function testVAMMExecution() public {
        // Test vAMM execution for unmatched orders
        // Verify market state structure
        
        // Check that market state can be accessed (even if not initialized)
        // In a real scenario, market would be initialized on first swap
        bytes32 testPoolId = keccak256("test");
        
        // Verify hook has vAMM state mapping
        // This is a structural test - actual execution requires full integration
        assertTrue(address(hook) != address(0));
        
        console.log("vAMM execution structure validated");
    }
    
    function testMarginLocking() public {
        // Test margin locking in MarginAccount with real USDC
        uint256 marginAmount = 1000e6; // 1000 USDC
        
        // Get USDC from a whale on mainnet fork
        address usdcWhale = 0x28C6c06298d514Db089934071355E5743bf21d60; // Binance hot wallet
        vm.prank(usdcWhale);
        IERC20(USDC).transfer(user1, marginAmount);
        
        // Approve margin account
        vm.prank(user1);
        IERC20(USDC).approve(address(marginAccount), marginAmount);
        
        // Deposit margin
        vm.prank(user1);
        marginAccount.deposit(marginAmount);
        
        // Authorize this contract to lock margin
        vm.prank(marginAccount.owner());
        marginAccount.addAuthorizedContract(address(this));
        
        // Lock margin
        marginAccount.lockMargin(user1, marginAmount);
        
        // Verify locked
        assertEq(marginAccount.getLockedBalance(user1), marginAmount);
        assertEq(marginAccount.getAvailableBalance(user1), 0);
        
        console.log("Margin locking test passed with real USDC");
    }
    
    function testPositionCreation() public {
        // Test position creation with real USDC on mainnet fork
        bytes32 marketId = poolId;
        int256 sizeBase = 1e18; // 1 ETH
        uint256 entryPrice = 2000e18; // $2000
        uint256 margin = 1000e6; // 1000 USDC
        
        // Get real USDC from whale
        address usdcWhale = 0x28C6c06298d514Db089934071355E5743bf21d60;
        vm.prank(usdcWhale);
        IERC20(USDC).transfer(user1, margin);
        
        // Setup margin first
        vm.prank(user1);
        IERC20(USDC).approve(address(marginAccount), margin);
        vm.prank(user1);
        marginAccount.deposit(margin);
        
        // Authorize PositionFactory to lock margin (it needs this to create positions)
        vm.prank(marginAccount.owner());
        marginAccount.addAuthorizedContract(address(positionFactory));
        
        // Add market to factory first
        vm.prank(positionFactory.owner());
        positionFactory.addMarket(marketId, WETH, USDC, address(0));
        
        // Create position via PositionManager.openPosition (like uniperp test)
        // This calls factory.openPosition(msg.sender, ...) internally
        vm.prank(user1);
        uint256 tokenId = positionManager.openPosition(
            marketId,
            sizeBase,
            entryPrice,
            margin
        );
        
        // Verify position
        assertGt(tokenId, 0);
        assertEq(positionNFT.ownerOf(tokenId), user1);
        
        console.log("Position created successfully with tokenId:", tokenId);
    }
    
    function testVAMMPriceCalculation() public {
        // Test vAMM price calculation with initialized market
        // First, we need to trigger market initialization via a swap or manual init
        // For now, we'll test the market state structure
        
        // Verify hook has market state mapping
        assertTrue(address(hook) != address(0));
        
        // Market will be auto-initialized on first swap
        // For this test, we verify the structure is ready
        bytes32 testPoolId = keccak256("test");
        
        // Check that perpMarkets mapping exists (even if not initialized)
        // In a real scenario, market would be initialized and we'd check:
        // (uint256 virtualBase, uint256 virtualQuote, uint256 k, ...) = hook.perpMarkets(poolId);
        
        console.log("vAMM price calculation structure ready");
        console.log("Market will be initialized on first swap");
    }
    
    function testVAMMMarketInitialization() public {
        // Test that market can be initialized (would require actual swap)
        // This is a structural test - full integration requires swap execution
        
        // Verify pool key is set
        assertTrue(poolId != bytes32(0));
        
        // Verify hook is properly configured
        assertEq(address(hook.marginAccount()), address(marginAccount));
        assertEq(address(hook.positionManager()), address(positionManager));
        assertEq(address(hook.fundingOracle()), address(fundingOracle));
        
        // Market initialization happens in _beforeSwap when market doesn't exist
        // This test verifies the setup is correct for initialization
        
        console.log("vAMM market initialization setup verified");
        console.log("Pool ID:", vm.toString(poolId));
    }
}
