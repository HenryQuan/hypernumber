from __future__ import annotations

import math
from collections import defaultdict, deque
from datetime import datetime, timezone
from statistics import mean, pstdev


def number(value, default=0.0) -> float:
    try: return float(value)
    except (TypeError, ValueError): return default


def money(value: float | None) -> float | None:
    return round(value, 2) if value is not None else None


def _holding_hours(fills: list[dict]) -> float | None:
    lots: dict[str, deque[tuple[float, float, int]]] = defaultdict(deque); durations = []
    for fill in fills:
        coin, qty = str(fill.get("coin", "?")), abs(number(fill.get("sz")))
        if not qty: continue
        sign = 1 if str(fill.get("side", "")).lower() in {"b", "buy", "long", "open long"} else -1
        book = lots[coin]
        while qty and book and book[0][1] * sign < 0:
            old_sign, old_qty, opened = book[0]; matched = min(qty, old_qty)
            durations.append((matched, max(0, int(fill.get("time", opened)) - opened)))
            qty -= matched; old_qty -= matched; book.popleft()
            if old_qty: book.appendleft((old_sign, old_qty, opened))
        if qty: book.append((sign, qty, int(fill.get("time", 0))))
    total = sum(q for q, _ in durations)
    return sum(q * ms for q, ms in durations) / total / 3_600_000 if total else None


def _monthly_growth(portfolio: list) -> dict[str, float]:
    by_month = defaultdict(list)
    for item in portfolio:
        if not isinstance(item, list) or len(item) < 2 or not isinstance(item[1], dict): continue
        for point in item[1].get("accountValueHistory", []):
            if isinstance(point, list) and len(point) >= 2 and number(point[1]):
                dt = datetime.fromtimestamp(int(point[0]) / 1000, timezone.utc)
                by_month[dt.strftime("%Y-%m")].append((int(point[0]), number(point[1])))
    result = {}
    maximum_equity = max((value for values in by_month.values() for _, value in values), default=0)
    for month, values in by_month.items():
        values.sort()
        opening, closing = values[0][1], values[-1][1]
        # The first history point can be a zero/near-zero seed balance. Do not
        # turn growth from that artificial baseline into a giant percentage.
        if opening and opening >= maximum_equity * 0.01:
            result[month] = round((closing / opening - 1) * 100, 2)
    return result


def _historical_leverage(fills: list[dict], portfolio: list) -> float | None:
    history = []
    for item in portfolio:
        if isinstance(item, list) and item and item[0] == "allTime" and isinstance(item[1], dict):
            history = item[1].get("accountValueHistory", [])
    history = sorted((int(x[0]), number(x[1])) for x in history if isinstance(x, list) and len(x) > 1)
    max_equity = max((x[1] for x in history), default=0)
    positions = defaultdict(float); maximum = None
    for fill in sorted(fills, key=lambda x: int(x.get("time", 0))):
        coin = str(fill.get("coin", "?")); side = str(fill.get("side", "")).lower()
        positions[coin] += (1 if side in {"b", "buy"} else -1) * abs(number(fill.get("sz")))
        price = number(fill.get("px")); timestamp = int(fill.get("time", 0))
        equity = next((v for t, v in reversed(history) if t <= timestamp), 0)
        if equity >= max_equity * 0.01 and equity:
            exposure = sum(abs(q) * price for q in positions.values())
            maximum = max(maximum or 0, exposure / equity)
    return round(maximum, 2) if maximum is not None else None


