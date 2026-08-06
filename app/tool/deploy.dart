/// Deploy the web build to docs/ for GitHub Pages (main -> /docs).
///
/// Run from anywhere (resolves its own location):
///   dart `path-to-app`/tool/deploy.dart          # build, refresh, commit, push
///   dart `path-to-app`/tool/deploy.dart --no-push # build + refresh + stage only
///
/// Steps: flutter build web -> refresh docs/ (with 404.html + CNAME) ->
/// git add docs -> commit -> push.
library;

import 'dart:io';

const cname = 'tracker.tragichero.win';

Future<void> main(List<String> args) async {
  final noPush = args.contains('--no-push');

  // Resolve paths from the script location, so it works from any cwd.
  final scriptDir = File.fromUri(Platform.script).parent; // app/tool
  final appDir = scriptDir.parent; // app
  final root = appDir.parent; // repo root
  final docs = Directory('${root.path}${Platform.pathSeparator}docs');
  final buildWeb =
      Directory('${appDir.path}${Platform.pathSeparator}build${Platform.pathSeparator}web');

  stdout.writeln('== flutter build web');
  var r = await run('flutter', ['build', 'web'], workingDirectory: appDir.path);
  stdout.write(r.stdout);
  stderr.write(r.stderr);
  if (r.exitCode != 0) exit(r.exitCode);

  stdout.writeln('== refresh docs/');
  if (docs.existsSync()) docs.deleteSync(recursive: true);
  copyDirSync(buildWeb.path, docs.path);
  File('${docs.path}${Platform.pathSeparator}index.html')
      .copySync('${docs.path}${Platform.pathSeparator}404.html');
  File('${docs.path}${Platform.pathSeparator}CNAME')
      .writeAsStringSync('$cname\n');

  stdout.writeln('== git add docs');
  r = await run('git', ['add', 'docs'], workingDirectory: root.path);
  stdout.write(r.stdout);
  stderr.write(r.stderr);
  if (r.exitCode != 0) exit(r.exitCode);

  r = await run('git', ['diff', '--cached', '--quiet', '--', 'docs'],
      workingDirectory: root.path);
  if (r.exitCode == 0) {
    stdout.writeln('No docs changes; nothing to commit.');
    return;
  }
  if (noPush) {
    stdout.writeln('Docs staged (--no-push). Commit and push manually.');
    return;
  }

  stdout.writeln('== commit');
  r = await run('git', ['commit', '-m', 'Update web build', '--', 'docs'],
      workingDirectory: root.path);
  stdout.write(r.stdout);
  stderr.write(r.stderr);
  if (r.exitCode != 0) exit(r.exitCode);

  stdout.writeln('== push');
  r = await run('git', ['push'], workingDirectory: root.path);
  stdout.write(r.stdout);
  stderr.write(r.stderr);
  if (r.exitCode != 0) exit(r.exitCode);

  stdout.writeln('Deployed: $cname');
}

void copyDirSync(String from, String to) {
  final src = Directory(from);
  for (final entity in src.listSync(recursive: true)) {
    final rel = entity.path.substring(src.path.length + 1);
    final dest = '$to${Platform.pathSeparator}$rel';
    if (entity is Directory) {
      Directory(dest).createSync(recursive: true);
    } else if (entity is File) {
      File(dest).parent.createSync(recursive: true);
      entity.copySync(dest);
    }
  }
}

/// Run a command, resolving .bat/.cmd wrappers on Windows (e.g. flutter).
Future<ProcessResult> run(
  String cmd,
  List<String> args, {
  String? workingDirectory,
}) {
  if (Platform.isWindows) {
    return Process.run('cmd', ['/c', cmd, ...args],
        workingDirectory: workingDirectory);
  }
  return Process.run(cmd, args, workingDirectory: workingDirectory);
}
