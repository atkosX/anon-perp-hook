import * as dotenv from "dotenv";
import { ethers } from "ethers";
dotenv.config();
const fs = require('fs');
const path = require('path');

import {
    createPublicClient,
    createWalletClient,
    getContract,
    http,
    keccak256,
    encodePacked,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { anvil, holesky } from "viem/chains";

import bigDecimal from "js-big-decimal";

export type TransferBalance = {
    amount: bigint;
    currency: `0x${string}`;
    sender: `0x${string}`;
};

export type SwapBalance = {
    amountSpecified: bigint;
    zeroForOne: boolean;
    sqrtPriceLimitX96: bigint;
};

export type PoolPriceInfo = {
    poolKey: PoolKey;
    spotPrice: number;
    liquidity: bigint;
};

export type Task = {
    // Base fields
    zeroForOne: boolean;
    amountSpecified: bigint;
    sqrtPriceLimitX96: bigint;
    sender: `0x${string}`;
    poolId: `0x${string}`;
    poolKey: PoolKey;
    taskCreatedBlock: number;
    taskId: number;
    poolOutputAmount: bigint | null;
    poolInputAmount: bigint | null;
    extraData: `0x${string}`;

    // Perp-specific fields (required for all tasks)
    isPerpOrder: boolean;
    positionId?: number;
    marginAmount?: bigint;
    leverage?: bigint;
    isLong?: boolean;
    
    // Pool info
    acceptedPools: PoolKey[];
    poolPrices?: PoolPriceInfo[];
};

export enum Feasibility {
    NONE = "NONE",
    PERP_COW = "PERP_COW",  // Perp CoW match (long vs short)
    VAMM = "VAMM"           // vAMM execution (unmatched)
}

export type PossibleResult = {
    matchings: Matching[];
    feasible: boolean;
    perpSettlement?: PerpCoWSettlement;
};

export type Matching = {
    tasks: Task[];
    feasibility: Feasibility;
    isPerpCow?: boolean;
};

export type PerpCoWSettlement = {
    longTrader: `0x${string}`;
    shortTrader: `0x${string}`;
    poolId: `0x${string}`;
    matchSize: bigint;
    matchPrice: bigint;
    longMargin: bigint;
    shortMargin: bigint;
    longLeverage: bigint;
    shortLeverage: bigint;
};

export type PoolKey = {
    currency0: `0x${string}`;
    currency1: `0x${string}`;
    fee: number;
    tickSpacing: number;
    hooks: `0x${string}`;
};

export const account = privateKeyToAccount(
    process.env.PRIVATE_KEY! as `0x${string}`
);

export const walletClient = createWalletClient({
    chain: process.env.IS_DEV === "true" ? anvil : holesky,
    transport: http(),
    account,
    pollingInterval: 2000,
});

export const publicClient = createPublicClient({
    chain: process.env.IS_DEV === "true" ? anvil : holesky,
    transport: http(),
    pollingInterval: 2000,
});

// Setup env variables
const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);
let chainId = process.env.CHAIN_ID ? parseInt(process.env.CHAIN_ID) : 31337;

// Load deployment data (adjust paths as needed)
const avsDeploymentData = JSON.parse(fs.readFileSync(path.resolve(__dirname, `../avs/contract/deployments/avs/${chainId}.json`), 'utf8'));
const coreDeploymentData = JSON.parse(fs.readFileSync(path.resolve(__dirname, `../avs/contract/deployments/core/${chainId}.json`), 'utf8'));
export const hookDeploymentData = JSON.parse(fs.readFileSync(path.resolve(__dirname, `../contracts/deployments/${chainId}/PerpDarkPoolHook.json`)));

const delegationManagerAddress = coreDeploymentData.addresses.delegationManager;
const avsDirectoryAddress = coreDeploymentData.addresses.avsDirectory;
export const avsServiceManagerAddress = avsDeploymentData.addresses.orderServiceManager;
const ecdsaStakeRegistryAddress = avsDeploymentData.addresses.stakeRegistry;
const hookAddr = hookDeploymentData.addresses.hook;

