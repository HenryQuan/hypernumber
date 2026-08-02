# Hyperliquid Numbers

100% Flutter (Dart) port of the `hyperliquid_tracker` Python/uv project. The
Python implementation is reference-only: all analytics, API calls and
formatting live in Dart, so the app runs on Android, iOS, web, Windows, macOS
and Linux.

## Run

```bash
cd app
flutter pub get
flutter run            # pick a device; -d chrome for web
flutter run -d chrome  # web
```

Enter any public Hyperliquid wallet address to build the trading report from
the public Info API (no API key required). Same metrics as the CLI: realized
trades, win/loss, gross and average P&L, profit factor, expected payoff,
Sharpe, streaks, direction split, activity, holding time, latest trade,
account value, equity/growth charts.

## Web JSON via URL

The web build serves the report and raw JSON from the URL (SPA hash routing,
no server config needed):

```
https://<host>/#/<address>         dashboard for the address
https://<host>/#/<address>/json    raw JSON report
https://<host>/?address=<address>&json=1
```

Query params also work. The JSON screen has copy + download buttons.

## Parity with the Python reference

`test/analytics_test.dart` locks the Dart port 1:1 against the Python
implementation's exact output (54 result keys, nested histories and growth
maps). Regenerate the fixture with:

```bash
cd ..
uv run python tool/gen_fixture.py
```

## Structure

- `lib/api/hyperliquid_client.dart` — port of `api.py` (Info API client)
- `lib/analytics/analytics.dart` — port of `analytics.py` + CLI formatting helpers
- `lib/screens/` — home / loading / report / JSON views (fl_chart line charts)
- `lib/main.dart` — entry point + web URL routing
- `lib/download*.dart` — web-only JSON file download
