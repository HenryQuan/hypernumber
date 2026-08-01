# Hyperliquid Number

A lightweight Python/uv CLI that accepts any public Hyperliquid wallet address and builds a trading report from the public Info API. No private key, API key, or account connection is used.

## Run

```bash
uv run hyperliquid-tracker 0x0000000000000000000000000000000000000000
uv run hyperliquid-tracker 0x... --since 2024-01-01 --json
```

Install as a local project if preferred:

```bash
uv sync
uv run hyperliquid-tracker <address>
```

The report includes realized trade count, win/loss rates, gross and average P&L, profit factor, expected payoff, Sharpe estimate, streaks, direction split, activity, holding time, latest trade, and current account value. `--json` is intended for dashboards and downstream applications.

## Important metric semantics

Hyperliquid returns `closedPnl` per closing fill, so “Trades” means realized/closing fills, not order submissions or open positions. Fees are deducted from each realized result. A trade may be split into multiple fills by the exchange. Holding time is FIFO-matched at the coin level.

The public API does not contain enough information to reproduce deposit-relative drawdown, pips, monthly growth, annual forecast, maximum deposit load, or algo-trading percentage. The CLI deliberately prints `n/a` for those instead of inventing values. An equity-history provider can be added later to calculate them.

## Development

```bash
uv run python -m compileall hyperliquid_tracker
```

The project uses only the Python standard library and Python 3.11+.
