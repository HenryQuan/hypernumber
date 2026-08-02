import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hypernumber/analytics/analytics.dart';
import 'package:hypernumber/screens/report_screen.dart';

/// Report screen must render without layout overflow at phone and desktop
/// widths (responsive metric grid + full-width calendar tables).
void main() {
  testWidgets('report renders at narrow and wide widths', (tester) async {
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
    final data = <String, dynamic>{'address': '0xabc', ...stats};

    for (final width in [360.0, 800.0, 1920.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ReportScreen(address: '0xabc', data: data),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'layout error at width $width');
      expect(find.text('Hyperliquid Numbers'), findsOneWidget);
    }
  });
}
