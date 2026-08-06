# Hyperliquid Numbers

100% Flutter (Dart) app that builds a trading report for any public
Hyperliquid wallet address from the public Info API (no API key required).
Runs on Android, iOS, web, Windows, macOS and Linux.

## Run

```bash
cd app
flutter pub get
flutter run            # pick a device; -d chrome for web
flutter run -d chrome  # web
```

Enter any public Hyperliquid wallet address to build the trading report from
the public Info API (no API key required). Metrics: realized trades, win/loss,
gross and average P&L, profit factor, expected payoff, Sharpe, streaks,
direction split, activity, holding time, latest trade, account value,
equity/growth charts.

## Local CLI

A Dart CLI shares the app's client + analytics (ASCII charts included):

```bash
cd app
dart run tool/report.dart 0xF297cd479123064997eEBbc675e41Eb13aE325E7
# options: --since YYYY-MM-DD, --api URL, --json
```

`test/report_cli_test.dart` locks the CLI text output against the committed
reference fixture.

## Open an address via URL (web)

Visiting the site with an address in the URL auto-loads that wallet's
report:

```
https://<host>/<address>            dashboard (auto-loads)
https://<host>/#/<address>          hash equivalent
https://<host>/?address=<address>
```

Real paths need the host to serve `index.html` for all paths: the
`flutter run` dev server does this out of the box; static hosts need a
rewrite rule (e.g. Netlify `_redirects` / Vercel `vercel.json` sending
`/*` to `/index.html`). Hash routes work on any host with zero config.

## Analytics regression

`test/analytics_test.dart` checks the analytics against the committed
reference fixture (`test/fixtures/report.json`, 54 result keys with nested
histories and growth maps). `test/report_cli_test.dart` locks the CLI text
output against `test/fixtures/report_cli.txt`.

## Structure

- `lib/api/hyperliquid_client.dart` — Hyperliquid Info API client
- `lib/analytics/analytics.dart` — analytics + formatting helpers
- `lib/screens/` — home / loading / report views (fl_chart line charts)
- `lib/main.dart` — entry point + web URL routing