const delegationManagerABI = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../abis/IDelegationManager.json'), 'utf8'));
const ecdsaRegistryABI = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../abis/ECDSAStakeRegistry.json'), 'utf8'));
export const avsServiceManagerABI = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../abis/OrderServiceManager.json'), 'utf8'));
const avsDirectoryABI = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../abis/IAVSDirectory.json'), 'utf8'));
const hookABI = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../abis/PerpDarkPoolHook.json'), 'utf8'));

// Initialize contract objects from ABIs
export const delegationManager = new ethers.Contract(delegationManagerAddress, delegationManagerABI, wallet);
export const serviceManager = new ethers.Contract(avsServiceManagerAddress, avsServiceManagerABI, wallet);
export const ecdsaRegistryContract = new ethers.Contract(ecdsaStakeRegistryAddress, ecdsaRegistryABI, wallet);
export const avsDirectory = new ethers.Contract(avsDirectoryAddress, avsDirectoryABI, wallet);
export const hook = new ethers.Contract(hookAddr, hookABI, wallet);

// Load MarginAccount ABI and address
const marginAccountABI = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../abis/MarginAccount.json'), 'utf8'));
const marginAccountAddress = hookDeploymentData.addresses?.marginAccount || hookDeploymentData.addresses?.MarginAccount;
export const marginAccount = marginAccountAddress 
    ? new ethers.Contract(marginAccountAddress, marginAccountABI, wallet)
    : null;

// Helper to calculate pool ID from key
export function calculatePoolId(key: PoolKey): `0x${string}` {
    return keccak256(
        encodePacked(
            ["address", "address", "uint24", "int24", "address"],
            [key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks]
        )
    );
}

// Helper to get vAMM price from hook
export async function getVAMMPrice(poolId: `0x${string}`): Promise<bigint> {
    try {
        const price = await hook.getMarkPrice(poolId);
        return BigInt(price.toString());
    } catch (error) {
        console.error(`Error getting vAMM price for pool ${poolId}:`, error);
        return BigInt(0);
    }
}

// Helper to get slot0 data using extsload
export async function getSlot0Data(poolManager: any, poolId: `0x${string}`): Promise<[bigint, number]> {
    const stateSlot = keccak256(encodePacked(["bytes32", "uint256"], [poolId, BigInt(0)]));
    const data = await poolManager.read.extsload([stateSlot]);
    const sqrtPriceX96 = BigInt(data) >> BigInt(96);
    const tick = Number((BigInt(data) >> BigInt(160)) & ((BigInt(1) << BigInt(24)) - BigInt(1)));
    return [sqrtPriceX96, tick];
}

// Helper to get liquidity using extsload
export async function getPoolLiquidity(poolManager: any, poolId: `0x${string}`): Promise<bigint> {
    const stateSlot = keccak256(encodePacked(["bytes32", "uint256"], [poolId, BigInt(0)]));
    const LIQUIDITY_OFFSET = BigInt(4);
    const liquiditySlot = BigInt(stateSlot) + LIQUIDITY_OFFSET;
    const liquiditySlotHex = `0x${liquiditySlot.toString(16).padStart(64, '0')}` as `0x${string}`;
    const data = await poolManager.read.extsload([liquiditySlotHex]);
    return BigInt(data);
}

// Helper to get user's available balance from MarginAccount
export async function getUserAvailableBalance(userAddress: string): Promise<bigint> {
    if (!marginAccount) {
        console.warn("MarginAccount not initialized, returning 0");
        return BigInt(0);
    }
    try {
        const balance = await marginAccount.getAvailableBalance(userAddress);
        return BigInt(balance.toString());
    } catch (error) {
        console.error(`Error fetching balance for ${userAddress}:`, error);
        return BigInt(0);
    }
}

// Helper to get nullifier set (for now returns empty, can be extended to read from contract events)
export async function getNullifierSet(): Promise<string[]> {
    // TODO: In production, read from contract events or storage
    // For now, return empty array - nullifiers can be tracked via events
    return [];
}

