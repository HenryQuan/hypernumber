from __future__ import annotations
import argparse, json, re, sys
from datetime import datetime, timezone
from .analytics import calculate, display_time
from .api import HyperliquidClient, HyperliquidError
ADDRESS = re.compile(r"^0x[0-9a-fA-F]{40}$")

def fmt(v): return "n/a" if v is None else f"{v:,.2f}" if isinstance(v, float) else str(v)
def multiple(v): return f"{fmt(v)}x" if v is not None else "n/a"

def print_report(address, s):
    total=s['trades']; wp=s['profit_trades']/total*100 if total else 0; lp=s['loss_trades']/total*100 if total else 0; sides=s['long_trades']+s['short_trades'];
    rows=[
      ("Trades",total,"Profitability",f"{s['profit_trades']} ({wp:.2f}%) / {s['loss_trades']} ({lp:.2f}%)"),
      ("Average Win",f"{fmt(s['average_profit_usdc'])} USDC","Average Loss",f"{fmt(s['average_loss_usdc'])} USDC"),
      ("Fees",f"-{fmt(s['fees_usdc'])} USDC","Funding",f"{fmt(s['funding_usdc'])} USDC"),
      ("Net P&L",f"{fmt(s['net_profit_usdc'])} USDC","Portfolio PNL",f"{fmt(s['portfolio_pnl_usdc'])} USDC"),
      ("Volume",f"{fmt(s['volume_usdc'])} USDC","Max Drawdown",f"{fmt(s['max_drawdown_percent'])}%"),
      ("Total Equity",f"{fmt(s['total_equity_usdc'])} USDC","Trading Equity",f"{fmt(s['trading_equity_usdc'])} USDC"),
      ("Current Leverage",multiple(s.get('account_leverage')),"Effective Leverage",multiple(s.get('effective_leverage'))),
      ("Longs Won",f"({s['long_wins']}/{s['long_trades']}) {s['long_wins']/s['long_trades']*100:.0f}%" if s['long_trades'] else "n/a","Shorts Won",f"({s['short_wins']}/{s['short_trades']}) {s['short_wins']/s['short_trades']*100:.0f}%" if s['short_trades'] else "n/a"),
      ("Best Trade",f"{fmt(s['best_trade_usdc'])} USDC","Worst Trade",f"{fmt(s['worst_trade_usdc'])} USDC"),
      ("Avg. Trade Length",f"{fmt(s['avg_holding_hours'])} hours","Profit Factor",fmt(s['profit_factor'])), 
      ("Standard Deviation",f"{fmt(s['standard_deviation_usdc'])} USDC","Sharpe Ratio",fmt(s['sharpe_ratio'])),
      ("Expectancy",f"{fmt(s['expected_payoff_usdc'])} USDC","Trading Activity",f"{fmt(s['trading_activity_percent'])}%"),
      ("Trades per Week",fmt(s['trades_per_week']),"Latest Trade",display_time(s['latest_trade_ms'])),

      ("Maximum Wins",f"{s['maximum_consecutive_wins']} ({fmt(s['maximum_consecutive_wins_usdc'])} USDC)","Maximum Losses",f"{s['maximum_consecutive_losses']} ({fmt(s['maximal_consecutive_loss_usdc'])} USDC)"),
      ]
    print(f"Hyperliquid trading report\n{address}\n")
    for a,b,c,d in rows:
        if c: print(f"{a:<22}: {b:<28} {c:<22}: {d}")
        else: print(f"{a:<22}: {b}")
    growth=s.get('monthly_growth',{})
    if growth:
        print("\nGrowth in Signals")
        print(f"{'Year':<7}" + "".join(f"{m:>9}" for m in ('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec')) + f"{'Year':>10}")
        years=sorted({x[:4] for x in growth})
        for year in years:
            last_month=max((int(key[5:]) for key, value in growth.items() if key.startswith(year) and value != 0), default=0)
            vals=[growth.get(f"{year}-{m:02d}") if m <= last_month else None for m in range(1,13)]
            total_growth=(__import__('math').prod(1 + v / 100 for v in vals if v is not None) - 1) * 100 if any(v is not None for v in vals) else 0
            cells="".join(f"{v:>8.2f}%" if v is not None else f"{'-':>9}" for v in vals)
            print(f"{year:<7}"+cells+f"{total_growth:>9.2f}%")
        total_growth=(__import__('math').prod(1 + v / 100 for v in growth.values() if v is not None) - 1) * 100 if growth else 0
        print(f"{'Total':<7}{'':>108}{total_growth:>9.2f}%")

def main(argv=None):
    p=argparse.ArgumentParser(description="Generate a trading report for any public Hyperliquid address"); p.add_argument("address"); p.add_argument("--json",action="store_true",dest="as_json"); p.add_argument("--since"); p.add_argument("--api",default="https://api.hyperliquid.xyz",help=argparse.SUPPRESS); a=p.parse_args(argv)
    if not ADDRESS.fullmatch(a.address): p.error("address must be a 0x-prefixed 40-hex-character address")
    start=None
    if a.since:
        try: start=int(datetime.strptime(a.since,"%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp()*1000)
        except ValueError: p.error("--since must be YYYY-MM-DD")
    try:
        c=HyperliquidClient(a.api); fills=c.fills(a.address,start); stats=calculate(fills,c.clearinghouse_state(a.address),c.portfolio(a.address),c.funding(a.address,start))
    except HyperliquidError as exc: print(str(exc),file=sys.stderr); return 1
    if a.as_json: print(json.dumps({"address":a.address,**stats},indent=2))
    else: print_report(a.address,stats)
    return 0

if __name__ == "__main__": raise SystemExit(main())