def calculate(fills: list[dict], state: dict | None = None, portfolio: list | None = None, funding: list[dict] | None = None) -> dict:
    fills = sorted(fills, key=lambda x: int(x.get("time", 0))); realized = []
    for fill in fills:
        if "closedPnl" not in fill or number(fill.get("closedPnl")) == 0: continue
        realized.append({"pnl": number(fill.get("closedPnl")) - abs(number(fill.get("fee"))), "time": int(fill.get("time", 0)), "side": str(fill.get("side", "")).lower()})
    pnls = [x["pnl"] for x in realized]; wins = [x for x in pnls if x > 0]; losses = [x for x in pnls if x < 0]
    gross_profit, gross_loss = sum(wins), sum(losses); longest_win = longest_loss = run_win = run_loss = 0
    win_run_profit = loss_run_profit = max_win_run_profit = max_loss_run_profit = 0.0
    for value in pnls:
        if value > 0:
            run_win += 1; run_loss = 0; win_run_profit += value; loss_run_profit = 0; longest_win = max(longest_win, run_win); max_win_run_profit = max(max_win_run_profit, win_run_profit)
        elif value < 0:
            run_loss += 1; run_win = 0; loss_run_profit += value; win_run_profit = 0; longest_loss = max(longest_loss, run_loss); max_loss_run_profit = min(max_loss_run_profit, loss_run_profit)
        else: run_win = run_loss = 0; win_run_profit = loss_run_profit = 0
    times = [x["time"] for x in realized]; span_weeks = ((max(times)-min(times))/86_400_000/7) if len(times) > 1 else 0
    deviation = pstdev(pnls) if len(pnls) > 1 else None; sharpe = mean(pnls) / deviation * math.sqrt(len(pnls)) if deviation else None
    long_trades = sum(x["side"] in {"a", "sell"} for x in realized); short_trades = sum(x["side"] in {"b", "buy"} for x in realized)
    long_wins = sum(x["side"] in {"a", "sell"} and x["pnl"] > 0 for x in realized); short_wins = sum(x["side"] in {"b", "buy"} and x["pnl"] > 0 for x in realized)
    funding_total = sum(number((x.get("delta") or {}).get("usdc", 0)) if isinstance(x.get("delta"), dict) else number(x.get("delta", x.get("usdc"))) for x in (funding or [])); fees = sum(abs(number(f.get("fee"))) for f in fills)
    all_time = next((x[1] for x in (portfolio or []) if isinstance(x, list) and x and x[0] == "allTime" and isinstance(x[1], dict)), {})
    equity_history = [number(x[1]) for x in all_time.get("accountValueHistory", []) if isinstance(x, list) and len(x) > 1]
    peak = equity_history[0] if equity_history else 0; max_drawdown = 0.0
    for equity in equity_history:
        peak = max(peak, equity)
        if peak: max_drawdown = max(max_drawdown, (peak - equity) / peak * 100)
    result = {
        "trades": len(pnls), "profit_trades": len(wins), "loss_trades": len(losses), "best_trade_usdc": money(max(pnls) if pnls else None), "worst_trade_usdc": money(min(pnls) if pnls else None),
        "gross_profit_usdc": money(gross_profit), "gross_loss_usdc": money(gross_loss), "fees_usdc": money(fees), "funding_usdc": money(funding_total), "net_profit_usdc": money(sum(pnls) + funding_total),
        "maximum_consecutive_wins": longest_win, "maximum_consecutive_wins_usdc": money(max_win_run_profit), "maximal_consecutive_profit_usdc": money(max_win_run_profit), "maximum_consecutive_losses": longest_loss, "maximal_consecutive_loss_usdc": money(max_loss_run_profit),
        "sharpe_ratio": round(sharpe, 2) if sharpe is not None else None, "trading_activity_percent": round(len(fills) / max(1, (max(times)-min(times))/86_400_000) * 100, 2) if len(times) > 1 else None, "trades_per_week": round(len(pnls)/span_weeks, 2) if span_weeks else None,
        "avg_holding_hours": round(_holding_hours(fills), 2) if _holding_hours(fills) is not None else None, "long_trades": long_trades, "short_trades": short_trades, "long_wins": long_wins, "short_wins": short_wins,
        "profit_factor": round(gross_profit / abs(gross_loss), 2) if gross_loss else None, "expected_payoff_usdc": money(sum(pnls)/len(pnls)) if pnls else None, "average_profit_usdc": money(gross_profit/len(wins)) if wins else None, "average_loss_usdc": money(gross_loss/len(losses)) if losses else None,
        "standard_deviation_usdc": money(deviation), "latest_trade_ms": times[-1] if times else None, "fills": len(fills), "monthly_growth": _monthly_growth(portfolio or []),
        "historical_effective_leverage": _historical_leverage(fills, portfolio or []),
        "portfolio_pnl_usdc": money(number(all_time.get("pnlHistory", [[0, 0]])[-1][1])) if all_time.get("pnlHistory") else None,
        "volume_usdc": money(number(all_time.get("vlm"))) if all_time else None, "max_drawdown_percent": round(max_drawdown, 2),
        "total_equity_usdc": money(equity_history[-1]) if equity_history else None, "trading_equity_usdc": money(equity_history[-1]) if equity_history else None,
    }
    if state:
        summary = state.get("marginSummary", {})
        account_value = number(summary.get("accountValue")); exposure = number(summary.get("totalNtlPos"))
        leverages = [number(x.get("position", {}).get("leverage", {}).get("value")) for x in state.get("assetPositions", []) if isinstance(x, dict)]
        result["account_value_usdc"] = money(account_value); result["withdrawable_usdc"] = money(number(state.get("withdrawable")))
        result["effective_leverage"] = round(exposure / account_value, 2) if account_value else None
        result["account_leverage"] = max(leverages) if leverages else result.get("historical_effective_leverage")
    return result


def display_time(ms: int | None) -> str:
    if not ms: return "n/a"
    age = max(0, datetime.now(timezone.utc).timestamp() - ms / 1000)
    if age < 3600: return f"{int(age/60)} minutes ago"
    if age < 86_400: return f"{int(age/3600)} hours ago"
    return f"{int(age/86_400)} days ago"
