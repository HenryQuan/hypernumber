import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../download.dart';

/// Raw report JSON view (mirrors the CLI `--json` output). On web the JSON
/// is also reachable directly at /#/<address>/json.
class JsonScreen extends StatelessWidget {
  const JsonScreen({super.key, required this.address, required this.data});

  final String address;
  final Map<String, dynamic> data;

  String get _json => const JsonEncoder.withIndent('  ').convert(data);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final jsonUrl = kIsWeb ? '${Uri.base.origin}/#/$address/json' : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('JSON report'),
        actions: [
          IconButton(
            tooltip: 'Copy JSON',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _json));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('JSON copied to clipboard')),
              );
            },
          ),
          if (kIsWeb)
            IconButton(
              tooltip: 'Download JSON',
              icon: const Icon(Icons.download),
              onPressed: () =>
                  downloadTextFile('hypernumber-report.json', _json),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (jsonUrl != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Direct JSON URL: $jsonUrl',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                _json,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
