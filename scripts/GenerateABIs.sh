#!/bin/bash

# Generate ABIs for all contracts
# This script extracts ABIs from forge build output to the abis/ directory

set -e

echo "🔨 Building contracts..."
forge build

echo "📦 Creating abis directory..."
mkdir -p abis

echo "📋 Extracting ABIs from build artifacts..."

# Function to extract ABI from a JSON artifact file
extract_abi() {
    local artifact_file=$1
    local contract_name=$2
    
    if [ -f "$artifact_file" ]; then
        # Extract just the "abi" field from the artifact
        jq '.abi' "$artifact_file" > "abis/${contract_name}.json" 2>/dev/null || {
            echo "⚠️  Warning: Could not extract ABI from $artifact_file (jq may not be installed)"
            # Fallback: copy entire file if jq not available
            cp "$artifact_file" "abis/${contract_name}.json" 2>/dev/null || true
        }
    fi
}

# Find and extract ABIs for key contracts
echo "Extracting key contract ABIs..."

# Core contracts
for contract in PerpDarkPoolHook MarginAccount PositionManager PositionFactory PositionNFT MarketManager FundingOracle; do
    artifact=$(find contracts/out -name "${contract}.sol" -type d | head -1)
    if [ -n "$artifact" ]; then
        json_file=$(find "$artifact" -name "*.json" | head -1)
        if [ -n "$json_file" ]; then
            extract_abi "$json_file" "$contract"
            echo "  ✓ $contract"
        fi
    fi
done

# AVS contracts
for contract in OrderServiceManager ZkVerifyBridge; do
    artifact=$(find avs/out -name "${contract}.sol" -type d 2>/dev/null | head -1)
    if [ -n "$artifact" ]; then
        json_file=$(find "$artifact" -name "*.json" 2>/dev/null | head -1)
        if [ -n "$json_file" ]; then
            extract_abi "$json_file" "$contract"
            echo "  ✓ $contract"
        fi
    fi
done

# Also try to extract from any JSON files directly
echo "Scanning for additional ABIs..."
find contracts/out -name "*.json" -type f | while read -r file; do
    # Try to extract contract name from path
    contract_name=$(basename "$(dirname "$file")" | sed 's/\.sol$//')
    if [ -n "$contract_name" ] && [ ! -f "abis/${contract_name}.json" ]; then
        extract_abi "$file" "$contract_name"
    fi
done

echo ""
echo "✅ ABIs generated in abis/ directory"
echo ""
echo "Generated ABIs:"
ls -1 abis/*.json 2>/dev/null | wc -l | xargs echo "Total files:"
ls -1 abis/*.json 2>/dev/null | sed 's|abis/||' | sed 's|\.json||' || echo "No ABIs found"
