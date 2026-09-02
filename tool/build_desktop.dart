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
  await runCommand(flutter, ['config', '--enable-$target-desktop']);
  await runCommand(flutter, ['pub', 'get']);
  await runCommand(flutter, [
    'build',
    target,
    '--release',
    if (target == 'macos') '--no-codesign',
  ]);

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
  'macos' => 'build/macos/Build/Products/Release/branchline.app',
  'windows' => 'build/windows/x64/runner/Release/',
  _ => 'build/',
};
