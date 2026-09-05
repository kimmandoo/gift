import 'dart:io';

/// Runs every local check used by CI.
///
/// Keeping this in Dart makes the same command work from Bash, PowerShell,
/// and any supported desktop operating system.
Future<void> main() async {
  final flutter = Platform.isWindows ? 'flutter.bat' : 'flutter';

  await runCommand(flutter, ['pub', 'get']);
  await runCommand('dart', [
    'format',
    '--output=none',
    '--set-exit-if-changed',
    'lib',
    'test',
    'integration_test',
    'tool',
  ]);
  await runCommand(flutter, ['analyze']);

  // Git integration fixtures create repositories and temporary helper files.
  // Serializing the suite avoids Windows file-lock races during teardown while
  // keeping the same deterministic verification contract on every runner.
  final gitTestEnvironment = Platform.isWindows
      ? const <String, String>{
          'GIT_CONFIG_COUNT': '2',
          'GIT_CONFIG_KEY_0': 'core.autocrlf',
          'GIT_CONFIG_VALUE_0': 'false',
          'GIT_CONFIG_KEY_1': 'core.eol',
          'GIT_CONFIG_VALUE_1': 'lf',
        }
      : null;
  await runCommand(flutter, [
    'test',
    '--concurrency=1',
    '--timeout=2m',
  ], environment: gitTestEnvironment);
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
    runInShell: Platform.isWindows,
    environment: environment,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    exit(result.exitCode);
  }
}
