"""Read one Uniswap v3 pool on Ethereum mainnet. Read-only: it cannot trade.

The script only makes view calls, which an RPC node answers from its copy of
the chain. It holds no wallet or signing key, so it has no way to change state.

Flow: find the pool through the factory, read every value at one pinned block,
validate what came back, then convert the raw price into a readable one.
"""

import math
import os
import sys
from datetime import datetime, timezone
from fractions import Fraction
from pathlib import Path

from dotenv import load_dotenv
from web3 import HTTPProvider, Web3

# --- Inputs ------------------------------------------------------------------
CHAIN_ID = 1  # Ethereum mainnet
FACTORY = "0x1F98431c8aD98523631AE4a59f267346ea31F984"  # UniswapV3Factory
USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
FEE_TIER = 500  # hundredths of a basis point, so 500 = 0.05%
TICK_SPACING = 10  # the factory pairs this spacing with the 0.05% fee tier

ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
Q96 = 2**96
# One tick moves the price 0.01%. The margin covers float rounding only.
TICK_TOLERANCE = 0.00011


def _view(name, inputs=(), outputs=()):
    """Build an ABI entry. Every entry is marked view, so this file has no
    function that could change on-chain state."""
    return {
        "type": "function",
        "name": name,
        "stateMutability": "view",
        "inputs": [{"name": "", "type": t} for t in inputs],
        "outputs": [{"name": "", "type": t} for t in outputs],
    }


FACTORY_ABI = [_view("getPool", ["address", "address", "uint24"], ["address"])]

POOL_ABI = [
    _view("factory", outputs=["address"]),
    _view("token0", outputs=["address"]),
    _view("token1", outputs=["address"]),
    _view("fee", outputs=["uint24"]),
    _view("tickSpacing", outputs=["int24"]),
    _view("liquidity", outputs=["uint128"]),
    _view(
        "slot0",
        outputs=["uint160", "int24", "uint16", "uint16", "uint16", "uint8", "bool"],
    ),
]

ERC20_ABI = [
    _view("symbol", outputs=["string"]),
    _view("decimals", outputs=["uint8"]),
    _view("balanceOf", ["address"], ["uint256"]),
]


class PoolCheckFailed(Exception):
    """The chain data did not match what this script expects."""


def require(condition, message):
    if not condition:
        raise PoolCheckFailed(message)


def read_token(w3, address, holder, block):
    token = w3.eth.contract(address=address, abi=ERC20_ABI)
    return {
        "address": address,
        "symbol": token.functions.symbol().call(block_identifier=block),
        "decimals": token.functions.decimals().call(block_identifier=block),
        "balance_raw": token.functions.balanceOf(holder).call(block_identifier=block),
    }


