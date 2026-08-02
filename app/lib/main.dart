import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

/// Entry point. On web, the report/JSON can be opened directly via URL:
///   /#/<address>          -> dashboard
///   /#/<address>/json     -> raw JSON
///   ?address=<address>&json=1  (also supported)
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final req = UrlRequest.fromUri(Uri.base);
  runApp(HypernumberApp(initialAddress: req.address, initialJson: req.asJson));
}

/// Parsed report request from the current URL (web only).
class UrlRequest {
  const UrlRequest({this.address, this.asJson = false});

  final String? address;
  final bool asJson;

  factory UrlRequest.fromUri(Uri uri) {
    String? address;
    var asJson = false;
    final qa = uri.queryParameters['address'];
    if (qa != null && qa.isNotEmpty) {
      address = qa;
      asJson = uri.queryParameters['json'] == '1' ||
          uri.queryParameters['json'] == 'true' ||
          uri.queryParameters['format'] == 'json';
    }
    if (uri.fragment.isNotEmpty) {
      final parts =
          uri.fragment.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        address = parts.first;
        asJson = parts.length > 1 && parts[1] == 'json';
      }
    }
    if (address != null &&
        !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address)) {
      address = null;
    }
    return UrlRequest(address: address, asJson: asJson);
  }
}

class HypernumberApp extends StatelessWidget {
  const HypernumberApp({
    super.key,
    this.initialAddress,
    this.initialJson = false,
  });

  final String? initialAddress;
  final bool initialJson;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hyperliquid Numbers',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: HomeScreen(
        initialAddress: initialAddress,
        initialJson: initialJson,
      ),
    );
  }
}
