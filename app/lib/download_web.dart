// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

/// Web: trigger a client-side download of [content] as [filename].
Future<void> downloadTextFile(String filename, String content) async {
  final blob = html.Blob([utf8.encode(content)], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)..download = filename;
  anchor.click();
  html.Url.revokeObjectUrl(url);
}
