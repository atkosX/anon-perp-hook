# Anon Perp Hook

Uniswap V4 hook for perpetual futures trading with dark pool matching. Orders are matched off-chain through an EigenLayer AVS operator network before settlement on-chain.

## Features

- Perpetual futures only (no spot trading)
- CoW matching for long/short orders in the same pool
- vAMM pricing (main Uniswap pool is no-op)
- Order hiding with ZK proofs for MEV protection
- EigenLayer AVS for decentralized order processing
- Centralized margin account (USDC collateral)
- NFT-based position representation

## Project Structure

```
contracts/src/          # Core contracts
├── PerpDarkPoolHook.sol
├── MarginAccount.sol
├── PositionManager.sol
├── PositionFactory.sol
├── FundingOracle.sol
└── MarketManager.sol

avs/src/                # EigenLayer AVS contracts
├── OrderServiceManager.sol
└── ZkVerifyBridge.sol

operator/               # Operator service (TypeScript)
├── index.ts
├── matching.ts
└── zk-proof.ts

order-engine/           # SP1 ZK proof program (Rust)
└── program/src/lib.rs
```

## Setup

### Prerequisites

- Foundry
- Node.js 18+
- Rust (for SP1 proof generation)

### Installation

```bash
# Install dependencies
./scripts/SetupDependencies.sh

# Configure environment
cp env.example .env
# Edit .env with your RPC URL and keys

# Build contracts
forge build

# Run tests
forge test
```

## Usage

### Submitting Orders

Orders are submitted via Uniswap V4's swap function with encoded hook data:

```solidity
// CoW matching order
bytes memory hookData = abi.encode(
    ORDER_TYPE_PERP_COW,  // 1
    abi.encode(
        sender,
        isLong,           // true = long, false = short
        marginAmount,     // USDC (6 decimals)
        leverage,         // e.g., 2e18 = 2x
        maxSlippage,      // basis points
        positionId        // 0 for new position
    )
);

poolManager.swap(key, swapParams, hookData);
```

For direct vAMM execution (bypass dark pool), use `ORDER_TYPE_PERP_DIRECT` (2).

## Architecture

### Order Flow

1. User submits order via `poolManager.swap()` with hook data
2. `PerpDarkPoolHook` intercepts, locks margin, creates task in AVS
3. Operator monitors tasks, batches them (10 blocks), finds CoW matches
4. Operator generates ZK proof, submits settlement to AVS
5. AVS verifies and calls hook to settle positions
6. Positions created, vAMM reserves synced

### CoW Matching

Long and short orders in the same pool are matched directly. Match price is the median of vAMM mark price and implied prices from both orders. Positions are created for both traders atomically.

### vAMM Fallback

Unmatched orders execute directly through the vAMM. Virtual reserves are updated and the position is created immediately. The main Uniswap pool remains unused (no-op).

## Testing

```bash
# All tests
forge test

# Verbose output
forge test -vvv

# Specific test file
forge test --match-path contracts/test/PerpDarkPoolHook.t.sol

# Fork tests (requires MAINNET_RPC_URL in .env)
forge test --match-path contracts/test/ForkTest.sol
```

## Deployment

Deploy in order:

```bash
# 1. Core contracts (MarginAccount, PositionManager, etc.)
forge script scripts/DeployCore.s.sol --rpc-url $RPC_URL --broadcast

# 2. Hook and AVS contracts
forge script scripts/DeployHook.s.sol --rpc-url $RPC_URL --broadcast

# 3. Initialize markets
forge script scripts/InitializeMarket.s.sol --rpc-url $RPC_URL --broadcast
```

## Configuration

Required environment variables (see `env.example`):

```env
RPC_URL=http://localhost:8545
PRIVATE_KEY=your_private_key
CHAIN_ID=31337
MAINNET_RPC_URL=https://...  # For fork tests
MARGIN_ACCOUNT=0x...
POSITION_MANAGER=0x...
FUNDING_ORACLE=0x...
PERP_DARK_POOL_HOOK=0x...
ORDER_SERVICE_MANAGER=0x...
```

### Running the Operator

The operator service monitors tasks, finds matches, and submits settlements:

```bash
cd operator
npm install
npm run operator
```

The operator must be registered in EigenLayer first.

## Security Considerations

- Orders are hidden until batch processing (MEV protection)
- ZK proofs validate order commitments without revealing details
- Nullifier system prevents replay attacks
- Operator signatures verified on-chain
- Margin locked before order creation

## Dependencies

- Uniswap V4 Core
- EigenLayer Middleware
- SP1 (ZK proof generation)
- Chainlink (price feeds)
- OpenZeppelin Contracts

## License

MIT
