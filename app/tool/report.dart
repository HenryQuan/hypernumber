/// Local CLI sharing the app's client + analytics.
///
/// Usage (from app/):
///   dart run tool/report.dart <address> [--since YYYY-MM-DD] [--api URL] [--json]
///
/// Output is locked byte-for-byte by test/report_cli_test.dart.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:hypernumber/analytics/analytics.dart';
import 'package:hypernumber/api/hyperliquid_client.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

final _addressRe = RegExp(r'^0x[0-9a-fA-F]{40}$');

Future<void> main(List<String> args) async {
  String? address;
  int? sinceMs;
  var api = 'https://api.hyperliquid.xyz';
  var asJson = false;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--json') {
      asJson = true;
    } else if (a == '--since') {
      if (i + 1 >= args.length) {
        stderr.writeln('--since requires YYYY-MM-DD');
        exitCode = 2;
        return;
      }
      final d = DateTime.tryParse(args[++i]);
      if (d == null) {
        stderr.writeln('--since must be YYYY-MM-DD');
        exitCode = 2;
        return;
      }
      sinceMs = DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch;
    } else if (a == '--api') {
      if (i + 1 >= args.length) {
        stderr.writeln('--api requires a URL');
        exitCode = 2;
        return;
      }
      api = args[++i];
    } else if (a.startsWith('--')) {
      stderr.writeln('unknown option: $a');
      exitCode = 2;
      return;
    } else if (address == null) {
      address = a;
    } else {
      stderr.writeln('unexpected argument: $a');
      exitCode = 2;
      return;
    }
  }
  if (address == null || !_addressRe.hasMatch(address)) {
    stderr.writeln('address must be a 0x-prefixed 40-hex-character address');
    exitCode = 2;
    return;
  }
  try {
    final client = HyperliquidClient(baseUrl: api);
    void progress(String kind, int page) =>
        stderr.writeln('  fetching $kind page $page');
    final fills =
        await client.fills(address, startMs: sinceMs, onPage: progress);
    final state = await client.clearinghouseState(address);
    final portfolio = await client.portfolio(address);
    final (funding, _) =
        await client.funding(address, startMs: sinceMs, onPage: progress);
    final stats = calculate(fills,
        state: state, portfolio: portfolio, funding: funding);
    stderr.writeln('Presenting results...');
    if (asJson) {
      stdout.writeln(const JsonEncoder.withIndent('  ')
          .convert({'address': address, ...stats}));
    } else {
      stdout.write(reportText(address, stats));
    }
  } on HyperliquidError catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  }
}

/// Python-style "%.2f" formatting: round half to even, preserve -0.00.
String _pyFmt2(double v, {int pad = 0}) {
  final scaled = v * 100;
  final floor = scaled.floor();
  final diff = scaled - floor;
  final rounded = diff < 0.5
      ? floor
      : diff > 0.5
          ? floor + 1
          : (floor.isEven ? floor : floor + 1);
  final r = rounded == 0 && v < 0 ? -0.0 : rounded / 100;
  final s = r.toStringAsFixed(2);
  return pad > 0 ? s.padLeft(pad) : s;
}

