# Uniswap v3 Pool Reader

A small Python script that reads the USDC/WETH 0.05% pool on Ethereum mainnet and prints its price, active liquidity, tick and token balances at one block.

It is read-only. It only makes `view` calls, holds no wallet or signing key, and cannot trade.

## Setup (Windows)

You need 64-bit Windows and a free API key from an Ethereum RPC provider such as Alchemy. No funds or wallet are needed. You don't need to install Python first.

From the project folder, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

The script:

1. Looks for a 64-bit Python 3.14. If there isn't one, it downloads the official installer from python.org, checks it against the SHA-256 checksum python.org publishes, and installs it for your user only. Other Python versions stay installed, and it doesn't change PATH or which Python opens `.py` files.
2. Builds `.venv` with Python 3.14 and installs `requirements.txt` into it. If an existing `.venv` was built with a different Python, it deletes and rebuilds it.
3. Creates `.env` from `.env.example` if you don't have one yet.

You can rerun it at any time. It keeps a `.venv` that is already correct. `-ExecutionPolicy Bypass` applies only to this one command; without it, Windows blocks local scripts by default.

The project needs Python 3.14 specifically because `web3` depends on `ckzg`, a C library whose prebuilt Windows packages cover 64-bit Python 3.9 to 3.14 only. On a newer or 32-bit Python, pip tries to compile it and fails unless a C compiler is installed.

Then open `.env` and paste your key after `API_KEY=`. To use Infura, set `RPC_BASE_URL=https://mainnet.infura.io/v3/`.

`.env` is ignored by git. Never commit a real key.

## Run

```powershell
.venv\Scripts\python read_pool.py
```

That command always works, with no activation needed.

`python read_pool.py` also works if you have a `python` command on PATH, whatever its version. If that Python doesn't have the packages, the script restarts itself with the `.venv` Python. Setup doesn't add Python to PATH, so on a machine that had no Python before, use the `.venv` command above.

## Troubleshooting

**`Failed to build ckzg` during install:** pip ran on a Python that `ckzg` has no prebuilt package for, usually a newer default Python. Run `setup.ps1` instead of installing by hand. It rebuilds `.venv` with Python 3.14.

**`... is not installed and there is no .venv`:** run `setup.ps1` first.

**`ModuleNotFoundError: No module named 'dotenv'`** (or `'web3'`): `.venv` exists but is missing packages, usually because an earlier install failed. Run `setup.ps1` again. Don't fix it by running `pip install` on your system Python; that installs into a different place from `.venv`.

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
