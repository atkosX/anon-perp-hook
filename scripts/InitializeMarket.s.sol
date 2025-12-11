// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {PerpDarkPoolHook} from "../contracts/src/PerpDarkPoolHook.sol";
import {FundingOracle} from "../contracts/src/FundingOracle.sol";
import {PositionManager} from "../contracts/src/PositionManager.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract InitializeMarket is Script {
    address constant HOOK = address(0); // Set after hook deployment
    address constant FUNDING_ORACLE = address(0); // Set after core deployment
    address constant POSITION_MANAGER = address(0); // Set after core deployment
    
    // Market parameters
    address constant BASE_ASSET = address(0); // ETH address (or WETH)
    address constant QUOTE_ASSET = address(0); // USDC address
    address constant CHAINLINK_PRICE_FEED = address(0); // Chainlink price feed aggregator for ETH/USD
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Initializing perp market...");
        
        // Create pool key
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(BASE_ASSET),
            currency1: Currency.wrap(QUOTE_ASSET),
            fee: 3000, // 0.3%
            tickSpacing: 60,
            hooks: HOOK
        });
        
        bytes32 poolId = bytes32(PoolId.unwrap(key.toId()));
        
        // 1. Add market to FundingOracle
        console.log("Adding market to FundingOracle...");
        FundingOracle fundingOracle = FundingOracle(FUNDING_ORACLE);
        fundingOracle.addMarket(PoolId.wrap(poolId), HOOK, CHAINLINK_PRICE_FEED);
        console.log("Market added to FundingOracle");
        
        // 2. Add market to PositionManager
        console.log("Adding market to PositionManager...");
        PositionManager positionManager = PositionManager(POSITION_MANAGER);
        positionManager.addMarket(
            poolId,
            BASE_ASSET,
            QUOTE_ASSET,
            address(0) // Pool address (set after pool initialization)
        );
        console.log("Market added to PositionManager");
        
        // 3. Initialize vAMM in hook (this happens automatically in afterInitialize)
        // But we can also call it manually if needed
        console.log("Market initialization complete!");
        console.log("PoolId:", vm.toString(poolId));
        
        vm.stopBroadcast();
    }
}