/// Port of cli.py print_report + the ASCII charts. Byte-identical to the
/// Python output ([now] only exists to keep the fixture test deterministic).
String reportText(String address, Map<String, dynamic> s, {DateTime? now}) {
  final sb = StringBuffer();
  final total = (s['trades'] as num?)?.toInt() ?? 0;
  final profitTrades = (s['profit_trades'] as num?)?.toInt() ?? 0;
  final lossTrades = (s['loss_trades'] as num?)?.toInt() ?? 0;
  final wp = total != 0 ? profitTrades / total * 100 : 0.0;
  final lp = total != 0 ? lossTrades / total * 100 : 0.0;

  String usdc(dynamic v) => '${fmtValue(v)} USDC';
  String pct(dynamic v) => '${fmtValue(v)}%';

  String sideStats(dynamic wins, dynamic trades) {
    final t = (trades as num?)?.toInt() ?? 0;
    if (t == 0) return 'n/a';
    final w = (wins as num?)?.toInt() ?? 0;
    return '($w/$t) ${(w / t * 100).toStringAsFixed(0)}%';
  }

  const freqLabels = {'D': 'Daily Avg', 'W': 'Weekly Avg', 'M': 'Monthly Avg'};
  final freq = freqLabels[s['period_freq']] ?? 'Period Avg';

  final rows = <List<String>>[
    ['Trades', '$total', 'Win Rate',
        'Wins $profitTrades (${_pyFmt2(wp)}%) / Losses $lossTrades (${_pyFmt2(lp)}%)'],
    ['Average Win', usdc(s['average_profit_usdc']), 'Average Loss',
        usdc(s['average_loss_usdc'])],
    ['Fees', '-${fmtValue(s['fees_usdc'])} USDC', 'Funding',
        usdc(s['funding_usdc'])],
    ['Deposits', usdc(s['deposits_usdc']), 'Withdrawals',
        usdc(s['withdrawals_usdc'])],
    ['Net P&L', usdc(s['net_profit_usdc']), 'Portfolio PNL',
        '${fmtValue(s['portfolio_pnl_usdc'])} USDC (${compact(s['portfolio_pnl_usdc'])})'],
    ['Volume', usdc(s['volume_usdc']), 'Max Drawdown',
        pct(s['max_drawdown_percent'])],
    ['Total Equity', usdc(s['total_equity_usdc']), 'Trading Equity',
        usdc(s['trading_equity_usdc'])],
    ['Current Leverage', multiple(s['account_leverage']), 'History Leverage',
        multiple(s['history_leverage'])],
    ['Longs Won', sideStats(s['long_wins'], s['long_trades']), 'Shorts Won',
        sideStats(s['short_wins'], s['short_trades'])],
    ['Best Trade', usdc(s['best_trade_usdc']), 'Worst Trade',
        usdc(s['worst_trade_usdc'])],
    ['Avg. Trade Length', '${fmtValue(s['avg_holding_hours'])} hours',
        'Profit Factor', fmtValue(s['profit_factor'])],
    ['Standard Deviation', usdc(s['standard_deviation_usdc']), 'Sharpe Ratio',
        fmtValue(s['sharpe_ratio'])],
    ['Sortino', fmtValue(s['sortino_ratio']), 'Recovery Factor',
        fmtValue(s['recovery_factor'])],
    ['Total Return', pct(s['total_return_percent']), 'Peak Return',
        pct(s['peak_return_percent'])],
    [freq, pct(s['period_avg_percent']), 'UPI', fmtValue(s['upi'])],
    ['Expectancy', usdc(s['expected_payoff_usdc']), 'Trading Activity',
        pct(s['trading_activity_percent'])],
    ['Trades per Week', fmtValue(s['trades_per_week']), 'Latest Trade',
        displayTime((s['latest_trade_ms'] as num?)?.toInt(), now: now)],
    ['Maximum Wins',
        '${s['maximum_consecutive_wins']} (${fmtValue(s['maximum_consecutive_wins_usdc'])} USDC)',
        'Maximum Losses',
        '${s['maximum_consecutive_losses']} (${fmtValue(s['maximal_consecutive_loss_usdc'])} USDC)'],
  ];

  sb.writeln('Hyperliquid trading report');
  sb.writeln(address);
  sb.writeln();
  for (final r in rows) {
    final a = r[0], b = r[1], c = r[2], d = r[3];
    if (c.isNotEmpty) {
      sb.writeln('${a.padRight(22)}: ${b.padRight(28)} ${c.padRight(22)}: $d');
    } else {
      sb.writeln('${a.padRight(22)}: $b');
    }
  }
  sb.writeln();
  sb.writeln('Equity History (USDC)');
  sb.writeln(equityChart(_numPairs(s['equity_history'])));
  sb.writeln();
  sb.writeln('Equity Movement');
  sb.writeln(movementChart(_numPairs(s['equity_history'])));
  final growth = s['monthly_growth'];
  if (growth is Map && growth.isNotEmpty) {
    final g = growth.cast<String, double>();
    sb.writeln();
    sb.writeln('Growth History');
    sb.writeln('${'Year'.padRight(10)}'
        '${_months.map((m) => m.padLeft(9)).join()}'
        '${'Year'.padLeft(10)}');
    final years = g.keys.map((k) => k.substring(0, 4)).toSet().toList()..sort();
    for (final year in years) {
      final vals = <double?>[
        for (var m = 1; m <= 12; m++) g['$year-${m.toString().padLeft(2, '0')}'],
      ];
      final totalGrowth = combineGrowth(vals);
      final cells = vals
          .map((v) =>
              v == null ? 'x'.padLeft(9) : '${v.toStringAsFixed(2).padLeft(8)}%')
          .join();
      sb.writeln('${year.padRight(10)}$cells${_pyFmt2(totalGrowth, pad: 9)}%');
    }
    final grandTotal = combineGrowth(g.values);
    sb.writeln('${'Total'.padRight(10)}'
        '${List.filled(12, '         ').join()}'
        '${'${compact(grandTotal)}%'.padLeft(10)}');
    sb.writeln();
    sb.writeln('Growth Movement');
    sb.writeln(movementChart(_numPairs(s['pnl_history'])));
  }
  return sb.toString();
}

