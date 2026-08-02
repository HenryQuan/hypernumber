import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hypernumber/analytics/analytics.dart';

/// Parity test: the Dart port must reproduce the reference Python
/// implementation's output exactly (see tool/gen_fixture.py).
void main() {
  test('calculate() matches the Python reference output', () {
    final fixture = jsonDecode(
      File('test/fixtures/report.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final inputs = fixture['inputs'] as Map<String, dynamic>;
    final expected = fixture['expected'] as Map<String, dynamic>;

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

    final actual = calculate(
      fills,
      state: state,
      portfolio: portfolio,
      funding: funding,
    );

    void check(dynamic exp, dynamic act, String key) {
      if (exp == null) {
        expect(act, isNull, reason: key);
      } else if (exp is num) {
        expect(act, isA<num>(), reason: key);
        expect((act as num).toDouble(), closeTo(exp.toDouble(), 0.02),
            reason: key);
      } else if (exp is Map) {
        expect(act, isA<Map>(), reason: key);
        final actMap = act as Map;
        expect(actMap.keys.toSet(), exp.keys.toSet(), reason: key);
        for (final k in exp.keys) {
          check(exp[k], actMap[k], '$key.$k');
        }
      } else if (exp is List) {
        expect(act, isA<List>(), reason: key);
        final actList = act as List;
        expect(actList.length, exp.length, reason: key);
        for (var i = 0; i < exp.length; i++) {
          check(exp[i], actList[i], '$key[$i]');
        }
      } else {
        expect(act, exp, reason: key);
      }
    }

    expect(actual.keys.toSet(), expected.keys.toSet(),
        reason: 'result keys must match');
    for (final key in expected.keys) {
      check(expected[key], actual[key], key);
    }
  });

  test('displayTime formats relative ages', () {
    final now = DateTime.now().toUtc();
    final minuteAgo = now.subtract(const Duration(minutes: 5));
    expect(
      displayTime(minuteAgo.millisecondsSinceEpoch),
      '5 minutes ago',
    );
    final hourAgo = now.subtract(const Duration(hours: 3));
    expect(
      displayTime(hourAgo.millisecondsSinceEpoch),
      '3 hours ago',
    );
    expect(displayTime(null), 'n/a');
  });

  test('fmtValue/compact/combineGrowth match Python formatting', () {
    expect(fmtValue(null), 'n/a');
    expect(fmtValue(1234567.891), '1,234,567.89');
    expect(fmtValue(4), '4');
    expect(compact(1234.5), '1.234K');
    expect(compact(-2500000.0), '-2.500M');
    expect(compact(999.99), '999.99');
    expect(compact(null), 'n/a');
    expect(combineGrowth([10.0, -5.0]), closeTo(4.5, 0.001));
    expect(combineGrowth(const [null, null]), 0);
  });
}
