from __future__ import annotations

import argparse
import json
import re
import sys
from bisect import bisect_left
from datetime import UTC, datetime

from .analytics import calculate, display_time
from .api import HyperliquidClient, HyperliquidError

ADDRESS = re.compile(r"^0x[0-9a-fA-F]{40}$")


def fmt(v):
    return "n/a" if v is None else f"{v:,.2f}" if isinstance(v, float) else str(v)


def multiple(v):
    return f"{fmt(v)}x" if v is not None else "n/a"


def compact(v):
    if v is None:
        return "n/a"
    v = abs(float(v))
    sign = "-" if float(v) < 0 else ""
    for unit, size in (("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if v >= size:
            return f"{sign}{v / size:.3f}{unit}"
    return f"{sign}{v:.2f}"


def equity_chart(points):
    if not points:
        return "n/a"
    monthly = {}
    for timestamp, value in points:
        date = datetime.fromtimestamp(timestamp / 1000, UTC)
        monthly[(date.year, date.month)] = value
    years = sorted({year for year, _ in monthly})
    lines = [
        f"{'Year':<10}"
        + "".join(
            f"{m:>9}"
            for m in (
                "Jan",
                "Feb",
                "Mar",
                "Apr",
                "May",
                "Jun",
                "Jul",
                "Aug",
                "Sep",
                "Oct",
                "Nov",
                "Dec",
            )
        )
    ]
    for year in years:
        values = [monthly.get((year, month)) for month in range(1, 13)]
        cells = "".join(
            f"{compact(v):>9}" if v is not None else f"{'-':>9}" for v in values
        )
        lines.append(f"{year:<10}" + cells)
    return "\n".join(lines)


def draw_equity_chart(points):
    """10-row terminal line chart: peak at row 0, bottom at row 9, oldest left.
    The x-axis is proportional to real time, so each column's date label
    exactly matches the data drawn at that position."""
    if not points:
        return "no equity data yet"
    width = 110
    items = sorted(points)
    ts_list = [t for t, _ in items]
    values = [v for _, v in items]
    t0, t1 = ts_list[0], ts_list[-1]
    lo, hi = min(values), max(values)
    rows = 10

    def row_of(v):
        if hi == lo:
            return rows // 2
        return rows - 1 - round((v - lo) / (hi - lo) * (rows - 1))

    def value_at(ts):
        i = bisect_left(ts_list, ts)
        if i == 0:
            return values[0]
        if i >= len(ts_list):
            return values[-1]
        before = ts - ts_list[i - 1]
        after = ts_list[i] - ts
        return values[i - 1] if before <= after else values[i]

    grid = [[" "] * width for _ in range(rows)]
    prev_row = None
    for c in range(width):
        ts = t0 + (t1 - t0) * (c / (width - 1))
        r = row_of(value_at(ts))
        grid[r][c] = "-"
        if prev_row is not None and prev_row != r:
            for k in range(min(prev_row, r) + 1, max(prev_row, r)):
                grid[k][c] = "|"
        prev_row = r

    labels = [" "] * width
    step = max(1, width // 7)
    for c in range(0, width, step):
        ts = t0 + (t1 - t0) * (c / (width - 1))
        label = datetime.fromtimestamp(ts / 1000, UTC).strftime("%b %Y")
        start = max(0, c - len(label) // 2)
        for j, ch in enumerate(label):
            if start + j < width:
                labels[start + j] = ch
    lines = []
    for r in range(rows):
        line = "".join(grid[r]).rstrip()
        if r == 0:
            line += f"   max {compact(hi)}"
        lines.append(line if line else " ")
    lines.append("".join(labels).rstrip())
    return "\n".join(lines)


def combine(growths):
    values = [v for v in growths if v is not None]
    if not values:
        return 0
    factors = [1 + v / 100 for v in values]
    if all(f > 0 for f in factors):
        return (__import__("math").prod(factors) - 1) * 100
    return sum(values)


def print_report(address, s):
    total = s["trades"]
    wp = s["profit_trades"] / total * 100 if total else 0
    lp = s["loss_trades"] / total * 100 if total else 0
    rows = [
        (
            "Trades",
            total,
            "Profitability",
            f"{s['profit_trades']} ({wp:.2f}%) / {s['loss_trades']} ({lp:.2f}%)",
        ),
        (
            "Average Win",
            f"{fmt(s['average_profit_usdc'])} USDC",
            "Average Loss",
            f"{fmt(s['average_loss_usdc'])} USDC",
        ),
        (
            "Fees",
            f"-{fmt(s['fees_usdc'])} USDC",
            "Funding",
            f"{fmt(s['funding_usdc'])} USDC",
        ),
        (
            "Net P&L",
            f"{fmt(s['net_profit_usdc'])} USDC",
            "Portfolio PNL",
            f"{fmt(s['portfolio_pnl_usdc'])} USDC ({compact(s['portfolio_pnl_usdc'])})",
        ),
        (
            "Volume",
            f"{fmt(s['volume_usdc'])} USDC",
            "Max Drawdown",
            f"{fmt(s['max_drawdown_percent'])}%",
        ),
        (
            "Total Equity",
            f"{fmt(s['total_equity_usdc'])} USDC",
            "Trading Equity",
            f"{fmt(s['trading_equity_usdc'])} USDC",
        ),
        (
            "Current Leverage",
            multiple(s.get("account_leverage")),
            "History Leverage",
            multiple(s.get("history_leverage")),
        ),
        (
            "Longs Won",
            f"({s['long_wins']}/{s['long_trades']}) {s['long_wins'] / s['long_trades'] * 100:.0f}%"
            if s["long_trades"]
            else "n/a",
            "Shorts Won",
            f"({s['short_wins']}/{s['short_trades']}) {s['short_wins'] / s['short_trades'] * 100:.0f}%"
            if s["short_trades"]
            else "n/a",
        ),
        (
            "Best Trade",
            f"{fmt(s['best_trade_usdc'])} USDC",
            "Worst Trade",
            f"{fmt(s['worst_trade_usdc'])} USDC",
        ),
        (
            "Avg. Trade Length",
            f"{fmt(s['avg_holding_hours'])} hours",
            "Profit Factor",
            fmt(s["profit_factor"]),
        ),
        (
            "Standard Deviation",
            f"{fmt(s['standard_deviation_usdc'])} USDC",
            "Sharpe Ratio",
            fmt(s["sharpe_ratio"]),
        ),
        (
            "Expectancy",
            f"{fmt(s['expected_payoff_usdc'])} USDC",
            "Trading Activity",
            f"{fmt(s['trading_activity_percent'])}%",
        ),
        (
            "Trades per Week",
            fmt(s["trades_per_week"]),
            "Latest Trade",
            display_time(s["latest_trade_ms"]),
        ),
        (
            "Maximum Wins",
            f"{s['maximum_consecutive_wins']} ({fmt(s['maximum_consecutive_wins_usdc'])} USDC)",
            "Maximum Losses",
            f"{s['maximum_consecutive_losses']} ({fmt(s['maximal_consecutive_loss_usdc'])} USDC)",
        ),
    ]
    print(f"Hyperliquid trading report\n{address}\n")
    for a, b, c, d in rows:
        if c:
            print(f"{a:<22}: {b:<28} {c:<22}: {d}")
        else:
            print(f"{a:<22}: {b}")
    print(f"\nEquity History (USDC)\n{equity_chart(s.get('equity_history', []))}")
    print(f"\nEquity Movement\n{draw_equity_chart(s.get('equity_history', []))}")
    growth = s.get("monthly_growth", {})
    if growth:
        print("\nAddress Growth")
        print(
            f"{'Year':<10}"
            + "".join(
                f"{m:>9}"
                for m in (
                    "Jan",
                    "Feb",
                    "Mar",
                    "Apr",
                    "May",
                    "Jun",
                    "Jul",
                    "Aug",
                    "Sep",
                    "Oct",
                    "Nov",
                    "Dec",
                )
            )
            + f"{'Year':>10}"
        )
        years = sorted({x[:4] for x in growth})
        for year in years:
            vals = [growth.get(f"{year}-{m:02d}") for m in range(1, 13)]
            total_growth = combine(vals)
            cells = "".join(
                f"{v:>8.2f}%" if v is not None else f"{'-':>9}" for v in vals
            )
            print(f"{year:<10}" + cells + f"{total_growth:>9.2f}%")
        total_growth = combine(growth.values())
        print(
            f"{'Total':<10}"
            + "".join(f"{'':>9}" for _ in range(12))
            + f"{(compact(total_growth) + '%'):>10}"
        )


def main(argv=None):
    p = argparse.ArgumentParser(
        description="Generate a trading report for any public Hyperliquid address"
    )
    p.add_argument("address")
    p.add_argument("--json", action="store_true", dest="as_json")
    p.add_argument("--since")
    p.add_argument(
        "--api", default="https://api.hyperliquid.xyz", help=argparse.SUPPRESS
    )
    a = p.parse_args(argv)
    if not ADDRESS.fullmatch(a.address):
        p.error("address must be a 0x-prefixed 40-hex-character address")
    start = None
    if a.since:
        try:
            start = int(
                datetime.strptime(a.since, "%Y-%m-%d").replace(tzinfo=UTC).timestamp()
                * 1000
            )
        except ValueError:
            p.error("--since must be YYYY-MM-DD")
    try:
        c = HyperliquidClient(a.api)
        fills = c.fills(a.address, start)
        stats = calculate(
            fills,
            c.clearinghouse_state(a.address),
            c.portfolio(a.address),
            c.funding(a.address, start),
        )
    except HyperliquidError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    if a.as_json:
        print(json.dumps({"address": a.address, **stats}, indent=2))
    else:
        print_report(a.address, stats)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
