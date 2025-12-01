// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {SwapMath} from "v4-core/libraries/SwapMath.sol";
import {FixedPoint96} from "v4-core/libraries/FixedPoint96.sol";
import {LiquidityMath} from "v4-core/libraries/LiquidityMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import "./hookBase.sol";

/// @title Uniswap V4 Quoter
/// @notice Contract for estimating swap amounts without executing the swap
contract Quoter {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using LPFeeLibrary for uint24;

    IPoolManager public immutable poolManager;
    HookBase public immutable hookBase;

    /// @notice Emitted when a quote is provided
    event QuoteProvided(
        PoolId indexed poolId,
        bool zeroForOne,
        int256 amountSpecified,
        uint256 amountIn,
        uint256 amountOut,
        uint160 sqrtPriceX96After,
        int24 tickAfter,
        uint256 priceImpact
    );

    /// @notice Structure to hold quote results
    struct QuoteResult {
        uint256 amountIn;
        uint256 amountOut;
        uint160 sqrtPriceX96After;
        int24 tickAfter;
        uint256 priceImpact;
    }

    /// @param _poolManager The Uniswap V4 PoolManager contract address
    /// @param _hookBase The base hook contract for getting pool state
    constructor(IPoolManager _poolManager, HookBase _hookBase) {
        poolManager = _poolManager;
        hookBase = _hookBase;
    }

    /// @notice Quote a swap from token0 to token1
    /// @param key The pool key
    /// @param amountIn The amount of input token
    /// @param zeroForOne Direction of swap (true for token0 to token1)
    /// @return result The quote result containing amounts and price impact
    function quoteExactInputSingle(
        PoolKey calldata key,
        uint256 amountIn,
        bool zeroForOne
    ) external view returns (QuoteResult memory result) {
        require(amountIn > 0, "Quoter: amountIn must be greater than 0");
        
        // Get current pool state
        (uint160 sqrtPriceX96, int24 tick,,,,,) = poolManager.getSlot0(key.toId());
        
        // Calculate the swap
        result = _calculateSwap(key, amountIn, zeroForOne, sqrtPriceX96, tick);
        
        emit QuoteProvided(
            key.toId(),
            zeroForOne,
            int256(amountIn),
            result.amountIn,
            result.amountOut,
            result.sqrtPriceX96After,
            result.tickAfter,
            result.priceImpact
        );
        
        return result;
    }

    /// @notice Quote a swap from token1 to token0
    /// @param key The pool key
    /// @param amountIn The amount of input token
    /// @return result The quote result containing amounts and price impact
    function quoteExactInputSingle_Token1ToToken0(
        PoolKey calldata key,
        uint256 amountIn
    ) external view returns (QuoteResult memory result) {
        return quoteExactInputSingle(key, amountIn, false);
    }

    /// @notice Quote a swap with slippage tolerance
    /// @param key The pool key
    /// @param amountIn The amount of input token
    /// @param zeroForOne Direction of swap
    /// @param slippageBps Maximum slippage in basis points (e.g., 50 = 0.5%)
    /// @return result The quote result
    function quoteExactInputSingleWithSlippage(
        PoolKey calldata key,
        uint256 amountIn,
        bool zeroForOne,
        uint16 slippageBps
    ) external view returns (QuoteResult memory result) {
        result = quoteExactInputSingle(key, amountIn, zeroForOne);
        
        // Check if slippage is within tolerance
        require(result.priceImpact <= slippageBps, "Quoter: slippage too high");
        
        return result;
    }

    /// @notice Get multiple quotes for different amounts
    /// @param key The pool key
    /// @param amounts Array of input amounts to quote
    /// @param zeroForOne Direction of swap
    /// @return results Array of quote results
    function quoteBatch(
        PoolKey calldata key,
        uint256[] calldata amounts,
        bool zeroForOne
    ) external view returns (QuoteResult[] memory results) {
        results = new QuoteResult[](amounts.length);
        
        for (uint256 i = 0; i < amounts.length; i++) {
            results[i] = quoteExactInputSingle(key, amounts[i], zeroForOne);
        }
        
        return results;
    }

    /// @notice Get current pool price information
    /// @param key The pool key
    /// @return sqrtPriceX96 Current square root price
    /// @return tick Current tick
    /// @return fee Current fee
    /// @return tickSpacing Current tick spacing
    function getPoolInfo(PoolKey calldata key) external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint24 fee,
        int24 tickSpacing
    ) {
        (sqrtPriceX96, tick,,,,,) = poolManager.getSlot0(key.toId());
        fee = key.fee;
        tickSpacing = key.tickSpacing;
    }

    /// @notice Calculate price impact for a given swap
    /// @param key The pool key
    /// @param amountIn The input amount
    /// @param zeroForOne Direction of swap
    /// @return priceImpactBps Price impact in basis points
    function calculatePriceImpact(
        PoolKey calldata key,
        uint256 amountIn,
        bool zeroForOne
    ) external view returns (uint256 priceImpactBps) {
        // Get current pool state
        (uint160 sqrtPriceX96Before,,,) = getPoolInfo(key);
        
        // Calculate quote
        QuoteResult memory result = quoteExactInputSingle(key, amountIn, zeroForOne);
        
        // Calculate price impact
        if (zeroForOne) {
            // token0 to token1
            priceImpactBps = _calculatePriceImpact(
                sqrtPriceX96Before,
                result.sqrtPriceX96After,
                true
            );
        } else {
            // token1 to token0
            priceImpactBps = _calculatePriceImpact(
                sqrtPriceX96Before,
                result.sqrtPriceX96After,
                false
            );
        }
        
        return priceImpactBps;
    }

    /// @notice Internal function to calculate swap amounts
    function _calculateSwap(
        PoolKey calldata key,
        uint256 amountIn,
        bool zeroForOne,
        uint160 sqrtPriceX96Current,
        int24 tickCurrent
    ) internal pure returns (QuoteResult memory result) {
        // This is a simplified calculation
        // In a real implementation, you would simulate the actual swap process
        
        uint256 fee = key.fee;
        uint256 amountInAfterFee = (amountIn * (1e6 - fee)) / 1e6;
        
        // Get the price change for the given amount
        uint160 sqrtPriceX96After = _calculateNewPrice(
            sqrtPriceX96Current,
            amountInAfterFee,
            zeroForOne,
            key.tickSpacing
        );
        
        // Calculate output amount (simplified)
        result.amountIn = amountIn;
        result.amountOut = _calculateOutputAmount(
            amountInAfterFee,
            sqrtPriceX96Current,
            sqrtPriceX96After
        );
        result.sqrtPriceX96After = sqrtPriceX96After;
        result.tickAfter = TickMath.getTickAtSqrtRatio(sqrtPriceX96After);
        result.priceImpact = _calculatePriceImpact(sqrtPriceX96Current, sqrtPriceX96After, zeroForOne);
        
        return result;
    }

    /// @notice Calculate new price after a swap
    function _calculateNewPrice(
        uint160 sqrtPriceX96,
        uint256 amount,
        bool zeroForOne,
        int24 tickSpacing
    ) internal pure returns (uint160 newSqrtPriceX96) {
        if (zeroForOne) {
            // Moving up in price (token0 to token1)
            // Price increases, so sqrtPrice increases
            newSqrtPriceX96 = sqrtPriceX96 + uint160((amount * FixedPoint96.Q96) / sqrtPriceX96);
        } else {
            // Moving down in price (token1 to token0)
            // Price decreases, so sqrtPrice decreases
            newSqrtPriceX96 = sqrtPriceX96 > uint160((amount * FixedPoint96.Q96) / sqrtPriceX96)
                ? sqrtPriceX96 - uint160((amount * FixedPoint96.Q96) / sqrtPriceX96)
                : sqrtPriceX96 / 2;
        }
        
        // Ensure price is within valid bounds
        if (newSqrtPriceX96 < TickMath.MIN_SQRT_RATIO) {
            newSqrtPriceX96 = TickMath.MIN_SQRT_RATIO;
        } else if (newSqrtPriceX96 > TickMath.MAX_SQRT_RATIO) {
            newSqrtPriceX96 = TickMath.MAX_SQRT_RATIO;
        }
        
        return newSqrtPriceX96;
    }

    /// @notice Calculate output amount from input
    function _calculateOutputAmount(
        uint256 amountIn,
        uint160 sqrtPriceX96Before,
        uint160 sqrtPriceX96After
    ) internal pure returns (uint256 amountOut) {
        // Simplified output calculation
        // In reality, this would use proper AMM mathematics
        uint256 priceRatio = (sqrtPriceX96After * 1e18) / sqrtPriceX96Before;
        amountOut = (amountIn * priceRatio) / 1e18;
        return amountOut;
    }

    /// @notice Calculate price impact in basis points
    function _calculatePriceImpact(
        uint160 sqrtPriceX96Before,
        uint160 sqrtPriceX96After,
        bool zeroForOne
    ) internal pure returns (uint256 priceImpactBps) {
        uint256 priceBefore = uint256(sqrtPriceX96Before) * uint256(sqrtPriceX96Before);
        uint256 priceAfter = uint256(sqrtPriceX96After) * uint256(sqrtPriceX96After);
        
        if (zeroForOne) {
            // For token0 to token1, price impact is positive (price increases)
            priceImpactBps = priceAfter > priceBefore
                ? ((priceAfter - priceBefore) * 10000) / priceBefore
                : 0;
        } else {
            // For token1 to token0, price impact is positive (price decreases)
            priceImpactBps = priceBefore > priceAfter
                ? ((priceBefore - priceAfter) * 10000) / priceBefore
                : 0;
        }
        
        return priceImpactBps;
    }

    /// @notice Validate pool key and return pool info
    /// @param key The pool key to validate
    /// @return isValid True if pool is valid
    /// @return errorMessage Error message if invalid
    function validatePool(PoolKey calldata key) external view returns (bool isValid, string memory errorMessage) {
        require(address(key.currency0) != address(0), "Quoter: currency0 cannot be zero address");
        require(address(key.currency1) != address(0), "Quoter: currency1 cannot be zero address");
        require(key.currency0 < key.currency1, "Quoter: currencies must be sorted");
        require(key.fee > 0 && key.fee < 1000000, "Quoter: invalid fee");
        require(key.tickSpacing > 0, "Quoter: invalid tick spacing");
        
        // Check if pool exists by trying to get slot0
        try poolManager.getSlot0(key.toId()) returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 feeProtocol,
            bool unlocked,
            uint256 protocolFee,
            uint256 coin0Reserve,
            uint256 coin1Reserve
        ) {
            if (sqrtPriceX96 == 0) {
                return (false, "Quoter: pool not initialized");
            }
            return (true, "");
        } catch {
            return (false, "Quoter: pool does not exist");
        }
    }
}