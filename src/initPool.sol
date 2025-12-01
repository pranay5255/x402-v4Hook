// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";

/// @title Uniswap V4 Pool Initializer
/// @notice Contract for initializing Uniswap V4 pools with proper price and liquidity
contract InitPool {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    IPoolManager public immutable poolManager;

    /// @notice Emitted when a pool is successfully initialized
    event PoolInitialized(PoolId indexed poolId, int24 tick, uint160 sqrtPriceX96);

    /// @param _poolManager The Uniswap V4 PoolManager contract address
    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @notice Initializes a pool with the given parameters
    /// @param key The pool key containing token addresses, fee, tick spacing, and hooks
    /// @param sqrtPriceX96 The initial square root price in Q64.96 format
    /// @param tick The initial tick for the pool
    /// @return poolId The ID of the initialized pool
    function initPool(
        PoolKey memory key,
        uint160 sqrtPriceX96,
        int24 tick
    ) external returns (PoolId poolId) {
        // Validate inputs
        require(key.currency0 < key.currency1, "InitPool: currencies must be sorted");
        require(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO && sqrtPriceX96 <= TickMath.MAX_SQRT_RATIO, "InitPool: invalid sqrt price");
        require(tick >= TickMath.MIN_TICK && tick <= TickMath.MAX_TICK, "InitPool: invalid tick");

        // Initialize the pool
        poolId = key.toId();
        poolManager.initialize(key, sqrtPriceX96, abi.encode(tick));

        emit PoolInitialized(poolId, tick, sqrtPriceX96);

        return poolId;
    }

    /// @notice Helper function to create a pool key
    /// @param currency0 The first currency (must be less than currency1)
    /// @param currency1 The second currency (must be greater than currency0)
    /// @param fee The pool fee in basis points
    /// @param tickSpacing The tick spacing for the pool
    /// @param hooks The hooks contract address (address(0) for no hooks)
    /// @return key The constructed pool key
    function createPoolKey(
        Currency currency0,
        Currency currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks
    ) external pure returns (PoolKey memory key) {
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: hooks
        });
    }

    /// @notice Calculates sqrt price from tick using TickMath
    /// @param tick The tick value representing the price level
    /// @return sqrtPriceX96 The square root price in Q64.96 format
    function calculateSqrtPriceFromTick(int24 tick) external pure returns (uint160 sqrtPriceX96) {
        return TickMath.getSqrtRatioAtTick(tick);
    }

    /// @notice Gets the current tick for a given sqrt price
    /// @param sqrtPriceX96 The square root price in Q64.96 format
    /// @return tick The corresponding tick
    function getTickAtSqrtRatio(uint160 sqrtPriceX96) external pure returns (int24 tick) {
        return TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }
}
