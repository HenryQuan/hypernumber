import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'loading_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialAddress, this.initialJson = false});

  final String? initialAddress;
  final bool initialJson;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _historyKey = 'address_history';
  static const _maxHistory = 10;
  static final _addressRe = RegExp(r'^0x[0-9a-fA-F]{40}$');

  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String? _error;
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialAddress ?? '');
    _focusNode = FocusNode()..addListener(() => setState(() {}));
    _loadHistory();
    if (widget.initialAddress != null) {
      // Opened from a URL (e.g. /#/<address>): do the work directly.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_historyKey) ?? [];
      if (mounted) setState(() => _history = list);
    } catch (_) {
      // Storage unavailable (e.g. blocked web storage): history is optional.
    }
  }

  Future<void> _remember(String address) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = [address, ..._history.where((a) => a != address)]
          .take(_maxHistory)
          .toList();
      await prefs.setStringList(_historyKey, list);
      if (mounted) setState(() => _history = list);
    } catch (_) {
      // Ignore persistence failures; the report still works.
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted || text.isEmpty) return;
    // Just paste into the field; the user presses View when ready.
    setState(() {
      _controller.text = text;
      _error = null;
    });
  }

  void _run([String? address]) {
    final addr = (address ?? _controller.text).trim();
    if (!_addressRe.hasMatch(addr)) {
      setState(() {
        _error = 'Address must be a 0x-prefixed 40-hex-character address';
      });
      return;
    }
    setState(() => _error = null);
    _remember(addr);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoadingScreen(address: addr),
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
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    labelText: 'Wallet address',
                    hintText: '0x0000000000000000000000000000000000000000',
                    border: const OutlineInputBorder(),
                    errorText: _error,
                    suffixIcon: _focusNode.hasFocus
                        ? IconButton(
                            tooltip: 'Paste',
                            icon: const Icon(Icons.content_paste),
                            onPressed: _paste,
                          )
                        : null,
                  ),
                  style: const TextStyle(fontFamily: 'monospace'),
                  onSubmitted: (_) => _run(),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _run,
                  icon: const Icon(Icons.play_arrow),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('View'),
                  ),
                ),
                if (_history.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Recent', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final addr in _history)
                        ActionChip(
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 300),
                            child: Text(
                              addr,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                          onPressed: () {
                            _controller.text = addr;
                            _run(addr);
                          },
                        ),
                    ],
                  ),
                ],
                if (kIsWeb) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Open any address directly: /<address> or /#/<address> '
                    'in this page URL.',
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
