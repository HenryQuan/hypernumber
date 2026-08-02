import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'loading_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialAddress, this.initialJson = false});

  final String? initialAddress;
  final bool initialJson;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final TextEditingController _controller;
  late bool _json;
  String? _error;

  static final _addressRe = RegExp(r'^0x[0-9a-fA-F]{40}$');

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialAddress ?? '');
    _json = widget.initialJson;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _run() {
    final address = _controller.text.trim();
    if (!_addressRe.hasMatch(address)) {
      setState(() {
        _error = 'Address must be a 0x-prefixed 40-hex-character address';
      });
      return;
    }
    setState(() => _error = null);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoadingScreen(address: address, asJson: _json),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.show_chart, size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  'Hyperliquid Numbers',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter any public Hyperliquid wallet address to build a '
                  'trading report from the public Info API. No API key needed.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    labelText: 'Wallet address',
                    hintText: '0x0000000000000000000000000000000000000000',
                    border: const OutlineInputBorder(),
                    errorText: _error,
                  ),
                  style: const TextStyle(fontFamily: 'monospace'),
                  onSubmitted: (_) => _run(),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('JSON output'),
                  subtitle: const Text('Render the raw report JSON instead of '
                      'the dashboard'),
                  value: _json,
                  onChanged: (v) => setState(() => _json = v),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _run,
                  icon: const Icon(Icons.play_arrow),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Build report'),
                  ),
                ),
                if (kIsWeb) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Web JSON via URL: add /#/<address> or /#/<address>/json '
                    '(or ?address=<address>&json=1) to this page URL.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
