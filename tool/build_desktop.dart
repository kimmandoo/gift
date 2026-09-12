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
  await runCommand(
    flutter,
    ['build', target, '--release'],
    environment: target == 'macos'
        ? const {
            // Keep macOS builds certificate-free. The distribution archive
            // ships Run-Gift.command beside the unsigned app.
            'CODE_SIGNING_ALLOWED': 'NO',
            'CODE_SIGNING_REQUIRED': 'NO',
          }
        : null,
  );
  if (target == 'macos') {
    await stageMacOSDesktopArtifact();
  }

  stdout.writeln('\nRelease bundle: ${artifactPath(target)}');
}

Future<void> stageMacOSDesktopArtifact() async {
  const releaseDirectory = 'build/macos/Build/Products/Release';
  const distributionDirectory = 'build/macos/Distribution';
  final app = Directory('$releaseDirectory/gift.app');
  final launcher = File('tool/Run-Gift.command');
  final distribution = Directory(distributionDirectory);
  if (!await app.exists()) {
    throw StateError('Missing macOS app bundle: ${app.path}');
  }
  if (!await launcher.exists()) {
    throw StateError('Missing macOS launcher: ${launcher.path}');
  }
  if (await distribution.exists()) {
    await distribution.delete(recursive: true);
  }
  await distribution.create(recursive: true);
  await runCommand('/usr/bin/ditto', [
    app.path,
    '$distributionDirectory/gift.app',
  ]);
  final destination = File('$distributionDirectory/Run-Gift.command');
  await launcher.copy(destination.path);
  await runCommand('/bin/chmod', ['+x', destination.path]);
}

Future<void> runCommand(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  stdout.writeln('\n> $executable ${arguments.join(' ')}');
  final result = await Process.run(
    executable,
    arguments,
    environment: environment,
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
