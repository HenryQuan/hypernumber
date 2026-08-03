import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hypernumber/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders the address input', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const HypernumberApp());
    expect(find.text('Hyperliquid Numbers'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
  });

  testWidgets('shows saved addresses', (tester) async {
    const addr = '0x1234567890abcdef1234567890abcdef12345678';
    SharedPreferences.setMockInitialValues({'address_history': [addr]});
    await tester.pumpWidget(const HypernumberApp());
    await tester.pump();
    expect(find.widgetWithText(ActionChip, addr), findsOneWidget);
  });

  testWidgets('saves a viewed address', (tester) async {
    const addr = '0x1234567890abcdef1234567890abcdef12345678';
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const HypernumberApp());
    await tester.enterText(find.byType(TextField), addr);
    await tester.tap(find.text('View'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    expect(find.widgetWithText(ActionChip, addr), findsOneWidget);
  });

  group('UrlRequest web routing', () {
    const addr = '0x1234567890abcdef1234567890abcdef12345678';
    const bad = '0xzzz';

    test('hash route #/<address>', () {
      final req = UrlRequest.fromUri(Uri.parse('https://h/#/$addr'));
      expect(req.address, addr);
      expect(req.asJson, isFalse);
    });

    test('hash route #/<address>/json', () {
      final req = UrlRequest.fromUri(Uri.parse('https://h/#/$addr/json'));
      expect(req.address, addr);
      expect(req.asJson, isTrue);
    });

    test('query params', () {
      final req = UrlRequest.fromUri(
          Uri.parse('https://h/?address=$addr&json=1'));
      expect(req.address, addr);
      expect(req.asJson, isTrue);
    });

    test('hash takes precedence over query', () {
      final req = UrlRequest.fromUri(Uri.parse('https://h/?address=$bad'));
      expect(req.address, isNull);
      final req2 = UrlRequest.fromUri(Uri.parse('https://h/#/$addr'));
      expect(req2.address, addr);
    });

    test('invalid address is rejected', () {
      final req = UrlRequest.fromUri(Uri.parse('https://h/#/$bad'));
      expect(req.address, isNull);
      expect(req.asJson, isFalse);
    });
  });
}
