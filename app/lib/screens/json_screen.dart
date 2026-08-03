import 'dart:convert';

import 'package:flutter/material.dart';

/// Raw report JSON, web only: no app chrome — just the raw JSON text.
class JsonScreen extends StatelessWidget {
  const JsonScreen({super.key, required this.data});

  final Map<String, dynamic> data;

  String get _json => const JsonEncoder.withIndent('  ').convert(data);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            _json,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
    );
  }
}
