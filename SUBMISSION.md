# Milestone 06 Submission Draft

This is a draft. Replace every `<fill in>`, reword it so you can explain it yourself, and paste the answers into Brightspace.

## Common Questions

### C1. Scope and purpose

I chose Uniswap v3 and the Technical track.

The user is anyone who needs to know the current state of a USDC/WETH market, such as a trader checking a price or a liquidity provider checking where the pool stands. Their problem is getting that information without trusting a centralized exchange's reported numbers.

Uniswap v3 solves this with an on-chain automated market maker. The pool holds both tokens and keeps its current price and active liquidity in public contract state, which anyone can read for free with view calls.

### C2. Evidence

**Official documentation:**

- [Uniswap v3 Ethereum deployments](https://developers.uniswap.org/docs/protocols/v3/deployments/v3-ethereum-deployments): supports the factory and WETH addresses.
- [Circle USDC contract addresses](https://developers.circle.com/stablecoins/usdc-contract-addresses): supports the USDC address.
- [`IUniswapV3PoolState.sol`](https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/pool/IUniswapV3PoolState.sol): supports the meaning of `slot0` and `liquidity`.
- [`IUniswapV3PoolImmutables.sol`](https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol): supports `factory`, `token0`, `token1`, `fee` and `tickSpacing`.
- [`IUniswapV3Factory.sol`](https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/IUniswapV3Factory.sol): supports `getPool`.

**Primary data:** contract state of pool `0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640` on Ethereum mainnet at block `<fill in>`, observed on `<fill in date and UTC time>`.

**Observations:** `sqrtPriceX96`, `tick`, `liquidity` and the token balances are values returned by the contracts.

**Interpretation:** the USDC per WETH price and whole-token amounts are my own calculations from those values. They assume the formula in the README and the tokens' decimals.

### C3. Assumptions and AI use

**Key assumption:** I trust my RPC provider to return true chain state. The script doesn't verify state with proofs, so a faulty or dishonest provider could give me wrong numbers that still look valid. The validation checks would catch inconsistent or mismatched data, but not a carefully faked response. Comparing against Etherscan reduces this risk because it is a separate source.

**AI use:** I used Claude (Claude Code) to help plan and write the script, README and this draft. I checked it by `<fill in what you did, for example: reading the code, running it with my own key, comparing the raw values with Etherscan>`. Claude checked the addresses against Uniswap's and Circle's documentation and ran the development tests listed under T2.

## Technical Track

### T1. Reproducible interaction

I built a Python script that reads the USDC/WETH 0.05% Uniswap v3 pool using view calls only.

- **Repository:** `<fill in your standalone GitHub link>`
- **Network:** Ethereum mainnet (chain ID 1)
- **Contracts:** UniswapV3Factory `0x1F98431c8aD98523631AE4a59f267346ea31F984`, which returns pool `0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640`
- **Inputs:** USDC `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`, WETH `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`, fee tier `500`
- **Dependencies:** Python 3.14, `web3` 8.0.0, `python-dotenv` 1.2.4, and an RPC provider API key
- **Run steps:** the README has the full setup. After that, add your key to `.env` and run `.venv\Scripts\python read_pool.py`.

### T2. Output and verification

**Output (block `<fill in>`, `<fill in date and UTC time>`):**

```text
<paste your console output here>
```

**Expected:** a USDC per WETH price close to the market price at that time, and all validation checks passing.

**What happened:** `<fill in>`

**How I verified it:** I compared `slot0` and `liquidity` with the pool's [Read Contract tab on Etherscan](https://etherscan.io/address/0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640#readContract). Result: `<fill in, and note any difference caused by reading a different block>`

**Development tests, run by Claude on 2026-11-05 at block 26351189 through a public RPC, not my API key:**

- Raw `eth_call` requests that bypassed `web3` returned the same `sqrtPriceX96`, `tick` and `liquidity`.
- Five deliberately wrong inputs (two fee tiers, tick spacing, chain ID and token address) were each stopped by a validation check.
- An empty key stopped the script before any network call, and a rejected key produced an error with the key hidden.

### T3. Architecture and limits

The script loads its inputs and my RPC URL, then sends read-only JSON-RPC requests to an Ethereum node through `web3`. It first confirms the network and pins one block, so that every value comes from the same snapshot. It asks the Uniswap factory for the pool address, then calls view functions on the pool and both tokens, and the node returns that contract state. The script validates those values against what it expects, then converts `sqrtPriceX96` into a readable price off-chain and prints the result. No transaction is ever sent, and the code has no signing key.

**Limitation:** I trust the RPC provider to return accurate state, and the printed price is a one-block snapshot that excludes the 0.05% fee and price impact, so it isn't what a trade would actually pay.

**Optional Challenge:** the script compares the price from `sqrtPriceX96` with the price implied by `tick` (`1.0001^tick`). This catches mistakes in the price formula or inconsistent data, because two separate on-chain values have to agree.

## DeFi Track

- **D1:** Not attempted
- **D2:** Not attempted
- **D3:** Not attempted
- **D4:** Not attempted

## Final Reflection

### R1. Bridge to the final project

Answer these from your own final-project idea:

- **How this could become part of the project:** `<fill in>`
- **One specific next step:** `<fill in>`
- **One question still to resolve:** `<fill in>`
