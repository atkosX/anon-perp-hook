#!/bin/bash

# Deploy all contracts in sequence

set -e

echo "🚀 Deploying all contracts..."

# Check environment
if [ -z "$RPC_URL" ]; then
    echo "❌ RPC_URL not set. Please set it in .env or export it."
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo "❌ PRIVATE_KEY not set. Please set it in .env or export it."
    exit 1
fi

# Load .env if it exists
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

echo "📦 Step 1: Deploying core contracts..."
forge script scripts/DeployCore.s.sol \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key ${ETHERSCAN_API_KEY:-""} \
    || echo "⚠️  Core deployment failed or contracts already deployed"

echo ""
echo "📦 Step 2: Deploying hook and AVS contracts..."
forge script scripts/DeployHook.s.sol \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key ${ETHERSCAN_API_KEY:-""} \
    || echo "⚠️  Hook deployment failed or contracts already deployed"

echo ""
echo "📦 Step 3: Initializing markets..."
forge script scripts/InitializeMarket.s.sol \
    --rpc-url $RPC_URL \
    --broadcast \
    || echo "⚠️  Market initialization failed"

echo ""
echo "✨ Deployment complete!"
echo ""
echo "Next steps:"
echo "1. Update .env with deployed contract addresses"
echo "2. Configure operator with contract addresses"
echo "3. Start operator service: npm run operator"

