import 'dart:io';

const supportedTargets = {'linux', 'macos', 'windows'};

/// Builds one release bundle for a supported Flutter desktop target.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 || !supportedTargets.contains(arguments.single)) {
    stderr.writeln(
      'Usage: dart run tool/build_desktop.dart <linux|macos|windows>',
    );
    exitCode = 64;
    return;
  }

  final target = arguments.single;
  final flutter = Platform.isWindows ? 'flutter.bat' : 'flutter';
  // A release build must not reuse a stale frontend kernel after source files
  // or the Flutter SDK changed. This is especially important on Windows,
  // where flutter_assemble.vcxproj can otherwise preserve misleading Dart
  // type errors from an older incremental build.
  await runCommand(flutter, ['clean']);
  await runCommand(flutter, ['config', '--enable-$target-desktop']);
  await runCommand(flutter, ['pub', 'get']);
  await runCommand(flutter, ['build', target, '--release']);

  stdout.writeln('\nRelease bundle: ${artifactPath(target)}');
}

Future<void> runCommand(String executable, List<String> arguments) async {
  stdout.writeln('\n> $executable ${arguments.join(' ')}');
  final result = await Process.run(
    executable,
    arguments,
    runInShell: Platform.isWindows,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) exit(result.exitCode);
}

String artifactPath(String target) => switch (target) {
  'linux' => 'build/linux/x64/release/bundle/',
  'macos' => 'build/macos/Build/Products/Release/gift.app',
  'windows' => 'build/windows/x64/runner/Release/',
  _ => 'build/',
};
