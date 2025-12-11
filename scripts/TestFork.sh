#!/bin/bash

# Test script for mainnet fork testing
# Uses the provided Alchemy mainnet RPC URL

set -e

echo "🧪 Running tests on mainnet fork..."
echo ""

# Set the RPC URL
export MAINNET_RPC_URL="https://eth-mainnet.g.alchemy.com/v2/LF_kKjuhP-n6jWcg9o94UWKNtoCf"

# Run fork tests
echo "Running ForkTest..."
forge test --match-contract ForkTest -vvv --fork-url "$MAINNET_RPC_URL"

echo ""
echo "✅ Fork tests completed!"

