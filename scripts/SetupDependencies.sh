#!/bin/bash

# Setup script for anon-perp-hook dependencies

set -e

echo "🚀 Setting up anon-perp-hook dependencies..."

# Check if foundry is installed
if ! command -v forge &> /dev/null; then
    echo "❌ Foundry is not installed. Please install it first:"
    echo "   curl -L https://foundry.paradigm.xyz | bash"
    exit 1
fi

echo "✅ Foundry is installed"

# Install Foundry dependencies
echo "📦 Installing Foundry dependencies..."
forge install openzeppelin/openzeppelin-contracts --no-commit
forge install Uniswap/v4-core --no-commit
forge install Uniswap/v4-periphery --no-commit
forge install openzeppelin/uniswap-hooks --no-commit || echo "⚠️  uniswap-hooks may need manual installation"
forge install eigenlayer/eigenlayer-contracts --no-commit || echo "⚠️  eigenlayer-contracts may need manual installation"
forge install eigenlayer/eigenlayer-middleware --no-commit || echo "⚠️  eigenlayer-middleware may need manual installation"
# Note: Using Chainlink instead of Pyth for price feeds
# forge install pyth-network/pyth-sdk-solidity --no-commit || echo "⚠️  pyth-sdk-solidity may need manual installation"
forge install SuccinctLabs/sp1-contracts --no-commit || echo "⚠️  sp1-contracts may need manual installation"

echo "✅ Foundry dependencies installed"

# Install Node.js dependencies
if [ -f "package.json" ]; then
    echo "📦 Installing Node.js dependencies..."
    npm install
    echo "✅ Node.js dependencies installed"
else
    echo "⚠️  package.json not found, skipping npm install"
fi

# Build contracts to generate ABIs
echo "🔨 Building contracts..."
forge build

# Create abis directory if it doesn't exist
mkdir -p abis

# Copy ABIs to abis directory
echo "📋 Copying ABIs to abis/ directory..."
if [ -d "contracts/out" ]; then
    find contracts/out -name "*.json" -path "*/PerpDarkPoolHook.sol/*" -exec cp {} abis/PerpDarkPoolHook.json \;
    find contracts/out -name "*.json" -path "*/OrderServiceManager.sol/*" -exec cp {} abis/OrderServiceManager.json \;
    find contracts/out -name "*.json" -path "*/MarginAccount.sol/*" -exec cp {} abis/MarginAccount.json \;
    find contracts/out -name "*.json" -path "*/PositionManager.sol/*" -exec cp {} abis/PositionManager.json \;
    echo "✅ ABIs copied"
else
    echo "⚠️  Contracts not built yet. Run 'forge build' first."
fi

echo ""
echo "✨ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Configure .env file with your addresses"
echo "2. Run 'forge test' to run tests"
echo "3. Deploy contracts using scripts in scripts/ directory"

