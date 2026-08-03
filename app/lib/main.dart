import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

/// Entry point. On web, an address can be opened directly via URL:
///   /#/<address>      or   /<address>      or   ?address=<address>
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final req = UrlRequest.fromUri(Uri.base);
  runApp(HypernumberApp(initialAddress: req.address));
}

/// Parsed address request from the current URL (web only).
class UrlRequest {
  const UrlRequest({this.address});

  final String? address;

  static final _addressRe = RegExp(r'^0x[0-9a-fA-F]{40}$');

  factory UrlRequest.fromUri(Uri uri) {
    String? address;
    // 1. Hash route: /#/<address>
    if (uri.fragment.isNotEmpty) {
      final parts =
          uri.fragment.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.isNotEmpty) address = parts.first;
    }
    // 2. Real path: /<address> (works wherever index.html is served for all
    //    paths: flutter run dev server, SPA rewrites, etc.)
    if (address == null && uri.pathSegments.isNotEmpty) {
      final segments =
          uri.pathSegments.where((p) => p.isNotEmpty).toList();
      if (segments.isNotEmpty) address = segments.last;
    }
    // 3. Query params: ?address=<address>
    if (address == null) {
      final qa = uri.queryParameters['address'];
      if (qa != null && qa.isNotEmpty) address = qa;
    }
    if (address != null && !_addressRe.hasMatch(address)) {
      address = null;
    }
    return UrlRequest(address: address);
  }
}

class HypernumberApp extends StatelessWidget {
  const HypernumberApp({super.key, this.initialAddress});

  final String? initialAddress;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hyperliquid Numbers',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: HomeScreen(initialAddress: initialAddress),
    );
  }
}
