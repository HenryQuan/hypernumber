import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  void mockClipboard(WidgetTester tester, String? text) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': text} : null,
    );
  }

  testWidgets('paste fills the field without running', (tester) async {
    const addr = '0x1234567890abcdef1234567890abcdef12345678';
    SharedPreferences.setMockInitialValues({});
    mockClipboard(tester, addr);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(const HypernumberApp());
    await tester.tap(find.byType(TextField)); // focus shows the paste button
    await tester.pump();
    await tester.tap(find.byIcon(Icons.content_paste));
    await tester.pump();
    expect(find.text(addr), findsOneWidget);
    expect(find.text('Building report'), findsNothing);
  });

  testWidgets('paste without an address just fills the field',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    mockClipboard(tester, 'not an address');
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(const HypernumberApp());
    await tester.tap(find.byType(TextField)); // focus shows the paste button
    await tester.pump();
    await tester.tap(find.byIcon(Icons.content_paste));
    await tester.pump();
    expect(find.text('not an address'), findsOneWidget);
    expect(
      find.text('Address must be a 0x-prefixed 40-hex-character address'),
      findsNothing,
    );
  });

  testWidgets('paste button only shows while the field is focused',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const HypernumberApp());
    expect(find.byIcon(Icons.content_paste), findsNothing);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.byIcon(Icons.content_paste), findsOneWidget);
  });

  testWidgets('auto-runs when opened with an address from the URL',
      (tester) async {
    const addr = '0x1234567890abcdef1234567890abcdef12345678';
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const HypernumberApp(initialAddress: addr));
    await tester.pump(); // post-frame callback
    await tester.pump(); // navigation
    expect(find.text('Building report'), findsOneWidget);
  });

  group('UrlRequest web routing', () {
    const addr = '0x1234567890abcdef1234567890abcdef12345678';
    const bad = '0xzzz';

    test('hash route #/<address>', () {
      final req = UrlRequest.fromUri(Uri.parse('https://h/#/$addr'));
      expect(req.address, addr);
    });

    test('real path /<address>', () {
      final req =
          UrlRequest.fromUri(Uri.parse('https://h/$addr'));
      expect(req.address, addr);
    });

    test('real path under a subdirectory', () {
      final req =
          UrlRequest.fromUri(Uri.parse('https://h/app/$addr'));
      expect(req.address, addr);
    });

    test('query params', () {
      final req = UrlRequest.fromUri(Uri.parse('https://h/?address=$addr'));
      expect(req.address, addr);
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
    });
  });
}
