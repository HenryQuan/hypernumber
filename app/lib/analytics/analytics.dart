import 'dart:math' as math;

/// Analytics for Hyperliquid trading reports.
///
/// All function names, result keys and numeric semantics match the original
/// reference implementation 1:1; test/analytics_test.dart locks output
/// against the committed fixture (test/fixtures/report.json).

/// Port of `number()`: coerce anything to double, falling back to [defaultValue].
double number(dynamic value, [double defaultValue = 0.0]) {
  if (value == null) return defaultValue;
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? defaultValue;
}

/// Port of `money()`: round to 2 decimals (None stays None).
double? money(double? value) {
  if (value == null) return null;
  return round2(value);
}

/// Round to 2 decimals like Python's round(x, 2): round half to even and
/// preserve negative zero (e.g. round(-0.004, 2) -> -0.0).
double round2(double v) {
  final scaled = v * 100;
  final floor = scaled.floor();
  final diff = scaled - floor;
  final rounded = diff < 0.5
      ? floor
      : diff > 0.5
          ? floor + 1
          : (floor.isEven ? floor : floor + 1);
  final result = rounded / 100;
  return result == 0 && v < 0 ? -0.0 : result;
}

double mean(List<double> xs) => xs.fold(0.0, (a, b) => a + b) / xs.length;

/// Population standard deviation (statistics.pstdev).
double? pstdev(List<double> xs) {
  if (xs.isEmpty) return null;
  final m = mean(xs);
  final variance = xs.fold(0.0, (a, b) => a + (b - m) * (b - m)) / xs.length;
  return math.sqrt(variance);
}

