import { parseEventLogs, formatEther } from "viem";
import { ethers } from "ethers";

import { findPerpCoWMatches, calculatePerpMatchPrice, computePerpSettlement, computePerpResult } from "./matching";
import { registerOperator } from "./register";
import {
    Task,
    account,
    hook,
    publicClient,
    serviceManager,
    walletClient,
    avsServiceManagerABI,
    getVAMMPrice,
    PerpCoWSettlement,
    getUserAvailableBalance,
    getNullifierSet
} from "./utils";
import { generateZKProof, prepareProofInput } from "./zk-proof";
import { Mathb } from "./math";

// Setup env variables
const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);
let chainId = 31337;

let latestBatchNumber: bigint = BigInt(0);
const MAX_BLOCKS_PER_BATCH = 10;
const batches: Record<string, Task[]> = {};

// Enhanced registration function with proper error handling
const safeRegisterOperator = async () => {
    try {
        console.log("Checking operator registration status...");

        let isRegistered = false;
        try {
            isRegistered = await serviceManager.isOperatorRegistered([account.address]);
        } catch (checkError) {
            console.log("Could not check registration status, attempting registration...");
        }

        if (isRegistered) {
            console.log("Operator already registered, skipping registration");
            return;
        }

        console.log("Registering operator...");
        await registerOperator();
        console.log("Operator registered successfully");

    } catch (error: any) {
        if (error.message?.includes("already initialized") ||
            error.message?.includes("already registered") ||
            error.reason?.includes("already initialized")) {
            console.log("Operator already registered (caught initialization error)");
            return;
        }

        if (error.code === 'CALL_EXCEPTION' &&
            error.reason?.includes("already initialized")) {
            console.log("Operator already registered (contract already initialized)");
            return;
        }

        console.error("Registration error (continuing anyway):", error.message || error);
        console.log("Continuing with monitoring...");
    }
};

const startMonitoring = async () => {
    console.log("Starting perp task monitoring...");

    const unwatchTasks = serviceManager.on("NewTaskCreated", async (logs: any) => {
        try {
            const parsedLogs = parseEventLogs({
                logs: logs,
                abi: avsServiceManagerABI,
                eventName: "NewTaskCreated",
            });

            const event = parsedLogs[0] as any;
            const taskData = event.args?.task || event.args;

            // Get pool key
            let poolKey;
            try {
                poolKey = await hook.poolKeys(taskData.poolId);
            } catch (poolError) {
                console.error("Error getting pool key for task:", poolError);
                return;
            }

            const task: Task = {
                ...taskData as Task,
                poolKey: {
                    currency0: poolKey[0],
                    currency1: poolKey[1],
                    fee: poolKey[2],
                    tickSpacing: poolKey[3],
                    hooks: poolKey[4],
                },
                acceptedPools: [
                    {
                        currency0: poolKey[0],
                        currency1: poolKey[1],
                        fee: poolKey[2],
                        tickSpacing: poolKey[3],
                        hooks: poolKey[4],
                    }
                ],
                poolOutputAmount: null,
                poolInputAmount: null,
                isPerpOrder: taskData.isPerpOrder || true, // All tasks are perp orders
            };

            if (!batches[latestBatchNumber.toString()]) {
                batches[latestBatchNumber.toString()] = [];
            }
            batches[latestBatchNumber.toString()].push(task);
            console.log("Perp task added to batch:", task.taskId);
        } catch (error) {
            console.error("Error processing new task:", error);
        }
    });

    const unwatchBlocks = publicClient.watchBlockNumber({
        onBlockNumber: (blockNumber) => {
            console.log("Block number:", blockNumber);
            if (latestBatchNumber === BigInt(0)) {
                console.log("First batch created at block:", blockNumber);
                latestBatchNumber = blockNumber;
            } else if (blockNumber - latestBatchNumber >= MAX_BLOCKS_PER_BATCH) {
                processBatch(latestBatchNumber);
                latestBatchNumber = blockNumber;
                console.log("New batch created at block:", latestBatchNumber);
            }
        },
    });

    return { unwatchTasks, unwatchBlocks };
};

