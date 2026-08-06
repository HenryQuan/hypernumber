import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hypernumber/analytics/analytics.dart';

import '../tool/report.dart';

/// The Dart CLI text output must be byte-identical to the committed
/// reference fixture (regenerated in Dart when the CLI changes).
void main() {
  test('CLI report text matches the reference output byte-for-byte', () {
    final fixture = jsonDecode(
      File('test/fixtures/report.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final inputs = fixture['inputs'] as Map<String, dynamic>;
    final fills = [
      for (final f in inputs['fills'] as List)
        (f as Map).cast<String, dynamic>(),
    ];
    final funding = [
      for (final f in inputs['funding'] as List)
        (f as Map).cast<String, dynamic>(),
    ];
    final state = (inputs['state'] as Map).cast<String, dynamic>();
    final portfolio = inputs['portfolio'] as List;
    final stats =
        calculate(fills, state: state, portfolio: portfolio, funding: funding);

    final expected = File('test/fixtures/report_cli.txt').readAsStringSync();
    final actual = reportText('0xabc', stats, now: DateTime.utc(2024, 1, 1));
    expect(actual, expected);
  });
}
