# Uniswap V4 Quoter Example

This project implements a comprehensive quoter system for Uniswap V4 based on the [v4-by-example quoter](https://www.v4-by-example.org/quoter). The system consists of three main components that work together to provide price quoting functionality for Uniswap V4 pools.

## Components

### 1. `src/hookBase.sol` - Base Hook Contract
- Abstract contract providing core hook functionality
- Implements all required hook interfaces for Uniswap V4
- Provides basic quote generation functionality
- Includes helper functions for price calculations and pool state queries

**Key Features:**
- Hook interface implementation (before/after swap, liquidity, donate)
- Quote generation with event emissions
- Pool price and state querying
- Permission checking for hook operations

### 2. `src/qouter.sol` - Main Quoter Contract
- Advanced quoter with comprehensive price estimation
- Multiple quoting methods (exact input, slippage tolerance, batch)
- Price impact calculations
- Pool validation and information retrieval

**Key Features:**
- `quoteExactInputSingle()` - Get quote for single swap amount
- `quoteExactInputSingleWithSlippage()` - Quote with slippage tolerance
- `quoteBatch()` - Get multiple quotes in one call
- `calculatePriceImpact()` - Calculate price impact in basis points
- `getPoolInfo()` - Get current pool state information
- `validatePool()` - Validate pool existence and parameters

### 3. `src/initPool.sol` - Pool Initialization
- Helper contract for initializing Uniswap V4 pools
- Validates pool parameters
- Provides utility functions for pool setup

**Key Features:**
- Pool initialization with validation
- Pool key creation helper
- Price and tick conversion utilities

### 4. `script/QuoterDemo.s.sol` - Demonstration Script
- Complete example showing how to use all components together
- Demonstrates pool creation, initialization, and quoting
- Shows different use cases and quoting scenarios

## Usage

### Basic Setup

```solidity
// Deploy contracts
IPoolManager poolManager = IPoolManager(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
InitPool initPool = new InitPool(poolManager);
HookBase hookBase = new ExampleHook(poolManager);
Quoter quoter = new Quoter(poolManager, hookBase);
```

### Creating and Initializing a Pool

```solidity
// Create pool key
PoolKey memory key = initPool.createPoolKey(
    currency0,  // First token (must be sorted)
    currency1,  // Second token
    3000,       // Fee (3000 = 0.3%)
    60,         // Tick spacing
    IHooks(address(0))  // Hooks contract (optional)
);

// Initialize pool
uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(0); // Neutral price
initPool.initPool(key, sqrtPriceX96, 0);
```

### Getting Price Quotes

```solidity
// Get basic quote
Quoter.QuoteResult memory result = quoter.quoteExactInputSingle(
    key,
    1 ether,      // Amount in
    true          // Token0 to Token1 direction
);

console.log("Expected output:", result.amountOut);
console.log("Price impact:", result.priceImpact, "bps");
```

### Advanced Quoting

```solidity
// Quote with slippage tolerance
Quoter.QuoteResult memory result = quoter.quoteExactInputSingleWithSlippage(
    key,
    1 ether,
    true,
    50  // 0.5% max slippage
);

// Get multiple quotes
uint256[] memory amounts = new uint256[](3);
amounts[0] = 0.1 ether;
amounts[1] = 0.5 ether;
amounts[2] = 1.0 ether;

Quoter.QuoteResult[] memory results = quoter.quoteBatch(key, amounts, true);

// Calculate price impact
uint256 priceImpact = quoter.calculatePriceImpact(key, 1 ether, true);
```

### Pool Information

```solidity
// Get current pool state
(uint160 sqrtPriceX96, int24 tick, uint24 fee, int24 tickSpacing) = 
    quoter.getPoolInfo(key);

// Validate pool
(bool isValid, string memory error) = quoter.validatePool(key);
require(isValid, error);
```

## Integration with Hooks

The quoter system integrates seamlessly with Uniswap V4 hooks:

```solidity
// Create hook implementation
contract MyCustomHook is HookBase {
    constructor(IPoolManager _poolManager) HookBase(_poolManager) {}
    
    // Custom hook logic can be added here
    function _update() internal override {
        // Your custom logic
    }
}

// Use with pool
IHooks myHook = new MyCustomHook(poolManager);
PoolKey memory key = initPool.createPoolKey(
    currency0, currency1, fee, tickSpacing, myHook
);
```

## Events

The quoter system emits several events for monitoring:

```solidity
// From HookBase
event QuoteGenerated(
    PoolId indexed poolId,
    bool zeroForOne,
    int256 amountSpecified,
    uint256 quoteAmount,
    uint256 priceImpact
);

// From Quoter
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
```

## Running the Demo

To run the demonstration script:

```bash
# Build the project
forge build

# Run the demo script
forge script script/QuoterDemo.s.sol --rpc-url <your-rpc-url>
```

The demo will:
1. Deploy all necessary contracts
2. Initialize example pools (WETH/USDC, USDC/DAI)
3. Perform various quote operations
4. Display results and analysis

## Important Considerations

1. **Token Sorting**: Uniswap V4 requires tokens to be sorted (token0 < token1)
2. **Pool Initialization**: Pools must be initialized before quoting
3. **Fee Calculation**: All calculations are estimates and don't include protocol fees
4. **Price Impact**: Real trading may experience different price impact due to slippage
5. **Hook Permissions**: Ensure hooks have appropriate permissions for the operations

## Testing

To test the implementation:

```bash
# Run tests
forge test

# Run with detailed output
forge test -vv
```

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   InitPool      │    │    HookBase      │    │     Quoter      │
│                 │    │                  │    │                 │
│ - Initialize    │    │ - Hook Interface │    │ - Quote Logic   │
│ - Create Keys   │    │ - Price Calc     │    │ - Batch Quotes  │
│ - Validate      │    │ - Pool State     │    │ - Impact Calc   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌──────────────────┐
                    │  PoolManager     │
                    │                  │
                    │ - Pool State     │
                    │ - Swap Logic     │
                    └──────────────────┘
```

## License

MIT License - see LICENSE file for details.