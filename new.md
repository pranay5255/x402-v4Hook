You’re right to be cautious here—there *are* a few conceptual traps. Let’s untangle them slowly and make the roles of:

* **hook contract**
* **EIP-3009**
* **x402 resource server**
* **dynamic pricing based on LLM tokens**

very clear.

I’ll walk through this in **4 steps**, directly addressing your 3 concerns.

---

## Step 1 – Ground truth constraints (what *must* be true on Ethereum)

First, some non-negotiables:

1. **Only EOAs (or 4337-style bundlers) pay gas.**
   A contract (your hook) can *hold* ETH/USDC, but it cannot spontaneously pay gas for a transaction. The gas is always fronted by the caller (facilitator/x402 server), and then the caller can be **reimbursed** from the contract.

   So when you say:

   > “funds for sponsoring gas must be in the hook contract”

   that really means:

   * The hook holds a **pot of ERC-20 or ETH** that *economically* funds gas.
   * The x402 server still pays gas at call time, then **collects** its gas subsidy from the hook (either as a fixed fee or as part of `protocolFee`).

2. **EIP-3009 lives on the token contract, not the hook.**

   * The functions `transferWithAuthorization` / `receiveWithAuthorization` are implemented by the token (e.g. USDC).
   * Your hook/settlement contract is just the **recipient** (`to`) of those transfers (or a participant if you wrap them).

3. **The number of LLM tokens used is inherently off-chain.**

   * OpenRouter tells you `input_tokens`, `output_tokens` *after* inference.
   * There is no native way for the hook to verify this itself; it must **trust** the server or use some extra attestation system.
   * So the hook contract will **accept some “tokensUsed” numbers as input** from the facilitator and enforce accounting/refunds around that.

Given these constraints, your architecture must look like:

* User **pre-funds** a max amount (via EIP-3009 → hook).
* Server runs inference, gets real token usage.
* Server calls hook’s `settle` with `tokensUsed` and pricing variables.
* Hook **charges** based on pricing rule + `tokensUsed`, and refunds the rest.

That already satisfies your 3 bullets, now we need to place dynamic pricing in a sensible place.

---

## Step 2 – Clean separation of concerns

Let’s separate **three layers**:

1. **Funding layer (EIP-3009 + hook balance)**
2. **Usage layer (tokens consumed by LLM)**
3. **Pricing layer (how much we charge per token + gas + margin)**

### 2.1 Funding layer – “funds for sponsoring gas must be in the hook”

Flow:

* Client signs an EIP-3009 authorization:
  `from = user`, `to = Hook`, `value = maxAmount`, `validBefore`, `nonce`, `v,r,s`.

* x402 server validates signature, then executes:

  ```solidity
  USDC.transferWithAuthorization(from, hookAddress, value, validAfter, validBefore, nonce, v, r, s);
  ```

* The hook’s **USDC balance increases by `value`**.

* Hook records:

  ```solidity
  deposits[requestId] = {
      user: from,
      token: USDC,
      amountPaid: value,
      settled: false
  };
  ```

This accomplishes:

* User **never touches gas** (thanks to EIP-3009).
* Hook contract is now literally **holding the user’s funds** which can be used to:

  * Pay for LLM cost,
  * Pay protocol fee,
  * **Economically reimburse gas** (by paying the facilitator more).

The facilitator (x402 server) still pays native gas, but recoups it from `protocolFee` or a dedicated gas fee component.

---

### 2.2 Usage layer – “hook contract must get total tokens used”

Resource server sequence:

1. API call passes `requestId` and the user’s prompt.
2. Server checks `deposits[requestId]` in the hook (view call).
3. Server calls OpenRouter → gets:

   * `input_tokens`, `output_tokens`, maybe `total_tokens`.
4. These numbers are **off-chain truth** that only the server sees directly.

To “give” this to the hook contract, there are two main options:

* **Option A – Store them on-chain**:

  ```solidity
  function settleRequest(
      bytes32 requestId,
      uint256 inputTokens,
      uint256 outputTokens
  ) external onlyFacilitator {
      // Hook computes cost using current pricing params and these counts
  }
  ```

  This means the hook itself knows the raw usage and can emit them in events.

* **Option B – Only store total cost**, but you *lose* on-chain introspectability:

  ```solidity
  function settleRequest(
      bytes32 requestId,
      uint256 totalCharge,  // includes LLM cost + gas + protocol fee
      uint256 modelCost,    // optional breakdown
      uint256 gasCost,
      uint256 protocolFee
  ) external onlyFacilitator { ... }
  ```

If you want the hook contract to **directly implement “dynamic pricing based on tokens consumed”**, you almost certainly want **Option A**: pass `inputTokens`, `outputTokens`, and let **the hook compute cost** from parameters it stores.

That addresses your point 2:

> “The hook contract must get the total number of tokens used in certain inference process done by the resource server.”

You do this by **passing them explicitly into `settle`**. There is no way around trusting the facilitator on these numbers unless you design some more complex attestation scheme.

---

### 2.3 Pricing layer – when and where to apply dynamic pricing?

This is the heart of your question.

You’re doing:

* **Ex-ante**: user sets a **max budget** `maxAmount` via EIP-3009.
* **Ex-post**: you only find **actual tokensUsed** after inference.

So the *only* sensible place to apply dynamic pricing is **in the settlement step**, after you know `tokensUsed`.

You can think of it like:

```solidity
// Stored in hook (dynamic, updated over time)
struct PricingParams {
    uint256 pricePerInputToken;   // e.g. in USDC 6 decimals
    uint256 pricePerOutputToken;
    uint256 protocolFeeBps;       // protocol fee percentage
    uint256 gasMarkupPerCall;     // optional gas compensation
    // maybe: volatilityMultiplier, surgeFactor, etc.
}
PricingParams public pricing;
```

