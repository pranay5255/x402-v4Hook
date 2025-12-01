// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {InitPool} from "../src/InitPool.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";

/// @title Uniswap V4 Pool Deployment Script
/// @notice Deploys and initializes a Uniswap V4 pool using the InitPool contract
/// @dev Follows Foundry deployment patterns with comprehensive logging and error handling
contract DeployPoolScript is Script {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    // Pool configuration constants
    uint24 constant FEE = 3000; // 0.3% fee
    int24 constant TICK_SPACING = 60; // Standard tick spacing for 0.3% fee tier
    uint160 constant INITIAL_SQRT_PRICE = 79228162514264337593543950336; // sqrt(1) * 2^96 ≈ 1:1 price ratio

    // Addresses - update these for your deployment
    address constant POOL_MANAGER = 0x1234567890123456789012345678901234567890; // Replace with actual PoolManager address
    address constant TOKEN_A = 0x2345678901234567890123456789012345678901; // Replace with actual token A address
    address constant TOKEN_B = 0x3456789012345678901234567890123456789012; // Replace with actual token B address
    address constant HOOKS = address(0); // No hooks for basic pool

    function setUp() public {
        // Validate addresses are set
        require(POOL_MANAGER != address(0), "DeployPoolScript: POOL_MANAGER not set");
        require(TOKEN_A != address(0), "DeployPoolScript: TOKEN_A not set");
        require(TOKEN_B != address(0), "DeployPoolScript: TOKEN_B not set");
        require(TOKEN_A != TOKEN_B, "DeployPoolScript: TOKEN_A and TOKEN_B must be different");

        console.log("=== Uniswap V4 Pool Deployment Setup ===");
        console.log("Pool Manager:", POOL_MANAGER);
        console.log("Token A:", TOKEN_A);
        console.log("Token B:", TOKEN_B);
        console.log("Hooks:", HOOKS);
        console.log("Fee:", FEE, "bps");
        console.log("Tick Spacing:", TICK_SPACING);
        console.log("Initial Sqrt Price:", INITIAL_SQRT_PRICE);
        console.log("========================================");
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("Starting pool deployment with deployer:", vm.addr(deployerPrivateKey));

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy the InitPool contract
        console.log("Deploying InitPool contract...");
        InitPool initPool = new InitPool(IPoolManager(POOL_MANAGER));
        console.log("InitPool deployed at:", address(initPool));

        // Step 2: Create currencies from token addresses
        Currency currency0 = Currency.wrap(TOKEN_A);
        Currency currency1 = Currency.wrap(TOKEN_B);

        // Ensure currencies are properly ordered (currency0 < currency1)
        if (Currency.unwrap(currency0) > Currency.unwrap(currency1)) {
            (currency0, currency1) = (currency1, currency0);
            console.log("Swapped currencies for proper ordering");
        }

        console.log("Currency 0:", Currency.unwrap(currency0));
        console.log("Currency 1:", Currency.unwrap(currency1));

        // Step 3: Create pool key
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(HOOKS)
        });

        console.log("Created pool key with fee:", key.fee, "and tick spacing:", key.tickSpacing);

        // Step 4: Calculate initial tick from sqrt price using TickMath
        // Alternative approach: start with desired tick and calculate sqrt price
        // int24 desiredTick = 0; // 1:1 price ratio
        // uint160 calculatedSqrtPrice = TickMath.getSqrtRatioAtTick(desiredTick);
        // int24 initialTick = TickMath.getTickAtSqrtRatio(INITIAL_SQRT_PRICE);

        int24 initialTick = TickMath.getTickAtSqrtRatio(INITIAL_SQRT_PRICE);
        console.log("Initial tick calculated using TickMath:", initialTick);

        // Step 5: Initialize the pool
        console.log("Initializing pool...");
        PoolId poolId = initPool.initPool(key, INITIAL_SQRT_PRICE, initialTick);
        console.log("Pool initialized with ID:", PoolId.unwrap(poolId));

        // Step 6: Verify pool initialization
        (uint160 sqrtPriceX96, int24 tick,,) = IPoolManager(POOL_MANAGER).getSlot0(poolId);
        console.log("Verified pool sqrt price:", sqrtPriceX96);
        console.log("Verified pool tick:", tick);

        require(sqrtPriceX96 == INITIAL_SQRT_PRICE, "DeployPoolScript: sqrt price mismatch");
        require(tick == initialTick, "DeployPoolScript: tick mismatch");

        vm.stopBroadcast();

        console.log("=== Pool Deployment Complete ===");
        console.log("Pool ID:", vm.toString(PoolId.unwrap(poolId)));
        console.log("InitPool Contract:", address(initPool));
        console.log("Pool Manager:", POOL_MANAGER);
        console.log("=================================");

        // Log important information for verification
        console.log("Verification Data:");
        console.log("- Pool ID:", vm.toString(PoolId.unwrap(poolId)));
        console.log("- Currency 0:", Currency.unwrap(currency0));
        console.log("- Currency 1:", Currency.unwrap(currency1));
        console.log("- Fee:", FEE);
        console.log("- Tick Spacing:", TICK_SPACING);
        console.log("- Initial Sqrt Price:", INITIAL_SQRT_PRICE);
        console.log("- Initial Tick:", initialTick);
    }

    /// @notice Helper function to calculate sqrt price from tick using TickMath
    /// @param tick The tick value representing the price level
    /// @return sqrtPriceX96 The square root price in Q64.96 format
    function calculateSqrtPriceFromTick(int24 tick) public pure returns (uint160) {
        return TickMath.getSqrtRatioAtTick(tick);
    }

    /// @notice Helper function to get tick from sqrt price using TickMath
    /// @param sqrtPriceX96 The square root price in Q64.96 format
    /// @return tick The corresponding tick value
    function getTickFromSqrtPrice(uint160 sqrtPriceX96) public pure returns (int24) {
        return TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }
}
