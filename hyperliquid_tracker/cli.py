from __future__ import annotations

import argparse
import json
import re
import sys
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
    Points are stretched across the full width so the line always fills it."""
    if not points:
        return "no equity data yet"
    width = 110
    values = [v for _, v in points]
    if len(values) > width:
        idx = sorted({round(i * (len(values) - 1) / (width - 1)) for i in range(width)})
        values = [values[i] for i in idx]
    lo, hi = min(values), max(values)
    rows = 10

    def row_of(v):
        if hi == lo:
            return rows // 2
        return rows - 1 - round((v - lo) / (hi - lo) * (rows - 1))

    n = len(values)
    cols = [round(i * (width - 1) / (n - 1)) for i in range(n)] if n > 1 else [0]
    rws = [row_of(v) for v in values]
    grid = [[" "] * width for _ in range(rows)]
    for i in range(n - 1):
        c1, c2, r1, r2 = cols[i], cols[i + 1], rws[i], rws[i + 1]
        # stretch the line horizontally between consecutive points
        for c in range(c1, c2):
            if grid[r1][c] == " ":
                grid[r1][c] = "-"
        # then connect vertically to the next row
        for k in range(min(r1, r2) + 1, max(r1, r2)):
            if grid[k][c2] == " ":
                grid[k][c2] = "|"
    for c, r in zip(cols, rws):
        grid[r][c] = "-"
    lines = []
    for r in range(rows):
        line = "".join(grid[r]).rstrip()
        if r == 0:
            line += f"   max {compact(hi)}"
        lines.append(line if line else " ")
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
