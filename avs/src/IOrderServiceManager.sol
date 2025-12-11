// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IOrderServiceManager {
    struct Task {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
        address sender;
        bytes32 poolId;
        uint32 taskCreatedBlock;
        uint32 taskId;
        // Perp-specific fields
        bool isPerpOrder;
        uint256 positionId;      // 0 for new positions
        uint256 marginAmount;    // Margin in USDC (6 decimals)
        uint256 leverage;        // Leverage (basis points)
        bool isLong;            // Long or short
    }

    event NewTaskCreated(uint32 indexed taskIndex, Task task);
    event BatchResponse(uint32[] indexed referenceTaskIndices, address sender);

    function latestTaskNum() external view returns (uint32);

    function allTaskHashes(
        uint32 taskIndex
    ) external view returns (bytes32);

    function allTaskResponses(
        address operator,
        uint32 taskIndex
    ) external view returns (bytes memory);

    function respondToTask(
        Task calldata task,
        uint32 referenceTaskIndex,
        bytes calldata signature
    ) external;

    function slashOperator(
        Task calldata task,
        uint32 referenceTaskIndex,
        address operator
    ) external;

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
    ) external returns (Task memory task);
}

