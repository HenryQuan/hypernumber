import 'package:flutter/material.dart';

import '../analytics/analytics.dart' show calculate;
import '../api/hyperliquid_client.dart';
import 'report_screen.dart';

/// Fetches fills/state/portfolio/funding, runs the ported analytics, then
/// shows the report with live pagination progress.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key, required this.address});

  final String address;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  final _client = HyperliquidClient();
  String _progress = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    // User navigated back: stop fetching pages.
    _client.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _progress = '';
    });
    try {
      final fills = await _client.fills(widget.address, onPage: _onPage);
      final state = await _client.clearinghouseState(widget.address);
      final portfolio = await _client.portfolio(widget.address);
      final (funding, fundingCapped) =
          await _client.funding(widget.address, onPage: _onPage);
      final stats = calculate(
          fills, state: state, portfolio: portfolio, funding: funding);
      if (!mounted) return;
      final data = <String, dynamic>{
        'address': widget.address,
        'funding_capped': fundingCapped,
        ...stats,
      };
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ReportScreen(address: widget.address, data: data),
        ),
      );
    } on HyperliquidCancelled {
      // User navigated back; requests stopped, nothing to show.
    } on HyperliquidError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Unexpected error: $e');
    }
  }

  void _onPage(String kind, int page) {
    if (!mounted) return;
    setState(() => _progress = 'fetching $kind page $page…');
  }

  void _retry() => _run();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Building report')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error == null) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  _progress.isEmpty ? 'Contacting Hyperliquid…' : _progress,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.address,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ] else ...[
                Icon(Icons.error_outline,
                    size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
