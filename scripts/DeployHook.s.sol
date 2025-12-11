// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {PerpDarkPoolHook} from "../contracts/src/PerpDarkPoolHook.sol";
import {OrderServiceManager} from "../avs/src/OrderServiceManager.sol";
import {ZkVerifyBridge} from "../avs/src/ZkVerifyBridge.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

contract DeployHook is Script {
    // These should be set after DeployCore.s.sol
    address constant MARGIN_ACCOUNT = address(0); // Set after core deployment
    address constant POSITION_MANAGER = address(0); // Set after core deployment
    address constant FUNDING_ORACLE = address(0); // Set after core deployment
    address constant POOL_MANAGER = address(0); // Uniswap V4 PoolManager
    address constant AVS_DIRECTORY = address(0); // EigenLayer AVS Directory
    address constant STAKE_REGISTRY = address(0); // EigenLayer Stake Registry
    address constant REWARDS_COORDINATOR = address(0); // EigenLayer Rewards Coordinator
    address constant DELEGATION_MANAGER = address(0); // EigenLayer Delegation Manager
    address constant ALLOCATION_MANAGER = address(0); // EigenLayer Allocation Manager
    address constant VERIFIER = address(0); // SP1 Verifier
    bytes32 constant ORDER_PROGRAM_VKEY = bytes32(0); // SP1 program verification key
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Deploying dark pool contracts...");
        
        // 1. Deploy ZkVerifyBridge
        console.log("Deploying ZkVerifyBridge...");
        ZkVerifyBridge zkVerifyBridge = new ZkVerifyBridge();
        console.log("ZkVerifyBridge deployed at:", address(zkVerifyBridge));
        
        // 2. Deploy OrderServiceManager
        console.log("Deploying OrderServiceManager...");
        OrderServiceManager orderServiceManager = new OrderServiceManager(
            AVS_DIRECTORY,
            STAKE_REGISTRY,
            REWARDS_COORDINATOR,
            DELEGATION_MANAGER,
            ALLOCATION_MANAGER,
            VERIFIER,
            ORDER_PROGRAM_VKEY,
            address(zkVerifyBridge)
        );
        console.log("OrderServiceManager deployed at:", address(orderServiceManager));
        
        // 3. Deploy PerpDarkPoolHook
        console.log("Deploying PerpDarkPoolHook...");
        PerpDarkPoolHook hook = new PerpDarkPoolHook(
            IPoolManager(POOL_MANAGER),
            MARGIN_ACCOUNT,
            POSITION_MANAGER,
            FUNDING_ORACLE,
            address(orderServiceManager)
        );
        console.log("PerpDarkPoolHook deployed at:", address(hook));
        
        // 4. Set hook in OrderServiceManager
        console.log("Setting hook in OrderServiceManager...");
        orderServiceManager.setHook(address(hook));
        console.log("Hook set in OrderServiceManager");
        
        // 5. Authorize hook in MarginAccount (if needed)
        // This would be done via MarginAccount.addKeyManager(address(hook))
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Summary ===");
        console.log("ZkVerifyBridge:", address(zkVerifyBridge));
        console.log("OrderServiceManager:", address(orderServiceManager));
        console.log("PerpDarkPoolHook:", address(hook));
    }
}

