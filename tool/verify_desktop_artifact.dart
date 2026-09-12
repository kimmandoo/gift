import 'dart:io';

const supportedTargets = {'linux', 'macos', 'windows'};

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 || !supportedTargets.contains(arguments.single)) {
    stderr.writeln(
      'Usage: dart run tool/verify_desktop_artifact.dart <linux|macos|windows>',
    );
    exitCode = 64;
    return;
  }

  final target = arguments.single;
  final requiredPaths = switch (target) {
    'linux' => <String>[
      'build/linux/x64/release/bundle/gift',
      'build/linux/x64/release/bundle/data/flutter_assets',
      'build/linux/x64/release/bundle/lib/libflutter_linux_gtk.so',
    ],
    'macos' => <String>[
      'build/macos/Distribution/gift.app/Contents/MacOS/gift',
      'build/macos/Distribution/gift.app/Contents/Frameworks/App.framework/Resources/flutter_assets',
      'build/macos/Distribution/Run-Gift.command',
    ],
    'windows' => <String>[
      'build/windows/x64/runner/Release/gift.exe',
      'build/windows/x64/runner/gift-portable.exe',
      'build/windows/x64/runner/gift-setup.zip',
    ],
    _ => const <String>[],
  };

  for (final relativePath in requiredPaths) {
    final entity = FileSystemEntity.typeSync(relativePath);
    if (entity == FileSystemEntityType.notFound) {
      throw StateError('Missing $target release artifact: $relativePath');
    }
    if (entity == FileSystemEntityType.file &&
        File(relativePath).lengthSync() == 0) {
      throw StateError('Empty $target release artifact: $relativePath');
    }
  }

  stdout.writeln('$target desktop artifact verification passed.');
  for (final relativePath in requiredPaths) {
    final entity = FileSystemEntity.typeSync(relativePath);
    final size = entity == FileSystemEntityType.file
        ? File(relativePath).lengthSync()
        : Directory(relativePath).listSync(followLinks: false).length;
    stdout.writeln('  $relativePath ($size)');
  }
}