int bisectLeft(List<int> a, int x) {
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

int bisectRight(List<int> a, int x) {
  var lo = 0, hi = a.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (a[mid] <= x) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Port of `_holding_hours`: FIFO-matched holding time at the coin level.
/// Lots are matched when the stored side is opposite the incoming fill side
/// (buy closes a short lot, sell closes a long lot).
double? holdingHours(List<Map<String, dynamic>> fills) {
  final lots = <String, List<List<double>>>{};
  final durations = <List<double>>[]; // [matched qty, ms held]
  for (final fill in fills) {
    final coin = '${fill['coin'] ?? '?'}';
    var qty = number(fill['sz']).abs();
    if (qty == 0) continue;
    final side = '${fill['side'] ?? ''}'.toLowerCase();
    final sign = (side == 'b' ||
            side == 'buy' ||
            side == 'long' ||
            side == 'open long')
        ? 1.0
        : -1.0;
    final book = lots.putIfAbsent(coin, () => <List<double>>[]);
    while (qty > 0 && book.isNotEmpty && book.first[0] * sign < 0) {
      final oldSign = book.first[0];
      final oldQty = book.first[1];
      final opened = book.first[2];
      final matched = qty < oldQty ? qty : oldQty;
      final t = number(fill['time'], opened);
      durations.add([matched, (t - opened) < 0 ? 0.0 : t - opened]);
      qty -= matched;
      final remaining = oldQty - matched;
      book.removeAt(0);
      if (remaining != 0) {
        book.insert(0, [oldSign, remaining, opened]);
      }
    }
    if (qty != 0) {
      book.add([sign, qty, number(fill['time'])]);
    }
  }
  var total = 0.0;
  for (final d in durations) {
    total += d[0];
  }
  if (total == 0) return null;
  var weighted = 0.0;
  for (final d in durations) {
    weighted += d[0] * d[1];
  }
  return weighted / total / 3_600_000;
}

/// Port of `_pnl_density`: approximate pnl snapshots per day or per week.
double pnlDensity(List<dynamic> portfolio, {bool perDay = false}) {
  var points = <List>[];
  for (final item in portfolio) {
    if (item is List &&
        item.isNotEmpty &&
        item[0] == 'allTime' &&
        item[1] is Map) {
      points = [];
      final hist = (item[1] as Map)['pnlHistory'];
      if (hist is List) {
        for (final x in hist) {
          if (x is List && x.length > 1) points.add(x);
        }
      }
      break;
    }
  }
  if (points.length < 2) return 0.0;
  final span = number(points.last[0]).toInt() - number(points.first[0]).toInt();
  final denominator = perDay ? 86_400_000 : 604_800_000;
  final periods = span / denominator;
  return periods > 0 ? points.length / periods : 0.0;
}

/// Port of `_net_flows`: estimate total deposits and withdrawals (USDC).
(double, double) netFlows(List<dynamic> portfolio) {
  final equity = <List<num>>[];
  final pnl = <List<num>>[];
  for (final item in portfolio) {
    if (item is! List ||
        item.isEmpty ||
        item[0] != 'allTime' ||
        item[1] is! Map) {
      continue;
    }
    final bucket = item[1] as Map;
    final ah = bucket['accountValueHistory'];
    if (ah is List) {
      for (final point in ah) {
        if (point is List && point.length > 1) {
          equity.add([number(point[0]).toInt(), number(point[1])]);
        }
      }
    }
    final ph = bucket['pnlHistory'];
    if (ph is List) {
      for (final point in ph) {
        if (point is List && point.length > 1) {
          pnl.add([number(point[0]).toInt(), number(point[1])]);
        }
      }
    }
    break;
  }
  equity.sort((a, b) => a[0].compareTo(b[0]));
  pnl.sort((a, b) => a[0].compareTo(b[0]));
  final pnlTs = [for (final p in pnl) p[0] as int];

  double pnlAt(int ts) {
    final i = bisectRight(pnlTs, ts) - 1;
    return i >= 0 ? pnl[i][1].toDouble() : 0.0;
  }

  var deposits = 0.0, withdrawals = 0.0;
  for (var i = 1; i < equity.length; i++) {
    final flow = (equity[i][1] - equity[i - 1][1]) -
        (pnlAt(equity[i][0] as int) - pnlAt(equity[i - 1][0] as int));
    if (flow > 0) {
      deposits += flow;
    } else {
      withdrawals += -flow;
    }
  }
  return (deposits, withdrawals);
}

/// ISO year and ISO week number (Python's date.isocalendar()).
(int, int) _isoYearWeek(DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  // Dart weekday matches ISO: Monday=1 .. Sunday=7.
  final thursday = d.add(Duration(days: 4 - d.weekday));
  final year = thursday.year;
  final first = DateTime.utc(year, 1, 1);
  final week = (thursday.difference(first).inDays / 7).floor() + 1;
  return (year, week);
}

String _pad2(int v) => v.toString().padLeft(2, '0');

/// Port of `_period_returns`: trading return per period (M/W/D).
Map<String, double> periodReturns(List<dynamic> portfolio, {String freq = 'M'}) {
  final equity = <List<num>>[];
  final pnl = <List<num>>[];
  for (final item in portfolio) {
    if (item is! List ||
        item.isEmpty ||
        item[0] != 'allTime' ||
        item[1] is! Map) {
      continue;
    }
    final bucket = item[1] as Map;
    final ah = bucket['accountValueHistory'];
    if (ah is List) {
      for (final point in ah) {
        if (point is List && point.length > 1) {
          equity.add([number(point[0]).toInt(), number(point[1])]);
        }
      }
    }
    final ph = bucket['pnlHistory'];
    if (ph is List) {
      for (final point in ph) {
        if (point is List && point.length > 1) {
          pnl.add([number(point[0]).toInt(), number(point[1])]);
        }
      }
    }
  }
  equity.sort((a, b) => a[0].compareTo(b[0]));
  pnl.sort((a, b) => a[0].compareTo(b[0]));
  if (pnl.isEmpty) return {};
  final equityTs = [for (final e in equity) e[0] as int];
  var maxEquity = 0.0;
  for (final e in equity) {
    if (e[1] > maxEquity) maxEquity = e[1].toDouble();
  }

  // Equity strictly BEFORE ts: the balance the period started with, so a
  // deposit or gain inside the period never leaks into the denominator.
  double equityAt(int ts) {
    final i = bisectLeft(equityTs, ts) - 1;
    if (i >= 0 && equity[i][1] > 0) return equity[i][1].toDouble();
    // Account starts with a zero-balance snapshot before the first deposit;
    // roll forward to the first real funded balance so the first period's
    // return is measured against the capital actually traded with.
    for (final e in equity) {
      if (e[0] >= ts && e[1] > 0) return e[1].toDouble();
    }
    return 0.0;
  }

  String periodKey(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true);
    if (freq == 'W') {
      final (y, w) = _isoYearWeek(dt);
      return '${y.toString().padLeft(4, '0')}-W${_pad2(w)}';
    }
    if (freq == 'D') {
      return '${dt.year.toString().padLeft(4, '0')}-${_pad2(dt.month)}-${_pad2(dt.day)}';
    }
    return '${dt.year.toString().padLeft(4, '0')}-${_pad2(dt.month)}';
  }

  final byPeriod = <String, List<List<num>>>{};
  for (final p in pnl) {
    byPeriod.putIfAbsent(periodKey(p[0] as int), () => []).add(p);
  }
  final result = <String, double>{};
  double? prevPnl;
  final keys = byPeriod.keys.toList()..sort();
  for (final period in keys) {
    final points = byPeriod[period]!..sort((a, b) => a[0].compareTo(b[0]));
    final endPnl = points.last[1].toDouble();
    // Carry the previous period's final PnL: the change between periods
    // belongs to the later period.
    final startPnl = prevPnl ?? points.first[1].toDouble();
    final openingEquity = equityAt(points.first[0] as int);
    // Ignore periods that start on a near-zero seed balance.
    if (openingEquity >= maxEquity * 0.01 && openingEquity != 0) {
      result[period] = round2((endPnl - startPnl) / openingEquity * 100);
    }
    prevPnl = endPnl;
  }
  return result;
}

/// Port of `_historical_leverage`: max exposure/equity across all fills,
/// capped at 100x.
double? historicalLeverage(
  List<Map<String, dynamic>> fills,
  List<dynamic> portfolio,
) {
  var history = <List<num>>[];
  for (final item in portfolio) {
    if (item is List &&
        item.isNotEmpty &&
        item[0] == 'allTime' &&
        item[1] is Map) {
      final ah = (item[1] as Map)['accountValueHistory'];
      if (ah is List) {
        history = [
          for (final x in ah)
            if (x is List && x.length > 1) [number(x[0]).toInt(), number(x[1])],
        ];
      }
    }
  }
  history.sort((a, b) => a[0].compareTo(b[0]));
  var maxEquity = 0.0;
  for (final x in history) {
    if (x[1] > maxEquity) maxEquity = x[1].toDouble();
  }
  final positions = <String, double>{};
  double? maximum;
  final sorted = [...fills]..sort((a, b) => number(a['time']).compareTo(number(b['time'])));
  for (final fill in sorted) {
    final coin = '${fill['coin'] ?? '?'}';
    final side = '${fill['side'] ?? ''}'.toLowerCase();
    final q = (side == 'b' || side == 'buy') ? 1.0 : -1.0;
    positions[coin] = (positions[coin] ?? 0.0) + q * number(fill['sz']).abs();
    final price = number(fill['px']);
    final timestamp = number(fill['time']).toInt();
    var equity = 0.0;
    for (final h in history.reversed) {
      if (h[0] <= timestamp) {
        equity = h[1].toDouble();
        break;
      }
    }
    if (equity >= maxEquity * 0.01 && equity != 0) {
      var exposure = 0.0;
      positions.forEach((_, v) => exposure += v.abs() * price);
      maximum = math.max(maximum ?? 0.0, exposure / equity);
    }
  }
  if (maximum == null) return null;
  // A handful of fills can land on tiny equity points and produce absurd
  // ratios (e.g. 700x). Cap at a sane level.
  return round2(math.min(maximum, 100.0));
}

/// Port of `calculate()`: full trading report. Result keys match the Python
/// output exactly (used for web JSON output and report rendering).
Map<String, dynamic> calculate(
  List<Map<String, dynamic>> fills, {
  Map<String, dynamic>? state,
  List<dynamic>? portfolio,
  List<Map<String, dynamic>>? funding,
}) {
  portfolio ??= const [];
  funding ??= const [];
  final sortedFills = [...fills]
    ..sort((a, b) => number(a['time']).compareTo(number(b['time'])));
  final realized = <Map<String, dynamic>>[];
  for (final fill in sortedFills) {
    if (number(fill['closedPnl']) == 0) continue;
    realized.add({
      'pnl': number(fill['closedPnl']) - number(fill['fee']).abs(),
      'time': number(fill['time']).toInt(),
      'side': '${fill['side'] ?? ''}'.toLowerCase(),
    });
  }
  final pnls = [for (final x in realized) (x['pnl'] as num).toDouble()];
  final wins = [for (final x in pnls) if (x > 0) x];
  final losses = [for (final x in pnls) if (x < 0) x];
  var grossProfit = 0.0;
  for (final x in wins) {
    grossProfit += x;
  }
  var grossLoss = 0.0;
  for (final x in losses) {
    grossLoss += x;
  }
  var longestWin = 0, longestLoss = 0, runWin = 0, runLoss = 0;
  var winRunProfit = 0.0,
      lossRunProfit = 0.0,
      maxWinRunProfit = 0.0,
      maxLossRunProfit = 0.0;
  for (final value in pnls) {
    if (value > 0) {
      runWin += 1;
      runLoss = 0;
      winRunProfit += value;
      lossRunProfit = 0;
      if (runWin > longestWin) longestWin = runWin;
      if (winRunProfit > maxWinRunProfit) maxWinRunProfit = winRunProfit;
    } else if (value < 0) {
      runLoss += 1;
      runWin = 0;
      lossRunProfit += value;
      winRunProfit = 0;
      if (runLoss > longestLoss) longestLoss = runLoss;
      if (lossRunProfit < maxLossRunProfit) maxLossRunProfit = lossRunProfit;
    } else {
      runWin = runLoss = 0;
      winRunProfit = lossRunProfit = 0;
    }
  }
  final times = [for (final x in realized) x['time'] as int];
  final maxTime = times.isEmpty ? 0 : times.reduce(math.max);
  final minTime = times.isEmpty ? 0 : times.reduce(math.min);
  final spanWeeks =
      times.length > 1 ? ((maxTime - minTime) / 86_400_000 / 7) : 0.0;
  final deviation = pnls.length > 1 ? pstdev(pnls) : null;

  // Full-history period returns for Sharpe/Sortino and TWR: per-trade stats
  // can be wrong for large accounts (public fills may only cover recent
  // activity). Use the finest granularity the pnl history supports: daily when
  // snapshots are dense (new accounts), weekly when weekly-sampled, else
  // monthly.
  final densityDay = pnlDensity(portfolio, perDay: true);
  final densityWeek = pnlDensity(portfolio);
  String periodFreq;
  double factor;
  if (densityDay >= 2) {
    periodFreq = 'D';
    factor = math.sqrt(365);
  } else if (densityWeek >= 3) {
    periodFreq = 'W';
    factor = math.sqrt(52);
  } else {
    periodFreq = 'M';
    factor = math.sqrt(12);
  }
  final periodReturnsList =
      periodReturns(portfolio, freq: periodFreq).values.toList();
  double? sharpe;
  double? sortino;
  final periodStd = pstdev(periodReturnsList);
  if (periodReturnsList.length >= 2 && (periodStd ?? 0) > 0) {
    final periodMean = mean(periodReturnsList);
    sharpe = periodMean / periodStd! * factor;
    final periodLosses = [for (final x in periodReturnsList) if (x < 0) x];
    final periodDownside = periodLosses.isEmpty
        ? 0.0
        : math.sqrt(periodLosses.fold(0.0, (a, b) => a + b * b) /
            periodLosses.length);
    sortino = periodDownside > 0 ? periodMean / periodDownside * factor : null;
  } else {
    sharpe = deviation != null && deviation != 0
        ? mean(pnls) / deviation * math.sqrt(pnls.length)
        : null;
    final lossesOnly = [for (final x in pnls) if (x < 0) x];
    final downsideStd = lossesOnly.isEmpty
        ? 0.0
        : math.sqrt(lossesOnly.fold(0.0, (a, b) => a + b * b) /
            lossesOnly.length);
    sortino = downsideStd > 0 && pnls.isNotEmpty
        ? mean(pnls) / downsideStd * math.sqrt(252)
        : null;
  }
  final periodAvgPercent =
      periodReturnsList.isEmpty ? null : mean(periodReturnsList);

  final longTrades = realized
      .where((x) => x['side'] == 'a' || x['side'] == 'sell')
      .length;
  final shortTrades = realized
      .where((x) => x['side'] == 'b' || x['side'] == 'buy')
      .length;
  final longWins = realized
      .where((x) =>
          (x['side'] == 'a' || x['side'] == 'sell') &&
          (x['pnl'] as num).toDouble() > 0)
      .length;
  final shortWins = realized
      .where((x) =>
          (x['side'] == 'b' || x['side'] == 'buy') &&
          (x['pnl'] as num).toDouble() > 0)
      .length;

  var fundingTotal = 0.0;
  for (final x in funding) {
    final delta = x['delta'];
    if (delta is Map) {
      fundingTotal += number(delta['usdc']);
    } else {
      fundingTotal += number(x['delta'] ?? x['usdc']);
    }
  }
  var fees = 0.0;
  for (final f in fills) {
    fees += number(f['fee']).abs();
  }

  Map<String, dynamic> allTime = const {};
  for (final x in portfolio) {
    if (x is List && x.isNotEmpty && x[0] == 'allTime' && x[1] is Map) {
      allTime = (x[1] as Map).cast<String, dynamic>();
      break;
    }
  }
  final equityHistory = <List<num>>[];
  {
    final ah = allTime['accountValueHistory'];
    if (ah is List) {
      for (final x in ah) {
        if (x is List && x.length > 1) {
          equityHistory.add([number(x[0]).toInt(), number(x[1])]);
        }
      }
    }
  }
  var peak = equityHistory.isEmpty ? 0.0 : number(equityHistory.first[1]);
  var maxDrawdown = 0.0;
  for (final e in equityHistory) {
    peak = math.max(peak, number(e[1]));
    if (peak != 0) {
      maxDrawdown =
          math.max(maxDrawdown, (peak - number(e[1])) / peak * 100);
    }
  }

  final winRatePercent = pnls.isEmpty ? null : wins.length / pnls.length * 100;

  // Time-weighted returns (TWR): compound the period returns, so deposits
  // and withdrawals never distort the result.
  double? totalReturnPercent;
  double? peakReturnPercent;
  var twr = 1.0, twrPeak = 1.0;
  var valid = true;
  for (final r in periodReturnsList) {
    final f = 1 + r / 100;
    if (f <= 0) {
      valid = false;
      break;
    }
    twr *= f;
    twrPeak = math.max(twrPeak, twr);
  }
  if (valid && periodReturnsList.isNotEmpty) {
    totalReturnPercent = (twr - 1) * 100;
    peakReturnPercent = (twrPeak - 1) * 100;
  }
  final recoveryFactor = maxDrawdown > 0 && totalReturnPercent != null
      ? totalReturnPercent / maxDrawdown
      : null;

  final (deposits, withdrawals) = netFlows(portfolio);
  final ddSquares = <double>[];
  var runningPeak = 0.0;
  for (final e in equityHistory) {
    runningPeak = math.max(runningPeak, number(e[1]));
    if (runningPeak != 0) {
      ddSquares.add((1 - number(e[1]) / runningPeak) * (1 - number(e[1]) / runningPeak));
    }
  }
  final ulcer = ddSquares.isEmpty
      ? 0.0
      : math.sqrt(ddSquares.fold(0.0, (a, b) => a + b) / ddSquares.length);
  final upi = ulcer > 0 && periodAvgPercent != null
      ? periodAvgPercent / ulcer
      : null;

  final pnlHistory = <List<num>>[];
  {
    final ph = allTime['pnlHistory'];
    if (ph is List) {
      for (final x in ph) {
        if (x is List && x.length > 1) {
          pnlHistory.add([number(x[0]).toInt(), number(x[1])]);
        }
      }
    }
  }
  final pnlHist = allTime['pnlHistory'];
  double? portfolioPnl;
  if (pnlHist is List && pnlHist.isNotEmpty) {
    final last = pnlHist.last;
    if (last is List && last.length > 1) {
      portfolioPnl = money(number(last[1]));
    }
  }

  final result = <String, dynamic>{
    'trades': pnls.length,
    'profit_trades': wins.length,
    'loss_trades': losses.length,
    'best_trade_usdc': pnls.isEmpty ? null : money(pnls.reduce(math.max)),
    'worst_trade_usdc': pnls.isEmpty ? null : money(pnls.reduce(math.min)),
    'gross_profit_usdc': money(grossProfit),
    'gross_loss_usdc': money(grossLoss),
    'fees_usdc': money(fees),
    'funding_usdc': money(fundingTotal),
    'deposits_usdc': money(deposits),
    'withdrawals_usdc': money(withdrawals),
    'net_profit_usdc': money(
        pnls.fold(0.0, (a, b) => a + b) + fundingTotal),
    'maximum_consecutive_wins': longestWin,
    'maximum_consecutive_wins_usdc': money(maxWinRunProfit),
    'maximal_consecutive_profit_usdc': money(maxWinRunProfit),
    'maximum_consecutive_losses': longestLoss,
    'maximal_consecutive_loss_usdc': money(maxLossRunProfit),
    'sharpe_ratio': sharpe == null ? null : round2(sharpe),
    'trading_activity_percent': times.length > 1
        ? round2(fills.length / math.max(1, (maxTime - minTime) / 86_400_000) * 100)
        : null,
    'trades_per_week': spanWeeks != 0 ? round2(pnls.length / spanWeeks) : null,
    'avg_holding_hours': (() {
      final h = holdingHours(fills);
      return h == null ? null : round2(h);
    })(),
    'long_trades': longTrades,
    'short_trades': shortTrades,
    'long_wins': longWins,
    'short_wins': shortWins,
    'profit_factor': grossLoss != 0
        ? round2(grossProfit / grossLoss.abs())
        : null,
    'expected_payoff_usdc': pnls.isEmpty
        ? null
        : money(pnls.fold(0.0, (a, b) => a + b) / pnls.length),
    'average_profit_usdc': wins.isEmpty ? null : money(grossProfit / wins.length),
    'average_loss_usdc': losses.isEmpty ? null : money(grossLoss / losses.length),
    'standard_deviation_usdc': money(deviation),
    'win_rate_percent': winRatePercent == null ? null : round2(winRatePercent),
    'period_avg_percent':
        periodAvgPercent == null ? null : round2(periodAvgPercent),
    'period_freq': periodFreq,
    'total_return_percent':
        totalReturnPercent == null ? null : round2(totalReturnPercent),
    'peak_return_percent':
        peakReturnPercent == null ? null : round2(peakReturnPercent),
    'sortino_ratio': sortino == null ? null : round2(sortino),
    'recovery_factor': recoveryFactor == null ? null : round2(recoveryFactor),
    'upi': upi == null ? null : round2(upi),
    'latest_trade_ms': times.isEmpty ? null : times.last,
    'fills': fills.length,
    'monthly_growth': periodReturns(portfolio, freq: 'M'),
    'historical_effective_leverage': historicalLeverage(fills, portfolio),
    'equity_history': equityHistory,
    'pnl_history': pnlHistory,
    'portfolio_pnl_usdc': portfolioPnl,
    'volume_usdc': allTime.isEmpty ? null : money(number(allTime['vlm'])),
    'max_drawdown_percent': round2(maxDrawdown),
    'total_equity_usdc':
        equityHistory.isEmpty ? null : money(number(equityHistory.last[1])),
    'trading_equity_usdc':
        equityHistory.isEmpty ? null : money(number(equityHistory.last[1])),
  };
  if (state != null && state.isNotEmpty) {
    final summary = state['marginSummary'] is Map
        ? (state['marginSummary'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final accountValue = number(summary['accountValue']);
    final exposure = number(summary['totalNtlPos']);
    result['account_value_usdc'] = money(accountValue);
    result['withdrawable_usdc'] = money(number(state['withdrawable']));
    result['effective_leverage'] =
        accountValue != 0 ? round2(exposure / accountValue) : null;
    final leverages = <double>[];
    final assetPositions = state['assetPositions'];
    if (assetPositions is List) {
      for (final x in assetPositions) {
        if (x is! Map) continue;
        final pos = x['position'];
        if (pos is Map) {
          final lev = pos['leverage'];
          if (lev is Map) leverages.add(number(lev['value']));
        }
      }
    }
    // Current leverage reflects the leverage set on currently open orders
    // and positions. Historical/combined leverage reflects all trades ever
    // made.
    result['account_leverage'] = leverages.isNotEmpty
        ? leverages.reduce(math.max)
        : result['historical_effective_leverage'];
    result['history_leverage'] = result['historical_effective_leverage'];
  }
  return result;
}

/// Port of `display_time()`.
String displayTime(int? ms, {DateTime? now}) {
  if (ms == null || ms == 0) return 'n/a';
  final age = (now ?? DateTime.now())
      .toUtc()
      .difference(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true))
      .inSeconds
      .toDouble();
  final ageSec = math.max(0.0, age);
  if (ageSec < 3600) return '${(ageSec / 60).floor()} minutes ago';
  if (ageSec < 86400) return '${(ageSec / 3600).floor()} hours ago';
  return '${(ageSec / 86400).floor()} days ago';
}

// ---------------------------------------------------------------------------
// Formatting helpers ported from cli.py
// ---------------------------------------------------------------------------

/// Port of `fmt()`: "n/a" for null, ",.2f" for doubles, plain for ints.
String fmtValue(dynamic v) {
  if (v == null) return 'n/a';
  if (v is double) {
    final s = v.toStringAsFixed(2);
    final neg = s.startsWith('-');
    final digits = neg ? s.substring(1, s.length - 3) : s.substring(0, s.length - 3);
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return (neg ? '-' : '') + buf.toString() + s.substring(s.length - 3);
  }
  return '$v';
}

/// Port of `multiple()`.
String multiple(dynamic v) => v == null ? 'n/a' : '${fmtValue(v)}x';

/// Port of `compact()`: 1.234B / 12.345M / 123.456K.
String compact(dynamic v) {
  if (v == null) return 'n/a';
  final value = number(v);
  final sign = value < 0 ? '-' : '';
  final a = value.abs();
  for (final (unit, size) in [('B', 1e9), ('M', 1e6), ('K', 1e3)]) {
    if (a >= size) {
      return '$sign${(a / size).toStringAsFixed(3)}$unit';
    }
  }
  return '$sign${a.toStringAsFixed(2)}';
}

/// Port of `combine()`: compound growth percentages.
double combineGrowth(Iterable<double?> growths) {
  final values = [for (final v in growths) ?v];
  if (values.isEmpty) return 0;
  final factors = [for (final v in values) 1 + v / 100];
  if (factors.every((f) => f > 0)) {
    var prod = 1.0;
    for (final f in factors) {
      prod *= f;
    }
    return (prod - 1) * 100;
  }
  return values.fold(0.0, (a, b) => a + b);
}