const processBatch = async (batchNumber: bigint) => {
    try {
        const tasks = batches[batchNumber.toString()];
        if (!tasks || tasks.length === 0) {
            console.log(`No tasks in batch ${batchNumber}`);
            return;
        }

        console.log(`Processing batch ${batchNumber} with ${tasks.length} perp tasks`);

        // Get vAMM prices for each task's pool
        const pricePromises = tasks.map(async (task) => {
            try {
                const vammPrice = await getVAMMPrice(task.poolId);
                // Store price for later use
                task.poolPrices = [{
                    poolKey: task.poolKey,
                    spotPrice: Number(vammPrice) / 1e18,
                    liquidity: BigInt(0) // vAMM doesn't use real liquidity
                }];
                console.log(`vAMM price obtained for task ${task.taskId}: ${formatEther(vammPrice)}`);
            } catch (err: any) {
                console.error(`Error getting vAMM price for task ${task.taskId}:`, err.message);
            }
        });

        await Promise.allSettled(pricePromises);

        // Find perp CoW matches (long vs short)
        const perpMatches = findPerpCoWMatches(tasks);
        const matchedTasks = new Set<number>();
        
        perpMatches.forEach(match => {
            match.forEach(idx => matchedTasks.add(idx));
        });

        console.log(`Found ${perpMatches.length} perp CoW matches`);

        // Get unmatched task indices
        const unmatchedIndices: number[] = [];
        for (let i = 0; i < tasks.length; i++) {
            if (!matchedTasks.has(i)) {
                unmatchedIndices.push(i);
            }
        }

        console.log(`Unmatched tasks: ${unmatchedIndices.length} (will execute via vAMM)`);

        // Process CoW matches
        if (perpMatches.length > 0) {
            const firstMatch = perpMatches[0];
            const longTask = tasks[firstMatch[0]];
            const shortTask = tasks[firstMatch[1]];
            
            // Get vAMM price for match price calculation
            const vammPrice = await getVAMMPrice(longTask.poolId);
            
            // Calculate match size (use minimum of both orders)
            const longSize = Mathb.abs(longTask.amountSpecified);
            const shortSize = Mathb.abs(shortTask.amountSpecified);
            const matchSize = Mathb.min(longSize, shortSize);
            
            // Calculate match price
            const matchPrice = calculatePerpMatchPrice(longTask, shortTask, vammPrice);
            
            // Create perp settlement
            const perpSettlement = computePerpSettlement(longTask, shortTask, matchSize, matchPrice);
            
            // Generate ZK proofs for matched tasks
            let zkProof = "0x";
            try {
                // Generate proof for the long task (representative proof for the match)
                // In production, you might want to generate proofs for both tasks
                const longTaskForProof = tasks.find(t => t.isLong);
                if (longTaskForProof) {
                    // Get user balance from MarginAccount
                    const userBalance = await getUserAvailableBalance(longTaskForProof.sender);
                    const nullifierSet = await getNullifierSet();
                    
                    const proofInput = prepareProofInput(longTaskForProof, userBalance, nullifierSet);
                    zkProof = await generateZKProof(proofInput);
                    console.log("ZK proof generated:", zkProof.slice(0, 20) + "...");
                    console.log(`User balance fetched: ${userBalance.toString()}`);
                }
            } catch (proofError: any) {
                console.warn("ZK proof generation failed, using empty proof:", proofError.message);
                zkProof = "0x"; // Fallback to empty proof
            }

            // Get message hash and sign
            try {
                const messageHash = await serviceManager.getMessageHash(
                    tasks[0].poolId,
                    perpSettlement
                );

                const signature = await walletClient.signTypedData({
                    account,
                    domain: {},
                    types: {
                        Message: [{ name: 'hash', type: 'bytes32' }]
                    },
                    primaryType: 'Message',
                    message: {
                        hash: messageHash
                    }
                });

                // Submit response with perp settlement
                const tx = await serviceManager.respondToBatch(
                    tasks.map(task => ({
                        taskId: Number(task.taskId),
                        zeroForOne: task.zeroForOne,
                        amountSpecified: task.amountSpecified,
                        sqrtPriceLimitX96: task.sqrtPriceLimitX96,
                        sender: task.sender as `0x${string}`,
                        poolId: task.poolId as `0x${string}`,
                        taskCreatedBlock: task.taskCreatedBlock,
                        isPerpOrder: task.isPerpOrder,
                        positionId: task.positionId || 0,
                        marginAmount: task.marginAmount || BigInt(0),
                        leverage: task.leverage || BigInt(0),
                        isLong: task.isLong || false,
                    })),
                    tasks.map(task => Number(task.taskId)),
                    perpSettlement,
                    signature,
                    zkProof
                );

                console.log("Perp CoW match transaction submitted successfully");
                console.log(`Match: Long ${longTask.sender} vs Short ${shortTask.sender}, Size: ${formatEther(matchSize)}, Price: ${formatEther(matchPrice)}`);

            } catch (txError: any) {
                console.error("Transaction submission error:", txError.message);
            }
        } else {
            console.log("No CoW matches found - all orders will execute via vAMM");
            // For unmatched orders, they will execute via vAMM in the hook's direct path
            // No need to submit response for unmatched orders
        }

        // Remove processed tasks from batch
        delete batches[batchNumber.toString()];
        console.log(`Batch ${batchNumber} processed and cleaned up`);

    } catch (error) {
        console.error("Error processing batch:", error);
    }
};

const main = async () => {
    console.log("Starting Perp Dark Pool Monitoring Service...");

    try {
        await safeRegisterOperator();
        console.log("Starting task monitoring...");
        await startMonitoring();
        console.log("Perp Dark Pool Monitoring Service is now running...");
    } catch (error) {
        console.error("Fatal error in main:", error);
        process.exitCode = 1;
    }
};

// Graceful shutdown handling
process.on('SIGINT', () => {
    console.log('\nReceived SIGINT. Shutting down gracefully...');
    process.exit(0);
});

process.on('SIGTERM', () => {
    console.log('\nReceived SIGTERM. Shutting down gracefully...');
    process.exit(0);
});

main().catch((error) => {
    console.error("Unhandled error:", error);
    process.exitCode = 1;
});

