// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title MarketManager - Enhanced market management with key manager pattern
/// @notice Manages trading markets with multi-user access control via key managers
contract MarketManager is Ownable, ReentrancyGuard {

    struct Market {
        address baseAsset;
        address quoteAsset;
        address poolAddress;
        uint64 lastFundingUpdate;
        bool isActive;
        uint256 fundingIndex; // Scaled by 1e18
    }

    // Storage
    mapping(bytes32 => Market) public markets;
    mapping(bytes32 => uint256[]) public marketPositions;
    mapping(address => bool) public keyManagers;
    bytes32[] public marketIds;
    
    event MarketAdded(bytes32 indexed marketId, address baseAsset, address quoteAsset, address poolAddress);
    event MarketStatusUpdated(bytes32 indexed marketId, bool isActive);
    event FundingIndexUpdated(bytes32 indexed marketId, uint256 newIndex);
    event KeyManagerAdded(address indexed keyManager);
    event KeyManagerRemoved(address indexed keyManager);

    modifier onlyKeyManager() {
        require(keyManagers[msg.sender] || msg.sender == owner(), "Not authorized: must be key manager or owner");
        _;
    }

    constructor() Ownable(msg.sender) {
        // Owner is automatically a key manager
        keyManagers[msg.sender] = true;
        emit KeyManagerAdded(msg.sender);
    }

    /// @notice Add a new key manager (only owner can do this)
    function addKeyManager(address keyManager) external onlyOwner {
        require(keyManager != address(0), "Invalid key manager address");
        require(!keyManagers[keyManager], "Already a key manager");
        keyManagers[keyManager] = true;
        emit KeyManagerAdded(keyManager);
    }

    /// @notice Remove a key manager (only owner can do this)
    function removeKeyManager(address keyManager) external onlyOwner {
        require(keyManager != owner(), "Cannot remove owner as key manager");
        require(keyManagers[keyManager], "Not a key manager");
        keyManagers[keyManager] = false;
        emit KeyManagerRemoved(keyManager);
    }

    /// @notice Add a new trading market (key managers can do this)
    function addMarket(
        bytes32 marketId,
        address baseAsset,
        address quoteAsset,
        address poolAddress
    ) external onlyKeyManager {
        require(baseAsset != address(0), "Invalid base asset");
        require(quoteAsset != address(0), "Invalid quote asset");
        require(poolAddress != address(0), "Invalid pool address");
        require(markets[marketId].baseAsset == address(0), "Market already exists");

        markets[marketId] = Market({
            baseAsset: baseAsset,
            quoteAsset: quoteAsset,
            poolAddress: poolAddress,
            lastFundingUpdate: uint64(block.timestamp),
            isActive: true,
            fundingIndex: 1e18
        });

        marketIds.push(marketId);
        emit MarketAdded(marketId, baseAsset, quoteAsset, poolAddress);
    }

    /// @notice Update market status
    function updateMarketStatus(bytes32 marketId, bool isActive) external onlyKeyManager {
        require(markets[marketId].baseAsset != address(0), "Market does not exist");
        markets[marketId].isActive = isActive;
        emit MarketStatusUpdated(marketId, isActive);
    }

    /// @notice Set market status (key managers can do this)
    function setMarketStatus(bytes32 marketId, bool isActive) external onlyKeyManager {
        require(markets[marketId].baseAsset != address(0), "Market does not exist");
        markets[marketId].isActive = isActive;
        emit MarketStatusUpdated(marketId, isActive);
    }

    /// @notice Update funding index for a market (key managers can do this)
    function updateFundingIndex(bytes32 marketId, uint256 newIndex) external onlyKeyManager {
        require(markets[marketId].baseAsset != address(0), "Market does not exist");
        require(newIndex > 0, "Invalid funding index");
        markets[marketId].fundingIndex = newIndex;
        markets[marketId].lastFundingUpdate = uint64(block.timestamp);
        emit FundingIndexUpdated(marketId, newIndex);
    }

    /// @notice Get market details
    function getMarket(bytes32 marketId) external view returns (Market memory) {
        return markets[marketId];
    }

    /// @notice Check if market exists and is active
    function isMarketActive(bytes32 marketId) external view returns (bool) {
        return markets[marketId].baseAsset != address(0) && markets[marketId].isActive;
    }

    /// @notice Get current funding index for a market
    function getFundingIndex(bytes32 marketId) external view returns (uint256) {
        return markets[marketId].fundingIndex;
    }

    /// @notice Add position to market tracking
    function addPositionToMarket(bytes32 marketId, uint256 tokenId) external {
        // This would be called by the factory
        marketPositions[marketId].push(tokenId);
    }

    /// @notice Remove position from market tracking
    function removePositionFromMarket(bytes32 marketId, uint256 tokenId) external {
        uint256[] storage positions = marketPositions[marketId];
        for (uint256 i = 0; i < positions.length; i++) {
            if (positions[i] == tokenId) {
                positions[i] = positions[positions.length - 1];
                positions.pop();
                break;
            }
        }
    }

    /// @notice Get all positions in a market
    function getMarketPositions(bytes32 marketId) external view returns (uint256[] memory) {
        return marketPositions[marketId];
    }

    /// @notice Get all market IDs
    function getAllMarketIds() external view returns (bytes32[] memory) {
        return marketIds;
    }

    /// @notice Get number of markets
    function getMarketCount() external view returns (uint256) {
        return marketIds.length;
    }

    /// @notice Check if an address is a key manager
    function isKeyManager(address account) external view returns (bool) {
        return keyManagers[account];
    }

    /// @notice Get last funding update timestamp for a market
    function getLastFundingUpdate(bytes32 marketId) external view returns (uint64) {
        return markets[marketId].lastFundingUpdate;
    }

    /// @notice Emergency function to pause all markets (only owner)
    function pauseAllMarkets() external onlyOwner {
        for (uint256 i = 0; i < marketIds.length; i++) {
            if (markets[marketIds[i]].isActive) {
                markets[marketIds[i]].isActive = false;
                emit MarketStatusUpdated(marketIds[i], false);
            }
        }
    }

    /// @notice Emergency function to resume all markets (only owner)
    function resumeAllMarkets() external onlyOwner {
        for (uint256 i = 0; i < marketIds.length; i++) {
            if (!markets[marketIds[i]].isActive) {
                markets[marketIds[i]].isActive = true;
                emit MarketStatusUpdated(marketIds[i], true);
            }
        }
    }
}

