# Uniswap v3 Pool Reader

A small Python script that reads the USDC/WETH 0.05% pool on Ethereum mainnet and prints its price, active liquidity, tick and token balances at one block.

It is read-only. It only makes `view` calls, holds no wallet or signing key, and cannot trade.

## Setup (Windows PowerShell)

You need Python 3.14 and a free API key from an Ethereum RPC provider such as Alchemy. No funds or wallet are needed.

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt
copy .env.example .env
```

If `python` isn't on your PATH, use the full path to `python.exe` for the first command. On the original machine that is:

```powershell
& "$env:LOCALAPPDATA\Programs\Python\Python314\python.exe" -m venv .venv
```

Then open `.env` and paste your key after `API_KEY=`. To use Infura, set `RPC_BASE_URL=https://mainnet.infura.io/v3/`.

`.env` is ignored by git. Never commit a real key.

## Run

```powershell
.venv\Scripts\python read_pool.py
```

## What it reads

| Input | Value |
|---|---|
| Network | Ethereum mainnet (chain ID 1) |
| UniswapV3Factory | `0x1F98431c8aD98523631AE4a59f267346ea31F984` |
| USDC | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` |
| WETH | `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` |
| Fee tier | `500` (0.05%) |
| Block | Latest block at run time |

The pool address is not hardcoded. The script gets it from `factory.getPool(USDC, WETH, 500)`, which returns `0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640`.

Dependencies are `web3` and `python-dotenv`, at the exact versions in `requirements.txt`.

## How it works

1. Connects to the RPC provider and confirms it is on chain ID 1.
2. Pins the latest block number and uses it for every read, so all values come from one snapshot.
3. Calls view functions on the factory, the pool and both tokens.
4. Runs the validation checks below.
5. Converts the raw price into a readable one. This step happens in the script, not in the protocol:

   ```text
   WETH per USDC = (sqrtPriceX96 / 2^96)^2 * 10^(6 - 18)
   USDC per WETH = 1 / (WETH per USDC)
   ```

## Validation checks

The script stops with a specific error if any of these fail:

| Check | What it catches |
|---|---|
| Chain ID is 1 | An RPC URL for the wrong network |
| `getPool` is not the zero address | A wrong token or fee tier, or a pool that doesn't exist |
| `pool.factory()` is the Uniswap factory | A pool that didn't come from the expected factory |
| `token0` and `token1` are USDC and WETH | Wrong token inputs |
| Fee is 500 and tick spacing is 10 | Mismatched fee settings |
| Symbols are USDC and WETH, with 6 and 18 decimals | Wrong assumptions about the tokens, which would skew the price |
| Price from `sqrtPriceX96` agrees with `1.0001^tick` | Mistakes in the price formula or inconsistent data |

If the RPC request fails, the error message has the API key replaced with `<API_KEY>`, because these errors can quote the full URL.

## Check the output yourself

1. Open the pool's [Read Contract tab on Etherscan](https://etherscan.io/address/0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640#readContract).
2. Compare `slot0` and `liquidity` with the script's raw values.

Etherscan shows the latest state, and this pool updates with every swap, so expect values that are close rather than identical unless both reads land on the same block.

## Limitations

- **Trust in the RPC provider:** the script believes what the provider returns. It doesn't verify state with proofs.
- **Snapshot only:** the output describes one block and goes out of date as swaps happen.
- **Price is not a quote:** it leaves out the 0.05% fee and price impact, so a real trade would get a different result.
- **Balances are not usable depth:** liquidity is concentrated in price ranges, and token balances include fees that haven't been collected.

## Sources

- [Uniswap v3 Ethereum deployments](https://developers.uniswap.org/docs/protocols/v3/deployments/v3-ethereum-deployments): factory and WETH addresses
- [Circle USDC contract addresses](https://developers.circle.com/stablecoins/usdc-contract-addresses): USDC address
- [`IUniswapV3PoolState.sol`](https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/pool/IUniswapV3PoolState.sol): `slot0` and `liquidity`
- [`IUniswapV3PoolImmutables.sol`](https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol): `factory`, `token0`, `token1`, `fee`, `tickSpacing`
- [`IUniswapV3Factory.sol`](https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/IUniswapV3Factory.sol): `getPool`
