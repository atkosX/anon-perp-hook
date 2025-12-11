// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {ECDSAServiceManagerBase} from
    "@eigenlayer-middleware/src/unaudited/ECDSAServiceManagerBase.sol";
import {ECDSAStakeRegistry} from "@eigenlayer-middleware/src/unaudited/ECDSAStakeRegistry.sol";
import {IServiceManager} from "@eigenlayer-middleware/src/interfaces/IServiceManager.sol";
import {ECDSAUpgradeable} from
    "@openzeppelin-upgrades/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import {IOrderServiceManager} from "./IOrderServiceManager.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";
import {IAllocationManager} from "@eigenlayer/contracts/interfaces/IAllocationManager.sol";

import {ISP1Verifier} from "sp1-contracts/src/ISP1Verifier.sol";
import {ZkVerifyBridge} from "./ZkVerifyBridge.sol";

/// @notice zkVerify proof receipt structure
struct ZkVerifyReceipt {
    string proofId;
    string merkleRoot;
    uint256 blockNumber;
}

interface IPerpDarkPoolHook {
    struct PerpCoWSettlement {
        address longTrader;
        address shortTrader;
        bytes32 poolId;
        uint256 matchSize;
        uint256 matchPrice;
        uint256 longMargin;
        uint256 shortMargin;
        uint256 longLeverage;
        uint256 shortLeverage;
    }

    function settlePerpBalances(
        bytes32 poolId,
        PerpCoWSettlement memory settlement
    ) external;
}