Then in `settleRequest`:

```solidity
function settleRequest(
    bytes32 requestId,
    uint256 inputTokens,
    uint256 outputTokens
) external onlyFacilitator {
    Deposit storage d = deposits[requestId];
    require(!d.settled, "settled");
    d.settled = true;

    // 1. Compute base cost from dynamic pricing params
    uint256 baseCost =
        inputTokens * pricing.pricePerInputToken +
        outputTokens * pricing.pricePerOutputToken;

    // 2. Add gas compensation if you want contract to fund gas indirectly
    uint256 gasComp = pricing.gasMarkupPerCall;

    // 3. Add protocol fee
    uint256 fee = (baseCost * pricing.protocolFeeBps) / 10_000;

    uint256 totalCharge = baseCost + gasComp + fee;
    require(totalCharge <= d.amountPaid, "underfunded"); // deposit too small

    uint256 refund = d.amountPaid - totalCharge;

    // 4. Move funds: pay LLM infra + protocol + optionally gas pot
    IERC20(d.token).transfer(llmTreasury, baseCost);
    if (gasComp > 0) IERC20(d.token).transfer(facilitatorTreasury, gasComp);
    if (fee > 0) IERC20(d.token).transfer(protocolTreasury, fee);

    if (refund > 0) IERC20(d.token).transfer(d.user, refund);
}
```

Now:

* **Dynamic pricing** is encapsulated in `pricing` struct.
* You are free to update `pricing` over time via:

  * admin/governance calls, or
  * Uniswap v4 hook logic (next step).
* `tokensUsed` is only known **after** inference—so it’s passed into `settleRequest`.

This is exactly the architecture you want: **pricing function applied at settlement using tokensUsed**.

---

## Step 3 – Where do Uniswap v4 hooks come in?

Now we plug Uniswap v4 hooks into this story in a clean way.

The hook contract is:

* both **the EIP-3009 payment recipient / settlement contract**, and
* a **v4 hook** attached to *some* pool (e.g. USDC / `$Atrium`).

The Uniswap hook is *not* directly used for the payment for each inference; rather it is used to **dynamically update the pricing parameters** based on market data.

Examples:

* In `afterSwap` on a USDC/$Atrium pool, you can:

  * read the new price / tick,
  * compute an implied volatility or TWAP,
  * update `pricing.pricePerInputToken` or add a `surgeFactor`.

Pseudo:

```solidity
function afterSwap(
    address sender,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    BalanceDelta delta,
    bytes calldata hookData
) external override returns (bytes4) {
    // 1. Use pool state / tick / volume to compute new dynamic price
    (int24 tick,,,,,) = poolManager.getSlot0(key.toId());
    uint256 newBasePrice = computePriceFromTick(tick);

    pricing.pricePerInputToken = newBasePrice;
    // maybe also adjust protocolFeeBps based on liquidity or utilization

    return BaseHook.afterSwap.selector;
}
```

Key point:

* **Uniswap hook → updates `pricing` over time.**
* **Settlement (`settleRequest`) → uses `pricing` and `tokensUsed` to calculate bill.**

This keeps dynamic pricing:

* **on-chain**, transparent,
* based on an open market (the pool),
* but still applied **after** inference, when you know exact usage.

---

## Step 4 – Answering your 3 pain points explicitly

### 1. “The funds for sponsoring gas must be in the hook contract.”

✅ You can achieve this **economically** like so:

* All user funds flow into the hook via **EIP-3009**.
* When you settle:

  * You include a **gas compensation component** (`gasComp`) in the charge.
  * That gas compensation is transferred from the hook contract to a **facilitatorTreasury** address controlled by the x402 server operator.
* Practically:

  * Facilitator EOA pays gas,
  * Later recovers gas cost from hook contract via `settleRequest` payouts.

Contracts cannot literally pay gas up front, but this pattern fully meets the **“gas sponsored from hook funds”** requirement.

---

### 2. “The hook contract must get the total number of tokens used…”

✅ You give the usage data to the hook at settlement:

* Server calls:

  ```solidity
  settleRequest(requestId, inputTokens, outputTokens);
  ```

* Hook stores/logs usage and computes cost with its current `pricing`.

This is the cleanest way: hook knows **tokensUsed** and uses it in its billing logic.

---

### 3. “Once we get total tokens consumed, we calculate the difference and refund.”

✅ This falls out naturally from the deposit pattern:

* Deposit: `amountPaid` from EIP-3009 into hook.
* Settlement:

  * `totalCharge = f(tokensUsed, pricing)`.
  * `refund = amountPaid - totalCharge`.
  * Hook sends `refund` back to `user`.

That’s exactly the “user only pays for what they used” semantics:

* They over-deposit via EIP-3009 max amount.
* Real cost is computed **after** usage.
* Hook enforces refund.

---

## TL;DR – Is this the “right” architecture?

Yes, structurally it *is* the right direction, **provided you accept**:

* The resource server is a **trusted reporter** of `tokensUsed`.
* Dynamic pricing is evaluated **at settlement**, using:

  * `tokensUsed` (from server), and
  * `pricing` (dynamic on-chain parameters, possibly updated via Uniswap v4 hooks).
* Gas sponsorship is **economic, not literal**: the hook holds funds, the EOA pays gas, and is compensated from hook balances.

If you want, next we can:

* Write the exact `settleRequest` interface and storage layout for the hook contract, and
* Show two variants of how `pricing` can be updated (simple admin vs Uniswap-driven),
  so you can start coding the actual Solidity.
