import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../analytics/analytics.dart' show number;

/// Mirrors hyperliquid_tracker/api.py: a small client for the public
/// Hyperliquid info API (no API key required).
class HyperliquidError implements Exception {
  HyperliquidError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when [HyperliquidClient.cancel] was called (e.g. the user navigated
/// back while the report was loading). Not an error: callers just stop.
class HyperliquidCancelled implements Exception {
  const HyperliquidCancelled();

  @override
  String toString() => 'cancelled';
}

/// Reports pagination progress from `fills`/`funding` (kind: "fills"|"funding").
typedef PageCallback = void Function(String kind, int page);

class HyperliquidClient {
  HyperliquidClient({
    String baseUrl = 'https://api.hyperliquid.xyz',
    Duration? timeout,
    Duration? delay,
  })  : _url = '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/info',
        _timeout = timeout ?? const Duration(seconds: 30),
        _delay = delay ?? const Duration(milliseconds: 500);

  final String _url;
  final Duration _timeout;
  final Duration _delay;
  DateTime? _lastRequest;
  bool _cancelled = false;

  /// Abort any in-flight or queued requests ([info] then throws
  /// [HyperliquidCancelled] and pagination loops stop).
  void cancel() => _cancelled = true;

  void _throwIfCancelled() {
    if (_cancelled) throw const HyperliquidCancelled();
  }

  Future<dynamic> info(Map<String, dynamic> payload) async {
    _throwIfCancelled();
    // Avoid hammering the public API: leave at least [_delay] between
    // requests (large accounts paginate dozens of pages).
    final now = DateTime.now();
    if (_lastRequest != null) {
      final wait = _delay - now.difference(_lastRequest!);
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
    }
    _lastRequest = DateTime.now();
    _throwIfCancelled();
    try {
      final response = await http
          .post(
            Uri.parse(_url),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      _throwIfCancelled();
      if (response.statusCode == 429) {
        throw HyperliquidError(
            'Hyperliquid rate limit reached - please wait a moment and try again');
      }
      if (response.statusCode != 200) {
        throw HyperliquidError(
            'Hyperliquid API request failed: ${response.statusCode} (${response.body})');
      }
      return jsonDecode(response.body);
    } on TimeoutException {
      throw HyperliquidError('Hyperliquid API request failed: timeout');
    } on FormatException {
      throw HyperliquidError('Hyperliquid returned invalid JSON');
    } on http.ClientException catch (e) {
      throw HyperliquidError('Hyperliquid API request failed: ${e.message}');
    }
  }

  /// Fetch the full public fill history, paging by timestamp.
  Future<List<Map<String, dynamic>>> fills(
    String address, {
    int? startMs,
    PageCallback? onPage,
  }) async {
    final result = <Map<String, dynamic>>[];
    // userFillsByTime requires startTime in the request body. A zero
    // timestamp means "all available history".
    var cursor = startMs ?? 0;
    final seen = <String>{};
    var pageNo = 0;
    while (true) {
      pageNo += 1;
      onPage?.call('fills', pageNo);
      final payload = <String, dynamic>{
        'type': 'userFillsByTime',
        'user': address,
        'startTime': cursor,
      };
      final page = await info(payload);
      if (page is! List) {
        throw HyperliquidError('Unexpected fills response');
      }
      final fresh = <Map<String, dynamic>>[];
      for (final fill in page) {
        if (fill is! Map) continue;
        final f = fill.cast<String, dynamic>();
        final key = '${f['hash']}|${f['tid']}|${f['time']}|${f['oid']}';
        if (seen.add(key)) {
          fresh.add(f);
        }
      }
      result.addAll(fresh);
      if (page.length < 2000) break;
      var newest = 0;
      for (final f in page) {
        if (f is! Map) continue;
        final t = number(f['time']).toInt();
        if (t > newest) newest = t;
      }
      if (newest <= cursor) break;
      cursor = newest + 1;
    }
    result.sort((a, b) => number(a['time']).compareTo(number(b['time'])));
    return result;
  }

  Future<Map<String, dynamic>> clearinghouseState(String address) async {
    final value = await info({'type': 'clearinghouseState', 'user': address});
    return value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<List<dynamic>> portfolio(String address) async {
    final value = await info({'type': 'portfolio', 'user': address});
    return value is List ? value : <dynamic>[];
  }

  /// userFunding caps responses at 500 entries, so advance the cursor as
  /// long as new data keeps arriving (no page-size assumption). Pages are
  /// capped at [maxPages] to stay within API rate limits; the returned bool
  /// is true when the cap was hit (history is incomplete).
  Future<(List<Map<String, dynamic>>, bool)> funding(
    String address, {
    int? startMs,
    PageCallback? onPage,
    int maxPages = 10,
  }) async {
    final result = <Map<String, dynamic>>[];
    var cursor = startMs ?? 0;
    final seen = <String>{};
    var pageNo = 0;
    var capped = false;
    while (true) {
      pageNo += 1;
      if (pageNo > maxPages) {
        capped = true;
        break;
      }
      onPage?.call('funding', pageNo);
      final value = await info({
        'type': 'userFunding',
        'user': address,
        'startTime': cursor,
      });
      if (value is! List || value.isEmpty) break;
      for (final item in value) {
        if (item is! Map) continue;
        final it = item.cast<String, dynamic>();
        final key = '${it['time']}|${it['hash']}|${it['delta']}';
        if (seen.add(key)) {
          result.add(it);
        }
      }
      var newest = 0;
      for (final x in value) {
        if (x is! Map) continue;
        final t = number(x['time']).toInt();
        if (t > newest) newest = t;
      }
      if (newest <= cursor) break;
      cursor = newest + 1;
    }
    result.sort((a, b) => number(a['time']).compareTo(number(b['time'])));
    return (result, capped);
  }
}