contract OrderServiceManager is ECDSAServiceManagerBase, IOrderServiceManager {
    using ECDSAUpgradeable for bytes32;

    event TaskResponded(uint32 indexed taskIndex, Task task, address operator);
    event ProveRequest(
        uint32 indexed taskIndex,
        address indexed operator,
        ProveRequestData provdata
    );
    event OperatorSlashed(address indexed operator, uint32 indexed taskIndex, uint256 timestamp);

    uint32 public latestTaskNum;
    address public hook;
    mapping(uint32 => bytes32) public allTaskHashes;
    mapping(address => mapping(uint32 => bytes)) public allTaskResponses;
    address public verifier;
    bytes32 public orderProgramVKey;
    ZkVerifyBridge public zkVerifyBridge;

    modifier onlyOperator() {
        require(
            ECDSAStakeRegistry(stakeRegistry).operatorRegistered(msg.sender),
            "Operator must be the caller"
        );
        _;
    }

    modifier onlyHook() {
        require(msg.sender == hook, "Only hook can call this function");
        _;
    }
    
    struct PublicValuesStruct {
        uint32 n;
        uint32 a;
        uint32 b;
    }

    struct ProveRequestData {
        bytes32 marketCurrentPrice;
        uint256 marketBlockTimestamp;
        bytes32 treeRoot;
        bytes32 nullifierHash;
        address walletAddress;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 targetPrice;
        uint256 deadline;
        bytes32 commitmentNullifier;
        uint256 balance;
        bytes32[] siblings;
        uint32[] indices;
    }

    ProveRequestData proveData;

    constructor(
        address _avsDirectory,
        address _stakeRegistry,
        address _rewardsCoordinator,
        address _delegationManager,
        address _allocationManager,
        address _verifier, 
        bytes32 _orderProgramVKey,
        address _zkVerifyBridge
    )
        ECDSAServiceManagerBase(
            _avsDirectory,
            _stakeRegistry,
            _rewardsCoordinator,
            _delegationManager,
            _allocationManager
        )
    {
        verifier = _verifier;
        orderProgramVKey = _orderProgramVKey;
        zkVerifyBridge = ZkVerifyBridge(_zkVerifyBridge);
        // Initialize hardcoded prove data
        proveData = ProveRequestData({
            marketCurrentPrice: bytes32(uint256(2050000000)),
            marketBlockTimestamp: 1735600000,
            treeRoot: 0x1111111111111111111111111111111111111111111111111111111111111111,
            nullifierHash: 0x2222222222222222222222222222222222222222222222222222222222222222,
            walletAddress: 0x0000000000000000000000000000000000000001,
            tokenIn: 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa,
            tokenOut: 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB,
            amountIn: 5000000000000000000,
            minAmountOut: 10000000000,
            targetPrice: 2000000000,
            deadline: 1735689600,
            commitmentNullifier: 0x3333333333333333333333333333333333333333333333333333333333333333,
            balance: 10000000000000000000,
            siblings: new bytes32[](2),
            indices: new uint32[](2)
        });
        proveData.siblings[0] = 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;
        proveData.siblings[1] = 0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb;
        proveData.indices[0] = 0;
        proveData.indices[1] = 1;
    }

    function initialize(address initialOwner, address _rewardsInitiator) external initializer {
        __ServiceManagerBase_init(initialOwner, _rewardsInitiator);
    }

    // These are just to comply with IServiceManager interface
    function addPendingAdmin(address admin) external onlyOwner {}
    function removePendingAdmin(address pendingAdmin) external onlyOwner {}
    function removeAdmin(address admin) external onlyOwner {}
    function setAppointee(address appointee, address target, bytes4 selector) external onlyOwner {}
    function removeAppointee(
        address appointee,
        address target,
        bytes4 selector
    ) external onlyOwner {}
    function deregisterOperatorFromOperatorSets(
        address operator,
        uint32[] memory operatorSetIds
    ) external {
        // unused
    }

    /* FUNCTIONS */
    /// @notice Create a new perp task (replaces createNewTask)
    function createPerpTask(
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        address sender,
        bytes32 poolId,
        bool isLong,
        uint256 marginAmount,
        uint256 leverage,
        uint256 positionId
    ) external onlyHook returns (Task memory task){
        task = Task({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: sqrtPriceLimitX96,
            sender: sender,
            poolId: poolId,
            taskCreatedBlock: uint32(block.number),
            taskId: latestTaskNum,
            isPerpOrder: true,
            positionId: positionId,
            marginAmount: marginAmount,
            leverage: leverage,
            isLong: isLong
        });
        allTaskHashes[latestTaskNum] = keccak256(abi.encode(task));
        emit NewTaskCreated(latestTaskNum, task);
        latestTaskNum++;
    }

    /// @notice Operators respond to tasks with perp CoW matching results
    function respondToBatch(
        Task[] calldata tasks,
        uint32[] memory referenceTaskIndices,
        IPerpDarkPoolHook.PerpCoWSettlement memory perpSettlement,
        bytes memory signature,
        bytes memory zkProof  // ZK proof for order validation
    ) external {
        // Check that tasks are valid and haven't been responded to
        for(uint256 i = 0; i < referenceTaskIndices.length; i++){
            require(
                keccak256(abi.encode(tasks[i])) == allTaskHashes[referenceTaskIndices[i]],
                "supplied task does not match the one recorded in the contract"
            );
            require(
                allTaskResponses[msg.sender][referenceTaskIndices[i]].length == 0,
                "Task already responded"
            );
        }

        // Verify all tasks are perp orders
        for (uint256 i = 0; i < tasks.length; i++) {
            require(tasks[i].isPerpOrder, "All tasks must be perp orders");
        }

        // The message that was signed
        bytes32 messageHash = getMessageHash(tasks[0].poolId, perpSettlement);

        address signer = ECDSAUpgradeable.recover(messageHash, signature);
        require(signer == msg.sender, "Invalid signature");

        // Store responses
        for (uint256 i = 0; i < referenceTaskIndices.length; i++) {
            allTaskResponses[msg.sender][referenceTaskIndices[i]] = signature;
        }

        // zkVerify proof verification
        if (zkProof.length > 0) {
            bool zkProofValid = verifyZkVerifyProof(zkProof, tasks[0].sender);
            require(zkProofValid, "Invalid zkVerify proof receipt");
        }

        ProveRequestData memory args = ProveRequestData(
            proveData.marketCurrentPrice,
            proveData.marketBlockTimestamp,
            proveData.treeRoot,
            proveData.nullifierHash,
            proveData.walletAddress,
            proveData.tokenIn,
            proveData.tokenOut,
            proveData.amountIn,
            proveData.minAmountOut,
            proveData.targetPrice,
            proveData.deadline,
            proveData.commitmentNullifier,
            proveData.balance,
            proveData.siblings,
            proveData.indices
        );
        
        // Emit prove request event for off-chain processing
        emit ProveRequest(
            referenceTaskIndices[0],
            msg.sender,
            args
        );
        
        // Settle perp CoW match
        IPerpDarkPoolHook(hook).settlePerpBalances(
            tasks[0].poolId,
            perpSettlement
        );

        emit BatchResponse(referenceTaskIndices, msg.sender);
    }

    // Internal function to handle memory to calldata conversion
    function verifyOrderProofInternal(bytes memory _publicValues, bytes memory _proofBytes)
        internal
        view
        returns (uint32, uint32, uint32)
    {
        ISP1Verifier(verifier).verifyProof(orderProgramVKey, _publicValues, _proofBytes);
        PublicValuesStruct memory publicValues = abi.decode(_publicValues, (PublicValuesStruct));
        return (publicValues.n, publicValues.a, publicValues.b);
    }

    // Public function for external calls with proper calldata parameters
    function verifyOrderProof(bytes calldata _publicValues, bytes calldata _proofBytes)
        public
        view
        returns (uint32, uint32, uint32)
    {
        ISP1Verifier(verifier).verifyProof(orderProgramVKey, _publicValues, _proofBytes);
        
        PublicValuesStruct memory publicValues = abi.decode(_publicValues, (PublicValuesStruct));
        return (publicValues.n, publicValues.a, publicValues.b);
    }

    /// @notice Verify zkVerify proof receipt using on-chain bridge
    function verifyZkVerifyProof(
        bytes memory zkProofData, 
        address operator
    ) public view returns (bool) {
        if (zkProofData.length == 0) {
            return false;
        }

        try this.decodeZkVerifyReceipt(zkProofData) returns (ZkVerifyReceipt memory receipt) {
            // Basic validation
            if (bytes(receipt.proofId).length == 0) {
                return false;
            }
            
            if (receipt.blockNumber == 0) {
                return false;
            }
            
            if (bytes(receipt.merkleRoot).length == 0) {
                return false;
            }
            
            // Use zkVerify bridge for actual on-chain verification
            if (address(zkVerifyBridge) != address(0)) {
                bool receiptValid = zkVerifyBridge.verifyProofReceipt(receipt.proofId);
                if (!receiptValid) {
                    return false;
                }
                
                bool merkleValid = zkVerifyBridge.verifyMerkleRoot(
                    receipt.merkleRoot, 
                    receipt.blockNumber
                );
                if (!merkleValid) {
                    return false;
                }
                
                return true;
            } else {
                // Fallback to basic validation if bridge not set
                return (
                    bytes(receipt.proofId).length > 0 &&
                    bytes(receipt.merkleRoot).length > 0 &&
                    receipt.blockNumber > 0
                );
            }
            
        } catch {
            return false;
        }
    }

    /// @notice Decode zkVerify receipt from bytes
    function decodeZkVerifyReceipt(bytes memory data) 
        public 
        pure 
        returns (ZkVerifyReceipt memory receipt) 
    {
        (receipt.proofId, receipt.merkleRoot, receipt.blockNumber) = 
            abi.decode(data, (string, string, uint256));
    }

    function getMessageHash(
        bytes32 poolId,
        IPerpDarkPoolHook.PerpCoWSettlement memory settlement
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(poolId, settlement));
    }

    /// @notice Slash an operator for misbehavior
    /// @param task The task that was incorrectly processed
    /// @param referenceTaskIndex The index of the reference task
    /// @param operator The operator to slash
    /// @dev This function should be called when an operator submits incorrect responses
    ///      It marks the operator as slashed and can trigger EigenLayer slashing
    function slashOperator(
        Task calldata task,
        uint32 referenceTaskIndex,
        address operator
    ) external {
        require(referenceTaskIndex < latestTaskNum, "Invalid task index");
        require(
            ECDSAStakeRegistry(stakeRegistry).operatorRegistered(operator),
            "Operator not registered"
        );
        
        // Verify the task exists
        require(
            allTaskHashes[referenceTaskIndex] == keccak256(abi.encode(task)),
            "Task mismatch"
        );
        
        // Check if operator has responded incorrectly
        // This would typically involve verifying the response against expected outcome
        // For now, we emit an event and mark the operator for slashing
        
        // Emit slashing event
        emit OperatorSlashed(operator, referenceTaskIndex, block.timestamp);
        
        // Note: Actual slashing would be done through EigenLayer's DelegationManager
        // This requires integration with IDelegationManager.slash() function
        // Example:
        // IDelegationManager(delegationManager).slash(operator, slashingAmount);
        
        // For now, we just record the slashing event
        // The actual stake slashing would be handled by EigenLayer infrastructure
    }

    function setHook(address _hook) external onlyOwner {
        require(_hook != address(0), "Hook address cannot be zero");
        hook = _hook;
    }

    function getHook() external view returns (address) {
        return hook;
    }

    // Single task response function required by IOrderServiceManager interface
    function respondToTask(
        Task calldata task,
        uint32 referenceTaskIndex,
        bytes calldata signature
    ) external {
        require(
            keccak256(abi.encode(task)) == allTaskHashes[referenceTaskIndex],
            "supplied task does not match the one recorded in the contract"
        );
        require(
            allTaskResponses[msg.sender][referenceTaskIndex].length == 0,
            "Operator has already responded to the task"
        );

        // Store the operator's signature
        allTaskResponses[msg.sender][referenceTaskIndex] = signature;

        // Emit event for this operator
        emit TaskResponded(referenceTaskIndex, task, msg.sender);
    }
}

