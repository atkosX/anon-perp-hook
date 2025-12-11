#!/bin/bash

# Run all tests

set -e

echo "🧪 Running all tests..."

echo ""
echo "📦 Building contracts..."
forge build

echo ""
echo "🔍 Running Solidity tests..."
forge test -vvv

echo ""
echo "✅ All tests complete!"

