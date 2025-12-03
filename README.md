# x402-v4Hook Project

This project implements a hybrid AI/Blockchain system that gates AI inference resources using **Uniswap V4 Hooks** and **EIP-3009 Gas-Abstracted Deposits**.

## Core Concept

The system allows users to pay for AI inference (LLM calls) using on-chain assets (USDC/ETH) without holding native gas tokens (ETH) or managing complex transaction flows. It uses a "Deposit -> Infer -> Settle & Refund" model.

### Key Features

1.  **Gasless User Experience**: Users sign **EIP-3009** authorizations. The x402 Facilitator pays the gas and is reimbursed economically from the user's deposit.
2.  **Pay-Per-Token**: Users deposit a maximum budget, but are only charged for the exact `input_tokens` and `output_tokens` consumed by the LLM. The difference is refunded instantly.
3.  **Dynamic Pricing**: The pricing for inference is not static. It is updated dynamically by a **Uniswap V4 Hook** that monitors on-chain market conditions (volatility, demand) to adjust the price-per-token.
4.  **Trust Minimized**: While the inference is off-chain, the settlement logic, pricing parameters, and refunds are strictly enforced by the smart contract.

## Architecture Overview

*   **Hook Contract**: Acts as both the settlement engine and a Uniswap V4 Hook. It holds user funds, calculates costs, and distributes payments.
*   **x402 Server**: The off-chain facilitator that validates requests, calls the LLM provider (OpenRouter), and submits on-chain settlement transactions.
*   **Uniswap V4 Pool**: Provides the market signal (e.g., USDC/UtilityToken pool) that drives the dynamic pricing logic.

## Project Structure

*   `src/`: Solidity smart contracts.
    *   `Hook.sol`: The main contract implementing `settleRequest` and Uniswap hooks.
*   `test/`: Foundry tests.
*   `script/`: Deployment scripts.

## Getting Started

### Prerequisites

*   [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Build & Test

```shell
$ forge build
$ forge test
```

## Documentation

See [Implementation_plan.md](./Implementation_plan.md) for a detailed architectural breakdown and sequence diagrams.