def read_pool(w3, block=None):
    """Read and validate the pool at one block, and return the results."""
    chain_id = w3.eth.chain_id
    require(chain_id == CHAIN_ID, f"expected chain {CHAIN_ID}, RPC is on {chain_id}")

    # Every read uses this block, so all values come from one snapshot.
    if block is None:
        block = w3.eth.block_number
    timestamp = w3.eth.get_block(block)["timestamp"]

    factory = w3.eth.contract(address=FACTORY, abi=FACTORY_ABI)
    pool_address = factory.functions.getPool(USDC, WETH, FEE_TIER).call(
        block_identifier=block
    )
    require(
        pool_address != ZERO_ADDRESS,
        f"factory has no USDC/WETH pool at fee tier {FEE_TIER}",
    )

    pool = w3.eth.contract(address=pool_address, abi=POOL_ABI)
    pool_factory = pool.functions.factory().call(block_identifier=block)
    token0_address = pool.functions.token0().call(block_identifier=block)
    token1_address = pool.functions.token1().call(block_identifier=block)
    fee = pool.functions.fee().call(block_identifier=block)
    tick_spacing = pool.functions.tickSpacing().call(block_identifier=block)
    liquidity = pool.functions.liquidity().call(block_identifier=block)
    sqrt_price_x96, tick, *_ = pool.functions.slot0().call(block_identifier=block)

    token0 = read_token(w3, token0_address, pool_address, block)
    token1 = read_token(w3, token1_address, pool_address, block)

    # Validation: each check catches a different way to read the wrong thing.
    require(pool_factory == FACTORY, f"pool reports factory {pool_factory}")
    require(
        (token0_address, token1_address) == (USDC, WETH),
        f"unexpected pair {token0_address} / {token1_address}",
    )
    require(fee == FEE_TIER, f"expected fee {FEE_TIER}, pool reports {fee}")
    require(
        tick_spacing == TICK_SPACING,
        f"expected tick spacing {TICK_SPACING}, pool reports {tick_spacing}",
    )
    require(
        (token0["symbol"], token0["decimals"]) == ("USDC", 6),
        f"unexpected token0 {token0['symbol']} with {token0['decimals']} decimals",
    )
    require(
        (token1["symbol"], token1["decimals"]) == ("WETH", 18),
        f"unexpected token1 {token1['symbol']} with {token1['decimals']} decimals",
    )

    # This part is our calculation, not the protocol's. The pool stores
    # sqrt(token1/token0) in smallest units, scaled up by 2^96.
    raw_price = Fraction(sqrt_price_x96, Q96) ** 2

    # Second route to the same price: price = 1.0001^tick.
    ratio = float(raw_price) / 1.0001**tick
    require(
        abs(ratio - 1) <= TICK_TOLERANCE,
        f"sqrtPriceX96 and tick disagree (ratio {ratio})",
    )

    # USDC has 6 decimals and WETH has 18, so scale to whole tokens.
    weth_per_usdc = raw_price * Fraction(10) ** (token0["decimals"] - token1["decimals"])

    return {
        "block": block,
        "timestamp": timestamp,
        "pool": pool_address,
        "fee": fee,
        "tick_spacing": tick_spacing,
        "liquidity": liquidity,
        "sqrt_price_x96": sqrt_price_x96,
        "tick": tick,
        "token0": token0,
        "token1": token1,
        "weth_per_usdc": weth_per_usdc,
        "usdc_per_weth": 1 / weth_per_usdc,
    }


def print_report(r):
    observed = datetime.fromtimestamp(r["timestamp"], timezone.utc)
    print("Uniswap v3 pool read (view calls only)")
    print(f"Network:        Ethereum mainnet (chain {CHAIN_ID})")
    print(f"Block:          {r['block']}")
    print(f"Block time:     {observed:%Y-%m-%d %H:%M:%S} UTC")
    print(f"Pool:           {r['pool']}")
    print(f"Pair:           {r['token0']['symbol']} / {r['token1']['symbol']}")
    print(f"Fee:            {r['fee'] / 10_000}%")
    print()
    print("Raw values from the contract")
    print(f"sqrtPriceX96:   {r['sqrt_price_x96']}")
    print(f"tick:           {r['tick']}")
    print(f"liquidity:      {r['liquidity']}")
    for token in (r["token0"], r["token1"]):
        print(f"{token['symbol'] + ' balance:':<16}{token['balance_raw']}")
    print()
    print("Computed by this script")
    print(f"USDC per WETH:  {float(r['usdc_per_weth']):,.2f}")
    print(f"WETH per USDC:  {float(r['weth_per_usdc']):.10f}")
    for token in (r["token0"], r["token1"]):
        amount = float(Fraction(token["balance_raw"], 10 ** token["decimals"]))
        print(f"{token['symbol'] + ' held:':<16}{amount:,.2f}")
    print()
    print("All validation checks passed.")


def main():
    load_dotenv(Path(__file__).with_name(".env"))
    base_url = os.getenv("RPC_BASE_URL", "").strip()
    api_key = os.getenv("API_KEY", "").strip()

    if not base_url or not api_key:
        sys.exit("Missing API key: open .env and paste your key after API_KEY=")

    url = f"{base_url.rstrip('/')}/{api_key}"
    w3 = Web3(HTTPProvider(url, request_kwargs={"timeout": 30}))

    try:
        result = read_pool(w3)
    except PoolCheckFailed as exc:
        sys.exit(f"Validation failed: {exc}")
    except Exception as exc:
        # The key is part of the URL, and network errors can quote the URL.
        message = str(exc).replace(api_key, "<API_KEY>")
        sys.exit(f"RPC request failed ({type(exc).__name__}): {message}")

    print_report(result)


if __name__ == "__main__":
    main()