List<List<num>> _numPairs(dynamic value) {
  if (value is! List) return const [];
  return [
    for (final x in value)
      if (x is List && x.length > 1) [number(x[0]).toInt(), number(x[1])],
  ];
}

/// Python round(): ties to even.
int pyRound(double x) {
  final floor = x.floor();
  final diff = x - floor;
  if (diff < 0.5) return floor;
  if (diff > 0.5) return floor + 1;
  return floor.isEven ? floor : floor + 1;
}

/// Port of cli.py equity_chart: month-end equity calendar table.
String equityChart(List<List<num>> points) {
  if (points.isEmpty) return 'n/a';
  final monthly = <String, double>{};
  for (final p in points) {
    final dt = DateTime.fromMillisecondsSinceEpoch(p[0].toInt(), isUtc: true);
    monthly['${dt.year}-${dt.month}'] = number(p[1]);
  }
  final years =
      monthly.keys.map((k) => int.parse(k.split('-')[0])).toSet().toList()
        ..sort();
  final lines = <String>[
    '${'Year'.padRight(10)}${_months.map((m) => m.padLeft(9)).join()}',
    for (final year in years)
      '${year.toString().padRight(10)}'
          '${[for (var m = 1; m <= 12; m++) monthly['$year-$m']]
              .map((v) => v == null ? 'x'.padLeft(9) : compact(v).padLeft(9))
              .join()}',
  ];
  return lines.join('\n');
}

/// Python bisect_left over ints with a float probe.
int bisectLeftNum(List<int> a, double x) {
  var lo = 0, hi = a.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (a[mid] < x) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Port of cli.py draw_movement_chart: 10-row ASCII line chart.
String movementChart(List<List<num>> points) {
  if (points.isEmpty) return 'no equity data yet';
  const width = 110;
  final items = [...points]..sort((a, b) => a[0].compareTo(b[0]));
  final tsList = [for (final p in items) p[0] as int];
  final values = [for (final p in items) number(p[1])];
  final t0 = tsList.first, t1 = tsList.last;
  var lo = double.infinity, hi = double.negativeInfinity;
  for (final v in values) {
    lo = math.min(lo, v);
    hi = math.max(hi, v);
  }
  const rows = 10;

  int rowOf(double v) {
    if (hi == lo) return rows ~/ 2;
    return rows - 1 - pyRound((v - lo) / (hi - lo) * (rows - 1));
  }

  double valueAt(double ts) {
    final i = bisectLeftNum(tsList, ts);
    if (i == 0) return values[0];
    if (i >= tsList.length) return values.last;
    final before = ts - tsList[i - 1];
    final after = tsList[i] - ts;
    return before <= after ? values[i - 1] : values[i];
  }

  final grid = List.generate(rows, (_) => List.filled(width, ' '));
  int? prevRow;
  for (var c = 0; c < width; c++) {
    final ts = t0 + (t1 - t0) * (c / (width - 1));
    final r = rowOf(valueAt(ts));
    grid[r][c] = '-';
    if (prevRow != null && prevRow != r) {
      for (var k = math.min(prevRow, r) + 1; k < math.max(prevRow, r); k++) {
        grid[k][c] = '|';
      }
    }
    prevRow = r;
  }

  final labels = List.filled(width, ' ');
  final step = math.max(1, width ~/ 7);
  for (var c = 0; c < width; c += step) {
    final ts = t0 + (t1 - t0) * (c / (width - 1));
    final dt = DateTime.fromMillisecondsSinceEpoch(ts.toInt(), isUtc: true);
    final label = '${_months[dt.month - 1]} ${dt.year}';
    final start = math.max(0, c - label.length ~/ 2);
    for (var j = 0; j < label.length; j++) {
      if (start + j < width) labels[start + j] = label[j];
    }
  }
  final lines = <String>[];
  for (var r = 0; r < rows; r++) {
    var line = grid[r].join().trimRight();
    if (r == 0) line += '   max ${compact(hi)}';
    lines.add(line.isEmpty ? ' ' : line);
  }
  lines.add(labels.join().trimRight());
  return lines.join('\n');
}
