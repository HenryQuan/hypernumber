from __future__ import annotations

import math
from bisect import bisect_left, bisect_right
from collections import defaultdict, deque
from datetime import UTC, datetime
from statistics import mean, pstdev
from typing import TypedDict


class RealizedTrade(TypedDict):
    pnl: float
    time: int
    side: str


def number(value, default=0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def money(value: float | None) -> float | None:
    return round(value, 2) if value is not None else None


def _holding_hours(fills: list[dict]) -> float | None:
    lots: dict[str, deque[tuple[float, float, int]]] = defaultdict(deque)
    durations = []
    for fill in fills:
        coin, qty = str(fill.get("coin", "?")), abs(number(fill.get("sz")))
        if not qty:
            continue
        sign = (
            1
            if str(fill.get("side", "")).lower() in {"b", "buy", "long", "open long"}
            else -1
        )
        book = lots[coin]
        while qty and book and book[0][1] * sign < 0:
            old_sign, old_qty, opened = book[0]
            matched = min(qty, old_qty)
            durations.append((matched, max(0, int(fill.get("time", opened)) - opened)))
            qty -= matched
            old_qty -= matched
            book.popleft()
            if old_qty:
                book.appendleft((old_sign, old_qty, opened))
        if qty:
            book.append((sign, qty, int(fill.get("time", 0))))
    total = sum(q for q, _ in durations)
    return sum(q * ms for q, ms in durations) / total / 3_600_000 if total else None


def _pnl_density(portfolio: list, per_day: bool = False) -> float:
    """Approximate pnl snapshots per day or per week (0 if unknown)."""
    points = []
    for item in portfolio:
        if (
            isinstance(item, list)
            and item
            and item[0] == "allTime"
            and isinstance(item[1], dict)
        ):
            points = [
                x
                for x in item[1].get("pnlHistory", [])
                if isinstance(x, list) and len(x) > 1
            ]
            break
    if len(points) < 2:
        return 0.0
    span = int(points[-1][0]) - int(points[0][0])
    denominator = 86_400_000 if per_day else 604_800_000
    periods = span / denominator
    return len(points) / periods if periods > 0 else 0.0


def _net_flows(portfolio: list) -> tuple[float, float]:
    """Estimate total deposits and withdrawals (USDC) from equity & pnl changes.
    net flow per snapshot = equity change - pnl change; positive sums are
    deposits, negative sums are withdrawals (net per period, so a deposit and
    withdrawal inside one snapshot window net out)."""
    equity, pnl = [], []
    for item in portfolio:
        if not (
            isinstance(item, list)
            and item
            and item[0] == "allTime"
            and isinstance(item[1], dict)
        ):
            continue
        for point in item[1].get("accountValueHistory", []):
            if isinstance(point, list) and len(point) > 1:
                equity.append((int(point[0]), number(point[1])))
        for point in item[1].get("pnlHistory", []):
            if isinstance(point, list) and len(point) > 1:
                pnl.append((int(point[0]), number(point[1])))
        break
    equity.sort()
    pnl.sort()
    pnl_ts = [t for t, _ in pnl]

    def pnl_at(ts):
        i = bisect_right(pnl_ts, ts) - 1
        return pnl[i][1] if i >= 0 else 0.0

    deposits = withdrawals = 0.0
    for i in range(1, len(equity)):
        flow = (equity[i][1] - equity[i - 1][1]) - (
            pnl_at(equity[i][0]) - pnl_at(equity[i - 1][0])
        )
        if flow > 0:
            deposits += flow
        else:
            withdrawals += -flow
    return deposits, withdrawals


def _period_returns(portfolio: list, freq: str = "M") -> dict[str, float]:
    """Trading return per period: cumulative-PnL delta / equity at period start.
    Uses PnL history (not raw equity), so deposits/withdrawals are excluded.
    freq: "M" for monthly (Y-M keys) or "W" for weekly (ISO year-week keys)."""
    equity, pnl = [], []
    for item in portfolio:
        # Only the allTime bucket: the per-day/week/month buckets are subsets
        # with different (sometimes zero) equity, so merging them corrupts pnl.
        if not (
            isinstance(item, list)
            and item
            and item[0] == "allTime"
            and isinstance(item[1], dict)
        ):
            continue
        for point in item[1].get("accountValueHistory", []):
            if isinstance(point, list) and len(point) > 1:
                equity.append((int(point[0]), number(point[1])))
        for point in item[1].get("pnlHistory", []):
            if isinstance(point, list) and len(point) > 1:
                pnl.append((int(point[0]), number(point[1])))
    equity.sort()
    pnl.sort()
    if not pnl:
        return {}
    equity_ts = [t for t, _ in equity]
    max_equity = max((v for _, v in equity), default=0)

    def equity_at(ts):
        # Equity strictly BEFORE ts: the balance the period started with, so a
        # deposit or gain inside the period never leaks into the denominator.
        i = bisect_left(equity_ts, ts) - 1
        if i >= 0 and equity[i][1] > 0:
            return equity[i][1]
        # Account starts with a zero-balance snapshot before the first deposit;
        # roll forward to the first real funded balance so the first period's
        # return is measured against the capital actually traded with.
        for t, v in equity:
            if t >= ts and v > 0:
                return v
        return 0.0

    def period_key(ts):
        dt = datetime.fromtimestamp(ts / 1000, UTC)
        if freq == "W":
            iso = dt.isocalendar()
            return f"{iso[0]}-W{iso[1]:02d}"
        if freq == "D":
            return dt.strftime("%Y-%m-%d")
        return dt.strftime("%Y-%m")

    by_period: dict[str, list[tuple[int, float]]] = defaultdict(list)
    for t, v in pnl:
        by_period[period_key(t)].append((t, v))
    result = {}
    prev_pnl: float | None = None
    for period, points in sorted(by_period.items()):
        points.sort()
        end_pnl = points[-1][1]
        # Carry the previous period's final PnL: the change between periods
        # belongs to the later period, so deposits/withdrawals inside a period
        # only affect that period's return, not the ones around it.
        start_pnl = prev_pnl if prev_pnl is not None else points[0][1]
        opening_equity = equity_at(points[0][0])
        # Ignore periods that start on a near-zero seed balance.
        if opening_equity >= max_equity * 0.01 and opening_equity:
            result[period] = round((end_pnl - start_pnl) / opening_equity * 100, 2)
        prev_pnl = end_pnl
    return result


def _historical_leverage(fills: list[dict], portfolio: list) -> float | None:
    history = []
    for item in portfolio:
        if (
            isinstance(item, list)
            and item
            and item[0] == "allTime"
            and isinstance(item[1], dict)
        ):
            history = item[1].get("accountValueHistory", [])
    history = sorted(
        (int(x[0]), number(x[1])) for x in history if isinstance(x, list) and len(x) > 1
    )
    max_equity = max((x[1] for x in history), default=0)
    positions = defaultdict(float)
    maximum = None
    for fill in sorted(fills, key=lambda x: int(x.get("time", 0))):
        coin = str(fill.get("coin", "?"))
        side = str(fill.get("side", "")).lower()
        positions[coin] += (1 if side in {"b", "buy"} else -1) * abs(
            number(fill.get("sz"))
        )
        price = number(fill.get("px"))
        timestamp = int(fill.get("time", 0))
        equity = next((v for t, v in reversed(history) if t <= timestamp), 0)
        if equity >= max_equity * 0.01 and equity:
            exposure = sum(abs(q) * price for q in positions.values())
            maximum = max(maximum or 0, exposure / equity)
    if maximum is None:
        return None
    # A handful of fills can land on tiny equity points and produce absurd
    # ratios (e.g. 700x). Cap at a sane level so "combined history leverage"
    # stays close to the trader's real setting (e.g. ~25x for a 25x trader).
    return round(min(maximum, 100.0), 2)


def calculate(
    fills: list[dict],
    state: dict | None = None,
    portfolio: list | None = None,
    funding: list[dict] | None = None,
) -> dict:
    fills = sorted(fills, key=lambda x: int(x.get("time", 0)))
    realized: list[RealizedTrade] = []
    for fill in fills:
        if "closedPnl" not in fill or number(fill.get("closedPnl")) == 0:
            continue
        realized.append(
            {
                "pnl": number(fill.get("closedPnl")) - abs(number(fill.get("fee"))),
                "time": int(fill.get("time", 0)),
                "side": str(fill.get("side", "")).lower(),
            }
        )
    pnls = [x["pnl"] for x in realized]
    wins = [x for x in pnls if x > 0]
    losses = [x for x in pnls if x < 0]
    gross_profit, gross_loss = sum(wins), sum(losses)
    longest_win = longest_loss = run_win = run_loss = 0
    win_run_profit = loss_run_profit = max_win_run_profit = max_loss_run_profit = 0.0
    for value in pnls:
        if value > 0:
            run_win += 1
            run_loss = 0
            win_run_profit += value
            loss_run_profit = 0
            longest_win = max(longest_win, run_win)
            max_win_run_profit = max(max_win_run_profit, win_run_profit)
        elif value < 0:
            run_loss += 1
            run_win = 0
            loss_run_profit += value
            win_run_profit = 0
            longest_loss = max(longest_loss, run_loss)
            max_loss_run_profit = min(max_loss_run_profit, loss_run_profit)
        else:
            run_win = run_loss = 0
            win_run_profit = loss_run_profit = 0
    times = [x["time"] for x in realized]
    span_weeks = ((max(times) - min(times)) / 86_400_000 / 7) if len(times) > 1 else 0
    deviation = pstdev(pnls) if len(pnls) > 1 else None
    # Full-history period returns for Sharpe/Sortino and TWR: per-trade stats
    # can be wrong for large accounts (public fills may only cover recent
    # activity). Use the finest granularity the pnl history supports so deposits
    # and withdrawals land between periods and don't distort returns: daily when
    # snapshots are dense (new accounts), weekly when weekly-sampled, else monthly.
    density_day = _pnl_density(portfolio or [], per_day=True)
    density_week = _pnl_density(portfolio or [])
    if density_day >= 2:
        period_freq, factor = "D", math.sqrt(365)
    elif density_week >= 3:
        period_freq, factor = "W", math.sqrt(52)
    else:
        period_freq, factor = "M", math.sqrt(12)
    period_returns = list(_period_returns(portfolio or [], period_freq).values())
    if len(period_returns) >= 2 and pstdev(period_returns) > 0:
        period_mean = mean(period_returns)
        period_std = pstdev(period_returns)
        sharpe = period_mean / period_std * factor
        period_losses = [x for x in period_returns if x < 0]
        period_downside = (
            (sum(x * x for x in period_losses) / len(period_losses)) ** 0.5
            if period_losses
            else 0.0
        )
        sortino = (
            period_mean / period_downside * factor if period_downside > 0 else None
        )
    else:
        sharpe = mean(pnls) / deviation * math.sqrt(len(pnls)) if deviation else None
        losses_only = [x for x in pnls if x < 0]
        downside_std = (
            (sum(x * x for x in losses_only) / len(losses_only)) ** 0.5
            if losses_only
            else 0.0
        )
        sortino = (
            mean(pnls) / downside_std * (252**0.5)
            if downside_std > 0 and pnls
            else None
        )
    period_avg_percent = mean(period_returns) if period_returns else None
    long_trades = sum(x["side"] in {"a", "sell"} for x in realized)
    short_trades = sum(x["side"] in {"b", "buy"} for x in realized)
    long_wins = sum(x["side"] in {"a", "sell"} and x["pnl"] > 0 for x in realized)
    short_wins = sum(x["side"] in {"b", "buy"} and x["pnl"] > 0 for x in realized)
    funding_total = sum(
        number((x.get("delta") or {}).get("usdc", 0))
        if isinstance(x.get("delta"), dict)
        else number(x.get("delta", x.get("usdc")))
        for x in (funding or [])
    )
    fees = sum(abs(number(f.get("fee"))) for f in fills)
    all_time = next(
        (
            x[1]
            for x in (portfolio or [])
            if isinstance(x, list)
            and x
            and x[0] == "allTime"
            and isinstance(x[1], dict)
        ),
        {},
    )
    equity_history = [
        number(x[1])
        for x in all_time.get("accountValueHistory", [])
        if isinstance(x, list) and len(x) > 1
    ]
    peak = equity_history[0] if equity_history else 0
    max_drawdown = 0.0
    for equity in equity_history:
        peak = max(peak, equity)
        if peak:
            max_drawdown = max(max_drawdown, (peak - equity) / peak * 100)

    # Extra fields ported from the backtest stats (sim.py compute_stats):
    # monthly average return, win rate, total/peak return, recovery, UPI.
    win_rate_percent = len(wins) / len(pnls) * 100 if pnls else None
    # Time-weighted returns (TWR): compound the period returns, so deposits and
    # withdrawals never distort the result (40u -> -10% -> +24u deposit -> +10%
    # compounds to -1%, not 65%).
    total_return_percent = peak_return_percent = None
    twr = twr_peak = 1.0
    valid = True
    for r in period_returns:
        factor = 1 + r / 100
        if factor <= 0:
            valid = False
            break
        twr *= factor
        twr_peak = max(twr_peak, twr)
    if valid and period_returns:
        total_return_percent = (twr - 1) * 100
        peak_return_percent = (twr_peak - 1) * 100
    recovery_factor = (
        total_return_percent / max_drawdown
        if max_drawdown > 0 and total_return_percent is not None
        else None
    )
    deposits_usdc, withdrawals_usdc = _net_flows(portfolio or [])
    dd_squares = []
    running_peak = 0.0
    for equity in equity_history:
        running_peak = max(running_peak, equity)
        if running_peak:
            dd_squares.append((1 - equity / running_peak) ** 2)
    ulcer = (sum(dd_squares) / len(dd_squares)) ** 0.5 if dd_squares else 0.0
    upi = (
        period_avg_percent / ulcer
        if ulcer > 0 and period_avg_percent is not None
        else None
    )
    result = {
        "trades": len(pnls),
        "profit_trades": len(wins),
        "loss_trades": len(losses),
        "best_trade_usdc": money(max(pnls) if pnls else None),
        "worst_trade_usdc": money(min(pnls) if pnls else None),
        "gross_profit_usdc": money(gross_profit),
        "gross_loss_usdc": money(gross_loss),
        "fees_usdc": money(fees),
        "funding_usdc": money(funding_total),
        "deposits_usdc": money(deposits_usdc),
        "withdrawals_usdc": money(withdrawals_usdc),
        "net_profit_usdc": money(sum(pnls) + funding_total),
        "maximum_consecutive_wins": longest_win,
        "maximum_consecutive_wins_usdc": money(max_win_run_profit),
        "maximal_consecutive_profit_usdc": money(max_win_run_profit),
        "maximum_consecutive_losses": longest_loss,
        "maximal_consecutive_loss_usdc": money(max_loss_run_profit),
        "sharpe_ratio": round(sharpe, 2) if sharpe is not None else None,
        "trading_activity_percent": round(
            len(fills) / max(1, (max(times) - min(times)) / 86_400_000) * 100, 2
        )
        if len(times) > 1
        else None,
        "trades_per_week": round(len(pnls) / span_weeks, 2) if span_weeks else None,
        "avg_holding_hours": (
            round(holding_hours, 2)
            if (holding_hours := _holding_hours(fills)) is not None
            else None
        ),
        "long_trades": long_trades,
        "short_trades": short_trades,
        "long_wins": long_wins,
        "short_wins": short_wins,
        "profit_factor": round(gross_profit / abs(gross_loss), 2)
        if gross_loss
        else None,
        "expected_payoff_usdc": money(sum(pnls) / len(pnls)) if pnls else None,
        "average_profit_usdc": money(gross_profit / len(wins)) if wins else None,
        "average_loss_usdc": money(gross_loss / len(losses)) if losses else None,
        "standard_deviation_usdc": money(deviation),
        "win_rate_percent": round(win_rate_percent, 2)
        if win_rate_percent is not None
        else None,
        "period_avg_percent": round(period_avg_percent, 2)
        if period_avg_percent is not None
        else None,
        "period_freq": period_freq,
        "total_return_percent": round(total_return_percent, 2)
        if total_return_percent is not None
        else None,
        "peak_return_percent": round(peak_return_percent, 2)
        if peak_return_percent is not None
        else None,
        "sortino_ratio": round(sortino, 2) if sortino is not None else None,
        "recovery_factor": round(recovery_factor, 2)
        if recovery_factor is not None
        else None,
        "upi": round(upi, 2) if upi is not None else None,
        "latest_trade_ms": times[-1] if times else None,
        "fills": len(fills),
        "monthly_growth": _period_returns(portfolio or [], "M"),
        "historical_effective_leverage": _historical_leverage(fills, portfolio or []),
        "equity_history": [
            [int(x[0]), number(x[1])]
            for x in all_time.get("accountValueHistory", [])
            if isinstance(x, list) and len(x) > 1
        ],
        "pnl_history": [
            [int(x[0]), number(x[1])]
            for x in all_time.get("pnlHistory", [])
            if isinstance(x, list) and len(x) > 1
        ],
        "portfolio_pnl_usdc": money(number(all_time.get("pnlHistory", [[0, 0]])[-1][1]))
        if all_time.get("pnlHistory")
        else None,
        "volume_usdc": money(number(all_time.get("vlm"))) if all_time else None,
        "max_drawdown_percent": round(max_drawdown, 2),
        "total_equity_usdc": money(equity_history[-1]) if equity_history else None,
        "trading_equity_usdc": money(equity_history[-1]) if equity_history else None,
    }
    if state:
        summary = state.get("marginSummary", {})
        account_value = number(summary.get("accountValue"))
        exposure = number(summary.get("totalNtlPos"))
        leverages = [
            number(x.get("position", {}).get("leverage", {}).get("value"))
            for x in state.get("assetPositions", [])
            if isinstance(x, dict)
        ]
        result["account_value_usdc"] = money(account_value)
        result["withdrawable_usdc"] = money(number(state.get("withdrawable")))
        result["effective_leverage"] = (
            round(exposure / account_value, 2) if account_value else None
        )
        # Current leverage reflects the leverage set on currently open orders
        # and positions. Historical/combined leverage reflects all trades ever
        # made (near the trader's usual setting, e.g. 25x if they always trade 25x).
        result["account_leverage"] = (
            max(leverages) if leverages else result.get("historical_effective_leverage")
        )
        result["history_leverage"] = result.get("historical_effective_leverage")
    return result


def display_time(ms: int | None) -> str:
    if not ms:
        return "n/a"
    age = max(0, datetime.now(UTC).timestamp() - ms / 1000)
    if age < 3600:
        return f"{int(age / 60)} minutes ago"
    if age < 86_400:
        return f"{int(age / 3600)} hours ago"
    return f"{int(age / 86_400)} days ago"
