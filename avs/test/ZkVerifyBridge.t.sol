// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {ZkVerifyBridge} from "../src/ZkVerifyBridge.sol";

/// @notice Test contract for ZkVerifyBridge
contract ZkVerifyBridgeTest is Test {
    ZkVerifyBridge bridge;
    
    address owner;
    address relayer1;
    address relayer2;
    address unauthorized;
    
    function setUp() public {
        owner = address(this);
        relayer1 = address(0xAAAA);
        relayer2 = address(0xBBBB);
        unauthorized = address(0xCCCC);
        
        bridge = new ZkVerifyBridge();
        
        // Owner is automatically a relayer
        assertTrue(bridge.authorizedRelayers(owner));
    }
    
    /// @notice Test adding a relayer
    function testAddRelayer() public {
        bridge.addRelayer(relayer1);
        assertTrue(bridge.authorizedRelayers(relayer1));
        
        console.log("[OK] Relayer added successfully");
    }
    
    /// @notice Test removing a relayer
    function testRemoveRelayer() public {
        bridge.addRelayer(relayer1);
        assertTrue(bridge.authorizedRelayers(relayer1));
        
        bridge.removeRelayer(relayer1);
        assertFalse(bridge.authorizedRelayers(relayer1));
        
        console.log("[OK] Relayer removed successfully");
    }
    
    /// @notice Test unauthorized relayer cannot publish Merkle root
    function test_RevertWhen_UnauthorizedRelayerPublishesMerkleRoot() public {
        vm.prank(unauthorized);
        vm.expectRevert(ZkVerifyBridge.UnauthorizedRelayer.selector);
        bridge.publishMerkleRoot("0xabc123", 1000);
    }
    
    /// @notice Test publishing Merkle root
    function testPublishMerkleRoot() public {
        string memory merkleRoot = "0xabc123def456";
        uint256 zkVerifyBlock = 1000;
        
        bridge.publishMerkleRoot(merkleRoot, zkVerifyBlock);
        
        assertTrue(bridge.validMerkleRoots(merkleRoot));
        
        console.log("[OK] Merkle root published successfully");
    }
    
    /// @notice Test storing proof receipt
    function testStoreProofReceipt() public {
        string memory proofId = "proof_123";
        string memory merkleRoot = "0xabc123def456";
        uint256 zkVerifyBlock = 1000;
        
        // First publish Merkle root
        bridge.publishMerkleRoot(merkleRoot, zkVerifyBlock);
        
        // Then store proof receipt
        bridge.storeProofReceipt(proofId, merkleRoot, zkVerifyBlock);
        
        // Verify receipt
        ZkVerifyBridge.ZkVerifyReceipt memory receipt = bridge.getProofReceipt(proofId);
        assertTrue(receipt.verified);
        assertEq(receipt.proofId, proofId);
        assertEq(receipt.merkleRoot, merkleRoot);
        assertEq(receipt.blockNumber, zkVerifyBlock);
        
        console.log("[OK] Proof receipt stored successfully");
    }
    
    /// @notice Test storing proof receipt with invalid Merkle root
    function test_RevertWhen_StoreProofReceiptWithInvalidMerkleRoot() public {
        string memory proofId = "proof_123";
        string memory invalidMerkleRoot = "0xinvalid";
        uint256 zkVerifyBlock = 1000;
        
        vm.expectRevert(ZkVerifyBridge.InvalidMerkleRoot.selector);
        bridge.storeProofReceipt(proofId, invalidMerkleRoot, zkVerifyBlock);
    }
    
    /// @notice Test storing duplicate proof receipt
    function test_RevertWhen_StoreDuplicateProofReceipt() public {
        string memory proofId = "proof_123";
        string memory merkleRoot = "0xabc123def456";
        uint256 zkVerifyBlock = 1000;
        
        bridge.publishMerkleRoot(merkleRoot, zkVerifyBlock);
        bridge.storeProofReceipt(proofId, merkleRoot, zkVerifyBlock);
        
        // Try to store again
        vm.expectRevert(ZkVerifyBridge.ProofAlreadyExists.selector);
        bridge.storeProofReceipt(proofId, merkleRoot, zkVerifyBlock);
    }
    
    /// @notice Test verifying proof receipt
    function testVerifyProofReceipt() public {
        string memory proofId = "proof_123";
        string memory merkleRoot = "0xabc123def456";
        uint256 zkVerifyBlock = 1000;
        
        bridge.publishMerkleRoot(merkleRoot, zkVerifyBlock);
        bridge.storeProofReceipt(proofId, merkleRoot, zkVerifyBlock);
        
        bool isValid = bridge.verifyProofReceipt(proofId);
        assertTrue(isValid);
        
        console.log("[OK] Proof receipt verified successfully");
    }
    
    /// @notice Test verifying non-existent proof receipt
    function testVerifyNonExistentProofReceipt() public {
        string memory proofId = "non_existent";
        
        bool isValid = bridge.verifyProofReceipt(proofId);
        assertFalse(isValid);
        
        console.log("[OK] Non-existent proof receipt correctly returns false");
    }
    
    /// @notice Test batch verification
    function testBatchVerifyProofReceipts() public {
        string[] memory proofIds = new string[](3);
        proofIds[0] = "proof_1";
        proofIds[1] = "proof_2";
        proofIds[2] = "proof_3";
        
        string memory merkleRoot = "0xmerkle123";
        uint256 zkVerifyBlock = 1000;
        
        bridge.publishMerkleRoot(merkleRoot, zkVerifyBlock);
        
        // Store all proof receipts
        for (uint i = 0; i < proofIds.length; i++) {
            bridge.storeProofReceipt(proofIds[i], merkleRoot, zkVerifyBlock);
        }
        
        // Batch verify
        bool[] memory results = bridge.batchVerifyProofReceipts(proofIds);
        
        assertEq(results.length, 3);
        assertTrue(results[0]);
        assertTrue(results[1]);
        assertTrue(results[2]);
        
        console.log("[OK] Batch verification successful");
    }
    
    /// @notice Test verifying Merkle root
    function testVerifyMerkleRoot() public {
        string memory merkleRoot = "0xabc123def456";
        uint256 zkVerifyBlock = 1000;
        
        bridge.publishMerkleRoot(merkleRoot, zkVerifyBlock);
        
        bool isValid = bridge.verifyMerkleRoot(merkleRoot, zkVerifyBlock);
        assertTrue(isValid);
        
        console.log("[OK] Merkle root verification successful");
    }
    
    /// @notice Test verifying invalid Merkle root
    function testVerifyInvalidMerkleRoot() public {
        string memory invalidMerkleRoot = "0xinvalid";
        uint256 zkVerifyBlock = 1000;
        
        bool isValid = bridge.verifyMerkleRoot(invalidMerkleRoot, zkVerifyBlock);
        assertFalse(isValid);
        
        console.log("[OK] Invalid Merkle root correctly returns false");
    }
    
    /// @notice Test pause/unpause functionality
    function testPauseUnpause() public {
        bridge.pause();
        assertTrue(bridge.paused());
        
        bridge.unpause();
        assertFalse(bridge.paused());
        
        console.log("[OK] Pause/unpause functionality works");
    }
    
    /// @notice Test cannot publish Merkle root when paused
    function test_RevertWhen_PublishMerkleRootWhenPaused() public {
        bridge.pause();
        
        vm.expectRevert("Pausable: paused");
        bridge.publishMerkleRoot("0xabc123", 1000);
    }
    
    /// @notice Test cleanup old receipts
    function testCleanupOldReceipts() public {
        string memory proofId = "old_proof";
        string memory merkleRoot = "0xabc123";
        uint256 zkVerifyBlock = 1000;
        
        bridge.publishMerkleRoot(merkleRoot, zkVerifyBlock);
        bridge.storeProofReceipt(proofId, merkleRoot, zkVerifyBlock);
        
        // Fast forward 31 days
        vm.warp(block.timestamp + 31 days);
        
        string[] memory proofIds = new string[](1);
        proofIds[0] = proofId;
        
        bridge.cleanupOldReceipts(proofIds);
        
        // Receipt should be deleted
        ZkVerifyBridge.ZkVerifyReceipt memory receipt = bridge.getProofReceipt(proofId);
        assertFalse(receipt.verified);
        
        console.log("[OK] Old receipts cleaned up successfully");
    }
    
    /// @notice Test get contract info
    function testGetContractInfo() public {
        (string memory zkRPC, uint256 chainId, uint256 relayerCount) = bridge.getContractInfo();
        
        assertGt(bytes(zkRPC).length, 0);
        assertGt(chainId, 0);
        
        console.log("[OK] Contract info retrieved successfully");
        console.log("zkVerify RPC:", zkRPC);
        console.log("Chain ID:", chainId);
    }
}

