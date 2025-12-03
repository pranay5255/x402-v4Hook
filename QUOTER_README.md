# Dynamic Pricing Hook (Quoter Integration)

This component demonstrates how the **Uniswap V4 Hook** functionality is used to drive dynamic pricing for the x402 AI inference service.

## Role in x402 Architecture

In the x402 architecture, the "Quoter" or "Hook" isn't just for swapping tokens. It serves a dual purpose:

1.  **Market Observer**: It listens to swap activity on a specific Uniswap V4 pool (e.g., USDC / $Atrium).
2.  **Price Setter**: Based on market signals (volatility, tick changes, volume), it updates the `PricingParams` used to charge for AI inference.

## How It Works

### 1. Hook Interface
The contract implements `afterSwap` (and potentially `beforeSwap`) from the Uniswap V4 Hook interface.

```solidity
function afterSwap(
    address sender,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    BalanceDelta delta,
    bytes calldata hookData
) external override returns (bytes4) {
    // Logic to update inference pricing
    updatePricingParams(key);
    return BaseHook.afterSwap.selector;
}
```

### 2. Pricing Logic
When a swap occurs, the hook calculates new pricing parameters. For example:

*   **High Volatility**: If the price moves significantly, increase the `pricePerInputToken` or `surgeFactor` to reflect higher demand or risk.
*   **Stable Market**: Revert to base pricing.

### 3. Settlement Consumption
The `PricingParams` updated by this hook are read by the `settleRequest` function in the main `x402-Hook` contract when a user's AI inference request is finalized.

## Integration

This module is part of the larger x402 system. See [Implementation_plan.md](./Implementation_plan.md) for the full context.
