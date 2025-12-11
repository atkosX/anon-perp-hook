// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MarginAccount} from "../contracts/src/MarginAccount.sol";
import {PositionNFT} from "../contracts/src/PositionNFT.sol";
import {PositionFactory} from "../contracts/src/PositionFactory.sol";
import {MarketManager} from "../contracts/src/MarketManager.sol";
import {PositionManager} from "../contracts/src/PositionManager.sol";
import {FundingOracle} from "../contracts/src/FundingOracle.sol";

contract DeployCore is Script {
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // Mainnet USDC
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Deploying core perp contracts...");
        
        // 1. Deploy MarginAccount
        console.log("Deploying MarginAccount...");
        MarginAccount marginAccount = new MarginAccount(USDC);
        console.log("MarginAccount deployed at:", address(marginAccount));
        
        // 2. Deploy PositionNFT
        console.log("Deploying PositionNFT...");
        PositionNFT positionNFT = new PositionNFT();
        console.log("PositionNFT deployed at:", address(positionNFT));
        
        // 3. Deploy PositionFactory
        console.log("Deploying PositionFactory...");
        PositionFactory positionFactory = new PositionFactory(USDC, address(marginAccount));
        console.log("PositionFactory deployed at:", address(positionFactory));
        
        // Set PositionNFT in factory
        positionFactory.setPositionNFT(address(positionNFT));
        console.log("PositionNFT set in factory");
        
        // 4. Deploy MarketManager
        console.log("Deploying MarketManager...");
        MarketManager marketManager = new MarketManager();
        console.log("MarketManager deployed at:", address(marketManager));
        
        // 5. Deploy PositionManager
        console.log("Deploying PositionManager...");
        PositionManager positionManager = new PositionManager(
            address(positionFactory),
            address(positionNFT),
            address(marketManager)
        );
        console.log("PositionManager deployed at:", address(positionManager));
        
        // 6. Deploy FundingOracle (no constructor params needed - uses Chainlink aggregators)
        console.log("Deploying FundingOracle...");
        FundingOracle fundingOracle = new FundingOracle();
        console.log("FundingOracle deployed at:", address(fundingOracle));
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Summary ===");
        console.log("MarginAccount:", address(marginAccount));
        console.log("PositionNFT:", address(positionNFT));
        console.log("PositionFactory:", address(positionFactory));
        console.log("MarketManager:", address(marketManager));
        console.log("PositionManager:", address(positionManager));
        console.log("FundingOracle:", address(fundingOracle));
    }
}

