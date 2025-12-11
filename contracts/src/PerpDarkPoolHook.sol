//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, toBeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/console.sol";

import {MarginAccount} from "./MarginAccount.sol";
import {PositionManager} from "./PositionManager.sol";
import {FundingOracle} from "./FundingOracle.sol";

interface IOrderServiceManager {
    struct Task {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
        address sender;
        bytes32 poolId;
        uint32 taskCreatedBlock;
        uint32 taskId;
        bool isPerpOrder;
        uint256 positionId;
        uint256 marginAmount;
        uint256 leverage;
        bool isLong;
    }
    
    function createPerpTask(
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        address sender,
        bytes32 poolId,
        bool isLong,
        uint256 marginAmount,
        uint256 leverage,
        uint256 positionId
    ) external returns (Task memory task);
}

/// @title PerpDarkPoolHook - Dark pool hook for perpetual futures trading
/// @notice Handles perp orders with CoW matching and vAMM fallback
/// @dev Main Uniswap pool is no-op, all pricing via vAMM
contract PerpDarkPoolHook is BaseHook, ReentrancyGuard {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using SafeERC20 for IERC20;

    // Order type constants
    uint8 public constant ORDER_TYPE_PERP_COW = 1;      // Perp with dark pool matching
    uint8 public constant ORDER_TYPE_PERP_DIRECT = 2;   // Direct vAMM, bypass dark pool

    // Core contracts
    address public serviceManager;
    MarginAccount public immutable marginAccount;
    PositionManager public immutable positionManager;
    FundingOracle public immutable fundingOracle;
    IERC20 public immutable USDC;

    // Pool management
    mapping(bytes32 => PoolKey) public poolKeys;

    // vAMM market state
    struct MarketState {
        uint256 virtualBase;      // Virtual base reserve (e.g., ETH in wei, 18 decimals)
        uint256 virtualQuote;     // Virtual quote reserve (USDC in 6 decimals)
        uint256 k;                // Constant product K = virtualBase * virtualQuote
        uint256 totalLongOI;      // Total long open interest (in quote terms, 6 decimals)
        uint256 totalShortOI;     // Total short open interest (in quote terms, 6 decimals)
        uint256 maxOICap;         // Maximum open interest cap
        uint256 lastFundingTime;  // Last time funding was updated
        bool isActive;            // Market active status
    }

    mapping(bytes32 => MarketState) public perpMarkets;

    // Risk parameters
    uint256 public constant MAX_LEVERAGE = 20e18;              // 20x leverage (18 decimals)
    uint256 public constant MIN_MARGIN = 10e6;                 // $10 minimum margin (6 decimals)
    uint256 public constant MAX_DEVIATION_BPS = 500;           // 5% max price deviation
    uint256 public constant TRADE_FEE_BPS = 30;               // 0.3% base trade fee
    uint256 public constant FUNDING_RATE_PRECISION = 1e18;     // Funding rate precision
    uint256 public constant FUNDING_INTERVAL = 1 hours;        // Funding update interval
    uint256 public constant INITIAL_ETH_PRICE = 2000e18;       // $2000 initial ETH price

    // Perp order data structure
    struct PerpOrderData {
        bool isLong;
        uint256 marginAmount;
        uint256 leverage;  // in basis points
        uint256 maxSlippage;
        uint256 positionId;  // 0 for new positions
    }

    // CoW settlement structure
    struct PerpCoWSettlement {
        address longTrader;
        address shortTrader;
        bytes32 poolId;
        uint256 matchSize;
        uint256 matchPrice;
        uint256 longMargin;
        uint256 shortMargin;
        uint256 longLeverage;
        uint256 shortLeverage;
    }

    // Transfer balance for CoW matches
    struct TransferBalance {
        uint256 amount;
        address currency;
        address sender;
    }

    // Swap balance for vAMM fallback (not used in CoW, but kept for interface compatibility)
    struct SwapBalance {
        int256 amountSpecified;
        bool zeroForOne;
        uint160 sqrtPriceLimitX96;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event MarketInitialized(bytes32 indexed poolId, uint256 virtualBase, uint256 virtualQuote, uint256 k);
    event VirtualReservesUpdated(bytes32 indexed poolId, uint256 virtualBase, uint256 virtualQuote);
    event PerpCoWMatch(bytes32 indexed poolId, address indexed longTrader, address indexed shortTrader, uint256 matchSize, uint256 matchPrice);
    event PerpPositionOpened(bytes32 indexed poolId, address indexed trader, uint256 tokenId, bool isLong, uint256 size, uint256 margin);

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAVS() {
        require(
            msg.sender == address(serviceManager),
            "Only AVS Service Manager can call this function"
        );
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        IPoolManager _manager,
        address _serviceManager,
        MarginAccount _marginAccount,
        PositionManager _positionManager,
        FundingOracle _fundingOracle,
        IERC20 _usdc
    ) BaseHook(_manager) {
        serviceManager = _serviceManager;
        marginAccount = _marginAccount;
        positionManager = _positionManager;
        fundingOracle = _fundingOracle;
        USDC = _usdc;
    }

    /*//////////////////////////////////////////////////////////////
                          HOOK PERMISSIONS
    //////////////////////////////////////////////////////////////*/

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    /*//////////////////////////////////////////////////////////////
                          HOOK CALLBACKS
    //////////////////////////////////////////////////////////////*/

    function _afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24
    ) internal override returns (bytes4) {
        bytes32 poolId = PoolId.unwrap(key.toId());
        poolKeys[poolId] = key;
        
        // Initialize vAMM market if not already initialized
        if (perpMarkets[poolId].k == 0) {
            _initializePerpMarket(poolId);
        }
        
        return this.afterInitialize.selector;
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        bytes calldata hookData
    )
        internal
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (hookData.length == 0) {
            // No hook data - allow regular swap (though pool should be no-op for perps)
            return (this.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        bytes32 poolId = PoolId.unwrap(key.toId());
        MarketState storage market = perpMarkets[poolId];
        
        if (!market.isActive) {
            return (this.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        // Decode order type and data
        uint8 orderType = uint8(hookData[0]);
        
        if (orderType == ORDER_TYPE_PERP_COW) {
            // Perp order with dark pool matching
            return _handlePerpCowOrder(key, swapParams, hookData, poolId);
        } else if (orderType == ORDER_TYPE_PERP_DIRECT) {
            // Direct vAMM execution (bypass dark pool)
            return _handleDirectPerpOrder(key, swapParams, hookData, poolId);
        }

        // Unknown order type
        return (this.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        PERP ORDER HANDLING
    //////////////////////////////////////////////////////////////*/

    /// @notice Handle perp order with CoW matching enabled
    function _handlePerpCowOrder(
        PoolKey calldata key,
        SwapParams calldata swapParams,
        bytes calldata hookData,
        bytes32 poolId
    ) internal returns (bytes4, BeforeSwapDelta, uint24) {
        // Decode perp order data (skip first byte which is order type)
        PerpOrderData memory orderData = abi.decode(hookData[1:], (PerpOrderData));
        
        // Validate: only exact input swaps for perp orders
        require(swapParams.amountSpecified < 0, "Only exact input supported");
        
        address sender = msg.sender;
        
        // Lock margin in MarginAccount
        marginAccount.lockMargin(sender, orderData.marginAmount);
        
        // Lock input currency using ERC6909 (for settlement)
        poolManager.mint(
            address(this),
            (swapParams.zeroForOne ? key.currency0 : key.currency1).toId(),
            uint256(-swapParams.amountSpecified)
        );
        
        // Create perp task in OrderServiceManager
        IOrderServiceManager(serviceManager).createPerpTask(
            swapParams.zeroForOne,
            swapParams.amountSpecified,
            swapParams.sqrtPriceLimitX96,
            sender,
            poolId,
            orderData.isLong,
            orderData.marginAmount,
            orderData.leverage,
            orderData.positionId
        );
        
        // Return delta to prevent default swap (pool is no-op)
        return (
            this.beforeSwap.selector,
            toBeforeSwapDelta(-int128(swapParams.amountSpecified), 0),
            0
        );
    }

    /// @notice Handle direct vAMM perp order (bypass dark pool)
    function _handleDirectPerpOrder(
        PoolKey calldata key,
        SwapParams calldata swapParams,
        bytes calldata hookData,
        bytes32 poolId
    ) internal returns (bytes4, BeforeSwapDelta, uint24) {
        // Decode perp order data
        PerpOrderData memory orderData = abi.decode(hookData[1:], (PerpOrderData));
        
        // Update funding if needed
        _updateFundingIfNeeded(poolId);
        
        // Get mark price
        uint256 markPrice = _getMarkPrice(poolId);
        
        // Lock margin
        marginAccount.lockMargin(msg.sender, orderData.marginAmount);
        
        // Execute vAMM swap (cancels pool swap)
        BeforeSwapDelta delta = _executeVAMMSwap(key, swapParams, markPrice);
        
        // Update vAMM reserves and create position
        _executeOpenPosition(poolId, orderData, swapParams, markPrice);
        
        return (this.beforeSwap.selector, delta, uint24(TRADE_FEE_BPS));
    }

    /*//////////////////////////////////////////////////////////////
                        SETTLEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Settle perp CoW match
    function settlePerpBalances(
        bytes32 poolId,
        PerpCoWSettlement memory settlement
    ) external onlyAVS nonReentrant {
        // Create positions for both traders
        bytes32 marketId = poolId; // Use poolId as marketId
        
        // Create long position
        uint256 longTokenId = positionManager.openPositionFor(
            settlement.longTrader,
            marketId,
            int256(settlement.matchSize),
            settlement.matchPrice,
            settlement.longMargin
        );
        
        // Create short position
        uint256 shortTokenId = positionManager.openPositionFor(
            settlement.shortTrader,
            marketId,
            -int256(settlement.matchSize),
            settlement.matchPrice,
            settlement.shortMargin
        );
        
        // Sync vAMM reserves
        _syncVAMMForCoWMatch(poolId, settlement);
        
        // Calculate ERC6909 token amounts to burn
        PoolKey memory key = poolKeys[poolId];
        Currency inputCurrency = key.currency0; // Assuming currency0 is base asset (ETH)
        uint256 currencyId = inputCurrency.toId();
        
        // Both traders provided input (long provides base, short provides base)
        // Total to burn = matchSize (from long) + matchSize (from short) = 2 * matchSize
        // But actually, in CoW match, they offset each other
        // Long wants base, short provides base - they match directly
        // So we only need to burn the matched amount from each
        
        // Unlock callback to handle ERC6909 token burning
        poolManager.unlock(
            abi.encode(key, settlement.matchSize, currencyId)
        );
        
        emit PerpCoWMatch(
            poolId,
            settlement.longTrader,
            settlement.shortTrader,
            settlement.matchSize,
            settlement.matchPrice
        );
    }

    /// @notice Unlock callback for CoW settlement
    function unlockCallback(
        bytes calldata data
    ) external onlyPoolManager returns (bytes memory) {
        (
            PoolKey memory key,
            uint256 matchSize,
            uint256 currencyId
        ) = abi.decode(data, (PoolKey, uint256, uint256));
        
        // Burn ERC6909 tokens for the matched amount
        // In CoW match, both traders' input tokens are burned
        // Long trader provided matchSize, short trader provided matchSize
        uint256 totalToBurn = matchSize * 2;
        
        uint256 hookBalance = poolManager.balanceOf(address(this), currencyId);
        uint256 burnAmount = hookBalance < totalToBurn ? hookBalance : totalToBurn;
        
        if (burnAmount > 0) {
            poolManager.burn(address(this), currencyId, burnAmount);
        }
        
        return new bytes(0);
    }

    /*//////////////////////////////////////////////////////////////
                        VAMM FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize vAMM market
    function _initializePerpMarket(bytes32 poolId) internal {
        // Try to get price from oracle
        uint256 initialPrice = INITIAL_ETH_PRICE;
        try fundingOracle.getSpotPrice(PoolId.wrap(poolId)) returns (uint256 spotPrice) {
            if (spotPrice > 0) {
                initialPrice = spotPrice;
            }
        } catch {}
        
        uint256 virtualLiquidity = 1000000e6; // 1M USDC
        uint256 maxOICap = 10000000e6; // 10M USDC
        
        uint256 virtualQuote = virtualLiquidity; // 1M USDC (6 decimals)
        uint256 virtualBase = (virtualLiquidity * 1e30) / initialPrice; // Convert to 18 decimals
        uint256 k = virtualBase * virtualQuote;
        
        perpMarkets[poolId] = MarketState({
            virtualBase: virtualBase,
            virtualQuote: virtualQuote,
            k: k,
            totalLongOI: 0,
            totalShortOI: 0,
            maxOICap: maxOICap,
            lastFundingTime: block.timestamp,
            isActive: true
        });
        
        emit MarketInitialized(poolId, virtualBase, virtualQuote, k);
    }

    /// @notice Sync vAMM reserves after CoW match
    function _syncVAMMForCoWMatch(
        bytes32 poolId,
        PerpCoWSettlement memory settlement
    ) internal {
        MarketState storage market = perpMarkets[poolId];
        
        // Calculate quote delta (in 18 decimals, convert to 6 for USDC)
        uint256 quoteDelta = (settlement.matchSize * settlement.matchPrice) / 1e18;
        uint256 quoteDelta6 = quoteDelta / 1e12; // Convert to 6 decimals
        
        // Update virtual reserves (maintain K)
        // Long: wants base (ETH), pays quote (USDC)
        // Short: wants quote (USDC), pays base (ETH)
        // Net: both positions created, OI increases
        
        market.virtualBase += settlement.matchSize;
        market.virtualQuote = market.k / market.virtualBase;
        
        // Update OI (both long and short increase)
        market.totalLongOI += quoteDelta6;
        market.totalShortOI += quoteDelta6;
        
        emit VirtualReservesUpdated(poolId, market.virtualBase, market.virtualQuote);
    }

    /// @notice Execute vAMM swap (for direct orders)
    function _executeVAMMSwap(
        PoolKey calldata key,
        SwapParams calldata params,
        uint256 markPrice
    ) internal returns (BeforeSwapDelta) {
        bool exactInput = params.amountSpecified < 0;
        bool zeroForOne = params.zeroForOne;
        
        (Currency inputCurrency, Currency outputCurrency) = zeroForOne 
            ? (key.currency0, key.currency1)
            : (key.currency1, key.currency0);
        
        if (exactInput) {
            uint256 inputAmount = uint256(-params.amountSpecified);
            uint256 outputAmount;
            
            if (zeroForOne) {
                outputAmount = (inputAmount * markPrice) / 1e30;
            } else {
                outputAmount = (inputAmount * 1e30) / markPrice;
            }
            
            // Take input currency
            poolManager.take(inputCurrency, address(this), inputAmount);
            
            // Settle output currency
            _settleCurrency(outputCurrency, outputAmount);
            
            return toBeforeSwapDelta(int128(-params.amountSpecified), int128(int256(outputAmount)));
        } else {
            uint256 outputAmount = uint256(params.amountSpecified);
            uint256 inputAmount;
            
            if (zeroForOne) {
                inputAmount = (outputAmount * 1e30) / markPrice;
            } else {
                inputAmount = (outputAmount * markPrice) / 1e30;
            }
            
            poolManager.take(inputCurrency, address(this), inputAmount);
            _settleCurrency(outputCurrency, outputAmount);
            
            return toBeforeSwapDelta(-int128(int256(inputAmount)), int128(params.amountSpecified));
        }
    }

    /// @notice Settle currency to PoolManager
    function _settleCurrency(Currency currency, uint256 amount) internal {
        if (amount == 0) return;
        
        if (currency.isAddressZero()) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(currency);
            IERC20(Currency.unwrap(currency)).safeTransfer(address(poolManager), amount);
            poolManager.settle();
        }
    }

    /// @notice Execute open position (for direct vAMM orders)
    function _executeOpenPosition(
        bytes32 poolId,
        PerpOrderData memory orderData,
        SwapParams calldata params,
        uint256 entryPrice
    ) internal {
        MarketState storage market = perpMarkets[poolId];
        bool isLong = orderData.isLong;
        
        // Update virtual reserves
        uint256 size = uint256(-params.amountSpecified);
        if (isLong) {
            uint256 quoteIn = (size * entryPrice) / 1e18;
            market.virtualQuote += quoteIn;
            market.virtualBase = market.k / market.virtualQuote;
            market.totalLongOI += quoteIn / 1e12;
        } else {
            market.virtualBase += size;
            market.virtualQuote = market.k / market.virtualBase;
            uint256 shortNotional = (size * entryPrice) / 1e18;
            market.totalShortOI += shortNotional / 1e12;
        }
        
        // Create position
        bytes32 marketId = poolId;
        uint256 tokenId = positionManager.openPositionFor(
            msg.sender,
            marketId,
            isLong ? int256(size) : -int256(size),
            entryPrice,
            orderData.marginAmount
        );
        
        emit PerpPositionOpened(poolId, msg.sender, tokenId, isLong, size, orderData.marginAmount);
        emit VirtualReservesUpdated(poolId, market.virtualBase, market.virtualQuote);
    }

    /// @notice Get mark price for a pool
    function _getMarkPrice(bytes32 poolId) internal view returns (uint256) {
        MarketState storage market = perpMarkets[poolId];
        
        if (market.virtualBase == 0) {
            return INITIAL_ETH_PRICE;
        }
        
        uint256 vammPrice = (market.virtualQuote * 1e30) / market.virtualBase;
        
        try fundingOracle.getSpotPrice(PoolId.wrap(poolId)) returns (uint256 spotPrice) {
            if (spotPrice > 0) {
                return (vammPrice + spotPrice) / 2; // Mean price
            }
        } catch {}
        
        return vammPrice;
    }

    /// @notice Update funding if needed
    function _updateFundingIfNeeded(bytes32 poolId) internal {
        MarketState storage market = perpMarkets[poolId];
        if (block.timestamp >= market.lastFundingTime + FUNDING_INTERVAL) {
            market.lastFundingTime = block.timestamp;
            // Funding updates handled by FundingOracle
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getMarkPrice(bytes32 poolId) external view returns (uint256) {
        return _getMarkPrice(poolId);
    }

    function getMarketState(bytes32 poolId) external view returns (MarketState memory) {
        return perpMarkets[poolId];
    }

    receive() external payable {}
}

