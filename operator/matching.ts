import { Mathb } from "./math";
import { Feasibility, Matching, PossibleResult, Task, PerpCoWSettlement } from "./utils";

/// @notice Find perp CoW matches (long vs short in same pool)
export function findPerpCoWMatches(tasks: Task[]): number[][] {
    const matches: number[][] = [];
    const matchedTasks = new Set<number>();

    // Find long vs short matches in the same pool
    for (let i = 0; i < tasks.length; i++) {
        if (matchedTasks.has(i)) continue;

        const taskA = tasks[i];
        if (!taskA.isPerpOrder || !taskA.isLong) continue; // Look for long orders

        for (let j = i + 1; j < tasks.length; j++) {
            if (matchedTasks.has(j)) continue;

            const taskB = tasks[j];
            if (!taskB.isPerpOrder || taskB.isLong) continue; // Look for short orders

            // Check if same pool and opposite directions
            if (taskA.poolId === taskB.poolId) {
                matches.push([i, j]);
                matchedTasks.add(i);
                matchedTasks.add(j);
                break;
            }
        }
    }

    return matches;
}

/// @notice Calculate execution price for perp CoW match
export function calculatePerpMatchPrice(longTask: Task, shortTask: Task, vammPrice: bigint): bigint {
    // Use median of:
    // 1. vAMM mark price
    // 2. Long task's implied price (if available)
    // 3. Short task's implied price (if available)
    
    const prices: bigint[] = [vammPrice];
    
    // Calculate implied prices from tasks if possible
    if (longTask.poolInputAmount && longTask.poolOutputAmount) {
        // Price = output / input (in 18 decimals)
        const impliedPrice = (longTask.poolOutputAmount * BigInt(1e30)) / longTask.poolInputAmount;
        prices.push(impliedPrice);
    }
    
    if (shortTask.poolInputAmount && shortTask.poolOutputAmount) {
        const impliedPrice = (shortTask.poolOutputAmount * BigInt(1e30)) / shortTask.poolInputAmount;
        prices.push(impliedPrice);
    }
    
    // Return median
    prices.sort((a, b) => {
        if (a < b) return -1;
        if (a > b) return 1;
        return 0;
    });
    
    if (prices.length % 2 === 0) {
        const mid = prices.length / 2;
        return (prices[mid - 1] + prices[mid]) / BigInt(2);
    } else {
        return prices[Math.floor(prices.length / 2)];
    }
}

/// @notice Compute perp CoW settlement
export function computePerpSettlement(
    longTask: Task,
    shortTask: Task,
    matchSize: bigint,
    matchPrice: bigint
): PerpCoWSettlement {
    return {
        longTrader: longTask.sender,
        shortTrader: shortTask.sender,
        poolId: longTask.poolId,
        matchSize: matchSize,
        matchPrice: matchPrice,
        longMargin: longTask.marginAmount || BigInt(0),
        shortMargin: shortTask.marginAmount || BigInt(0),
        longLeverage: longTask.leverage || BigInt(0),
        shortLeverage: shortTask.leverage || BigInt(0),
    };
}

/// @notice Compute result for perp matching
export function computePerpResult(
    tasks: Task[],
    perpMatches: number[][],
    unmatchedIndices: number[]
): PossibleResult {
    const matchings: Matching[] = [];
    
    // Add CoW matches
    for (const match of perpMatches) {
        matchings.push({
            tasks: match.map(i => tasks[i]),
            feasibility: Feasibility.PERP_COW,
            isPerpCow: true
        });
    }
    
    // Add unmatched tasks (vAMM execution)
    for (const idx of unmatchedIndices) {
        matchings.push({
            tasks: [tasks[idx]],
            feasibility: Feasibility.VAMM,
            isPerpCow: false
        });
    }
    
    return {
        matchings,
        feasible: matchings.length > 0,
    };
}

/// @notice Check if combination is possible (for perps, only direct matches)
export function isCombinationPossible(tasks: Task[]): boolean {
    // Single task is always possible via vAMM
    if (tasks.length === 1) return true;
    
    // For perps, only 2-task matches (long vs short) are valid
    if (tasks.length === 2) {
        const taskA = tasks[0];
        const taskB = tasks[1];
        
        // Both must be perp orders
        if (!taskA.isPerpOrder || !taskB.isPerpOrder) return false;
        
        // Must be same pool
        if (taskA.poolId !== taskB.poolId) return false;
        
        // Must be opposite directions (one long, one short)
        if (taskA.isLong === taskB.isLong) return false;
        
        return true;
    }
    
    return false;
}

