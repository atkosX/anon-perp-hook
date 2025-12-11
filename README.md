# Anon Perp Hook - Perpetual Futures Dark Pool

A dark pool implementation for perpetual futures trading on Uniswap V4, featuring CoW (Coincidence of Wants) matching and MEV protection.

## 🎯 Features

- **Perp-Only Trading**: Only perpetual futures, no spot trading
- **CoW Matching**: Direct matching of long vs short orders (same pool)
- **vAMM Integration**: Virtual AMM for pricing (main pool is no-op)
- **Dark Pool**: Order hiding with ZK proofs for MEV protection
- **EigenLayer AVS**: Decentralized operator network
- **Margin Management**: Centralized USDC vault for collateral
- **NFT Positions**: ERC721-based position representation

## 📁 Project Structure

```
anon-perp-hook/
├── contracts/src/          # Solidity contracts
│   ├── PerpDarkPoolHook.sol
│   ├── MarginAccount.sol
│   ├── PositionManager.sol
│   └── libraries/
├── avs/src/               # EigenLayer AVS contracts
│   ├── OrderServiceManager.sol
│   └── ZkVerifyBridge.sol
├── operator/              # TypeScript operator code
│   ├── index.ts
│   ├── matching.ts
│   └── utils.ts
├── scripts/               # Deployment & setup scripts
├── abis/                  # Contract ABIs (generated)
└── order-engine/          # SP1 ZK proof program
```

## 🚀 Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 18+
- Rust (for SP1 proofs, optional)

### Setup

1. **Clone and install dependencies:**
   ```bash
   git clone <repo-url>
   cd anon-perp-hook
   ./scripts/SetupDependencies.sh
   ```

2. **Configure environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

3. **Build contracts:**
   ```bash
   forge build
   ```

4. **Generate ABIs:**
   ```bash
   ./scripts/GenerateABIs.sh
   ```

5. **Run tests:**
   ```bash
   ./scripts/TestAll.sh
   ```

## 📖 Usage

### Submit Perp Order with CoW Matching

```solidity
// Encode order data
bytes memory hookData = abi.encode(
    ORDER_TYPE_PERP_COW,  // 1
    abi.encode(
        sender,
        isLong,           // true for long, false for short
        marginAmount,     // USDC amount (6 decimals)
        leverage,         // Basis points (e.g., 1000 = 10x)
        maxSlippage,      // Basis points
        positionId        // 0 for new position
    )
);

// Call pool swap with hook data
poolManager.swap(key, swapParams, hookData);
```

### Submit Direct vAMM Order

```solidity
bytes memory hookData = abi.encode(
    ORDER_TYPE_PERP_DIRECT,  // 2
    abi.encode(...)  // Same structure as above
);
```

## 🏗️ Architecture

### Order Flow

```
User → PerpDarkPoolHook → OrderServiceManager → Operator
         ↓                      ↓                    ↓
    [Lock Margin]        [Create Task]      [Find CoW Match]
         ↓                      ↓                    ↓
    [ERC6909 Lock]       [ZK Proof]         [Submit Settlement]
         ↓                      ↓                    ↓
    [Position Created]   [vAMM Sync]        [CoW Match Executed]
```

### CoW Matching

- Long orders are matched with short orders
- Same pool, opposite direction
- Match price calculated from vAMM + task prices
- Positions created for both traders
- vAMM reserves synchronized

### vAMM Fallback

- Unmatched orders execute via vAMM
- Virtual reserves updated
- Position created directly
- Main Uniswap pool remains no-op

## 🧪 Testing

```bash
# Run all tests
forge test

# Run with verbose output
forge test -vvv

# Run specific test
forge test --match-test testPerpOrderCreation
```

## 📦 Deployment

### 1. Deploy Core Contracts

```bash
forge script scripts/DeployCore.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

### 2. Deploy Hook & AVS

```bash
forge script scripts/DeployHook.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

### 3. Initialize Markets

```bash
forge script scripts/InitializeMarket.s.sol \
  --rpc-url $RPC_URL \
  --broadcast
```

## 🔧 Configuration

### Environment Variables

```env
RPC_URL=http://localhost:8545
PRIVATE_KEY=your_private_key
CHAIN_ID=31337
MARGIN_ACCOUNT=0x...
POSITION_MANAGER=0x...
FUNDING_ORACLE=0x...
PERP_DARK_POOL_HOOK=0x...
ORDER_SERVICE_MANAGER=0x...
```

### Operator Setup

1. Register operator in EigenLayer
2. Configure operator environment
3. Start operator service:
   ```bash
   npm run operator
   ```

## 📚 Documentation

- [Quick Start Guide](./QUICK_START.md)
- [Implementation Status](./IMPLEMENTATION_STATUS.md)
- [Build Summary](./BUILD_SUMMARY.md)
- [Missing Components](./MISSING_COMPONENTS.md)

## 🔒 Security

- Order hiding prevents front-running
- ZK proofs validate order commitments
- EigenLayer AVS provides decentralized validation
- MarginAccount manages collateral securely
- Positions are NFT-based for composability

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

MIT

## 🙏 Acknowledgments

- Uniswap V4 for the hook architecture
- EigenLayer for AVS infrastructure
- SP1 for ZK proof generation
- Pyth Network for price feeds
