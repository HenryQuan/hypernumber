import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../analytics/analytics.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Tooltip explanations for jargon-y metric labels (simple labels have none).
const _termTips = <String, String>{
  'Max Drawdown': 'Largest peak-to-trough decline in account equity, as % of the peak.',
  'Portfolio PNL': 'Cumulative realized P&L from the portfolio PnL history.',
  'Funding': 'Perpetual funding payments: received (+) or paid (-) for holding positions.',
  'Current Leverage': 'Leverage set on currently open orders and positions.',
  'History Leverage': 'Largest exposure-to-equity ratio across all historical fills (capped at 100x).',
  'Profit Factor': 'Gross profit / gross loss. Above 1 means the account made more than it lost.',
  'Standard Deviation': 'Spread of per-trade P&L (population standard deviation).',
  'Sharpe Ratio': 'Risk-adjusted return: average P&L / its standard deviation (annualized).',
  'Sortino': 'Like Sharpe, but only penalizes losing periods (downside deviation).',
  'Recovery Factor': 'Total return / max drawdown. How quickly the account recovers from its worst decline.',
  'Total Return': 'Compounded (time-weighted) return across all periods.',
  'Peak Return': 'Highest compounded return the account reached.',
  'UPI': 'Ulcer Performance Index: average period return / Ulcer index (drawdown pain).',
  'Expectancy': 'Average expected P&L per trade (total P&L / trades).',
  'Trading Activity': '% of days with at least one fill since the first trade.',
  'Maximum Wins': 'Longest consecutive winning-trade streak.',
  'Maximum Losses': 'Longest consecutive losing-trade streak.',
  'Avg. Trade Length': 'Average time a position is held, FIFO-matched per coin.',
  'Daily Avg': 'Average return per day (period frequency chosen from data density).',
  'Weekly Avg': 'Average return per week (period frequency chosen from data density).',
  'Monthly Avg': 'Average return per month (period frequency chosen from data density).',
};

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key, required this.address, required this.data});

  final String address;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cards = _reportCards(data);
    final equity = _numPairs(data['equity_history']);
    final pnl = _numPairs(data['pnl_history']);
    final growth =
        (data['monthly_growth'] as Map?)?.cast<String, double>() ?? {};

    return Scaffold(
      appBar: AppBar(title: const Text('Hyperliquid Numbers')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SelectableText(
            address,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          if (data['funding_capped'] == true) ...[
            const SizedBox(height: 12),
            _CappedBanner(theme),
          ],
          const SizedBox(height: 16),
          _MetricGrid(cards),
          const _SectionTitle('Equity History (USDC)'),
          _lineChart(equity, color: theme.colorScheme.primary, unit: 'USDC'),
          const _SectionTitle('Equity History by Month (USDC)'),
          _equityTable(equity, theme),
          const _SectionTitle('Growth History (monthly returns)'),
          _growthTable(growth, theme),
          const _SectionTitle('Growth Movement (cumulative PnL)'),
          _lineChart(pnl, color: theme.colorScheme.tertiary, unit: 'USDC'),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// Warns that the funding history was capped and the funding total may be
/// incomplete.
class _CappedBanner extends StatelessWidget {
  const _CappedBanner(this.theme);

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Funding history was capped at 10 pages (5,000 entries) - '
              'the funding total may not reflect the full amount.',
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.tip});

  final String label;
  final String value;
  final String? tip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = Text(
      label,
      style: theme.textTheme.labelSmall
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tip != null)
            Tooltip(message: tip!, child: labelText)
          else
            labelText,
          const SizedBox(height: 4),
          SelectableText(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Responsive metrics grid: one card per row on narrow screens, up to 10 per
/// row when the width allows.
class _MetricGrid extends StatelessWidget {
  const _MetricGrid(this.cards);

  final List<(String, String)> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minCardWidth = 180.0;
        final columns =
            (constraints.maxWidth / minCardWidth).floor().clamp(1, 10).toInt();
        final itemWidth =
            (constraints.maxWidth - 8.0 * (columns - 1)) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, value) in cards)
              SizedBox(
                width: itemWidth,
                child: _Metric(
                  label: label,
                  value: value,
                  tip: _termTips[label],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Port of cli.py print_report rows, flattened into (label, value) cards.
List<(String, String)> _reportCards(Map<String, dynamic> s) {
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

  final cards = <(String, String)>[
    ('Trades', '$total'),
    ('Wins', '$profitTrades (${wp.toStringAsFixed(2)}%)'),
    ('Losses', '$lossTrades (${lp.toStringAsFixed(2)}%)'),
  ];
  final rest = <(String, String, String, String)>[
    ('Average Win', usdc(s['average_profit_usdc']), 'Average Loss',
        usdc(s['average_loss_usdc'])),
    ('Fees', '-${fmtValue(s['fees_usdc'])} USDC', 'Funding',
        usdc(s['funding_usdc'])),
    ('Deposits', usdc(s['deposits_usdc']), 'Withdrawals',
        usdc(s['withdrawals_usdc'])),
    ('Net P&L', usdc(s['net_profit_usdc']), 'Portfolio PNL',
        usdc(s['portfolio_pnl_usdc'])),
    ('Volume', usdc(s['volume_usdc']), 'Max Drawdown',
        pct(s['max_drawdown_percent'])),
    ('Total Equity', usdc(s['total_equity_usdc']), 'Trading Equity',
        usdc(s['trading_equity_usdc'])),
    ('Current Leverage', multiple(s['account_leverage']), 'History Leverage',
        multiple(s['history_leverage'])),
    ('Longs Won', sideStats(s['long_wins'], s['long_trades']), 'Shorts Won',
        sideStats(s['short_wins'], s['short_trades'])),
    ('Best Trade', usdc(s['best_trade_usdc']), 'Worst Trade',
        usdc(s['worst_trade_usdc'])),
    ('Avg. Trade Length', '${fmtValue(s['avg_holding_hours'])} hours',
        'Profit Factor', fmtValue(s['profit_factor'])),
    ('Standard Deviation', usdc(s['standard_deviation_usdc']), 'Sharpe Ratio',
        fmtValue(s['sharpe_ratio'])),
    ('Sortino', fmtValue(s['sortino_ratio']), 'Recovery Factor',
        fmtValue(s['recovery_factor'])),
    ('Total Return', pct(s['total_return_percent']), 'Peak Return',
        pct(s['peak_return_percent'])),
    (freq, pct(s['period_avg_percent']), 'UPI', fmtValue(s['upi'])),
    ('Expectancy', usdc(s['expected_payoff_usdc']), 'Trading Activity',
        pct(s['trading_activity_percent'])),
    ('Trades per Week', fmtValue(s['trades_per_week']), 'Latest Trade',
        displayTime((s['latest_trade_ms'] as num?)?.toInt())),
    ('Maximum Wins',
        '${s['maximum_consecutive_wins']} (${fmtValue(s['maximum_consecutive_wins_usdc'])} USDC)',
        'Maximum Losses',
        '${s['maximum_consecutive_losses']} (${fmtValue(s['maximal_consecutive_loss_usdc'])} USDC)'),
  ];
  for (final (a, b, c, d) in rest) {
    cards
      ..add((a, b))
      ..add((c, d));
  }
  return cards;
}

List<List<num>> _numPairs(dynamic value) {
  if (value is! List) return const [];
  return [
    for (final x in value)
      if (x is List && x.length > 1) [number(x[0]).toInt(), number(x[1])],
  ];
}

Widget _lineChart(List<List<num>> points,
    {required Color color, required String unit}) {
  if (points.length < 2) {
    return const Text('n/a');
  }
  final spots = [
    for (final p in points) FlSpot(p[0].toDouble(), p[1].toDouble()),
  ];
  var minY = double.infinity, maxY = double.negativeInfinity;
  for (final s in spots) {
    minY = math.min(minY, s.y);
    maxY = math.max(maxY, s.y);
  }
  if (minY == maxY) {
    minY -= 1;
    maxY += 1;
  }
  final pad = (maxY - minY) * 0.05;
  final minX = spots.first.x, maxX = spots.last.x;

  return SizedBox(
    height: 220,
    child: LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (value, meta) => Text(
                compact(value),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: (maxX - minX) / 6,
              // Avoid a duplicate tick on top of the last data point.
              maxIncluded: false,
              getTitlesWidget: (value, meta) {
                final dt = DateTime.fromMillisecondsSinceEpoch(
                  value.toInt(),
                  isUtc: true,
                );
                return Text(
                  '${dt.month}/${dt.year % 100}',
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => [
              for (final t in touched)
                LineTooltipItem(
                  '${compact(t.y)} $unit',
                  const TextStyle(color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Shared monthly calendar table: one row per year, 12 month cells, optional
/// year-total column and grand-total row. Stretches to fill the available
/// width (scrolls horizontally only when the viewport is too narrow).
Widget _calendarTable({
  required ThemeData theme,
  required List<String> years,
  required String Function(String year, int month) cell,
  String Function(String year)? yearTotal,
  String? grandTotal,
}) {
  final columnCount = 13 + (yearTotal != null ? 1 : 0);

  Widget rowCell(String text, {bool strong = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        alignment: Alignment.centerRight,
        child: Text(
          text,
          style: strong
              ? theme.textTheme.labelSmall
              : theme.textTheme.bodySmall,
        ),
      );

  final rows = <TableRow>[
    TableRow(children: [
      rowCell('Year', strong: true),
      for (final m in _months) rowCell(m, strong: true),
      if (yearTotal != null) rowCell('Year', strong: true),
    ]),
    for (final year in years)
      TableRow(children: [
        rowCell(year),
        for (var m = 1; m <= 12; m++) rowCell(cell(year, m)),
        if (yearTotal != null) rowCell(yearTotal(year)),
      ]),
    if (grandTotal != null)
      TableRow(children: [
        rowCell('Total'),
        for (var i = 0; i < 12; i++) rowCell(''),
        if (yearTotal != null) rowCell(grandTotal),
      ]),
  ];

  // Fill the full width when it fits; on narrow viewports use a readable
  // fixed column width and let the user scroll horizontally.
  return LayoutBuilder(
    builder: (context, constraints) {
      final colWidth = math.max(constraints.maxWidth / columnCount, 64.0);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: FixedColumnWidth(colWidth),
          border: TableBorder.all(color: theme.colorScheme.outlineVariant),
          children: rows,
        ),
      );
    },
  );
}

/// Port of cli.py growth history table (monthly % returns + year totals).
Widget _growthTable(Map<String, double> growth, ThemeData theme) {
  if (growth.isEmpty) return const Text('n/a');
  final years = growth.keys
      .map((k) => k.length >= 4 ? k.substring(0, 4) : k)
      .toSet()
      .toList()
    ..sort();
  return _calendarTable(
    theme: theme,
    years: years,
    cell: (year, month) {
      final v = growth['$year-${month.toString().padLeft(2, '0')}'];
      return v == null ? '' : '${v.toStringAsFixed(2)}%';
    },
    yearTotal: (year) {
      final vals = <double?>[
        for (var m = 1; m <= 12; m++)
          growth['$year-${m.toString().padLeft(2, '0')}'],
      ];
      return '${combineGrowth(vals).toStringAsFixed(2)}%';
    },
    grandTotal: '${compact(combineGrowth(growth.values))}%',
  );
}

/// Port of cli.py equity_chart: month-end equity per month (compact format).
Widget _equityTable(List<List<num>> points, ThemeData theme) {
  final monthly = <String, double>{};
  for (final p in points) {
    final dt = DateTime.fromMillisecondsSinceEpoch(p[0].toInt(), isUtc: true);
    monthly['${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}'] =
        number(p[1]);
  }
  if (monthly.isEmpty) return const Text('n/a');
  final years = monthly.keys.map((k) => k.substring(0, 4)).toSet().toList()
    ..sort();
  return _calendarTable(
    theme: theme,
    years: years,
    cell: (year, month) {
      final v = monthly['$year-${month.toString().padLeft(2, '0')}'];
      return v == null ? '' : compact(v);
    },
  );
}
