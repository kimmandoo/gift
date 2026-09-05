import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _checksumsFile = 'SHA256SUMS.txt';
const _metadataFile = 'release-metadata.json';
const _sbomFile = 'sbom.cdx.json';
const _auditFile = 'dependency-audit.json';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    _usage();
    exitCode = 64;
    return;
  }

  try {
    switch (arguments.first) {
      case 'validate':
        _requireArguments(arguments, 2, 'validate <release-tag>');
        final version = await validateReleaseTag(arguments[1]);
        stdout.writeln('Release tag ${arguments[1]} matches version $version.');
      case 'generate':
        if (arguments.length < 4 || arguments.length > 5) {
          _requireArguments(
            arguments,
            4,
            'generate <release-tag> <commit> <artifact-directory> [--require-licenses]',
          );
        }
        final requireLicenses =
            arguments.length == 5 && arguments[4] == '--require-licenses';
        if (arguments.length == 5 && !requireLicenses) {
          throw const FormatException('Unknown generate option.');
        }
        await generateReleaseMetadata(
          tag: arguments[1],
          commit: arguments[2],
          directory: Directory(arguments[3]),
          requireLicenses: requireLicenses,
        );
      case 'verify':
        _requireArguments(
          arguments,
          3,
          'verify <artifact-directory> <checksums-file>',
        );
        await verifyChecksums(Directory(arguments[1]), File(arguments[2]));
      default:
        _usage();
        exitCode = 64;
    }
  } on Object catch (error) {
    stderr.writeln('Release metadata check failed: $error');
    exitCode = 1;
  }
}

Future<String> validateReleaseTag(String tag) async {
  final pubspec = await File('pubspec.yaml').readAsString();
  final versionMatch = RegExp(
    r'^version:\s*([^\s#]+)',
    multiLine: true,
  ).firstMatch(pubspec);
  if (versionMatch == null) {
    throw const FormatException('pubspec.yaml has no package version.');
  }
  final packageVersion = versionMatch.group(1)!;
  final tagMatch = RegExp(
    r'^release-v([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?)$',
  ).firstMatch(tag);
  if (tagMatch == null) {
    throw FormatException(
      'Expected a tag named release-v<semver>, received $tag.',
    );
  }
  final packageBaseVersion = packageVersion.split('+').first;
  final tagVersion = tagMatch.group(1)!;
  if (packageBaseVersion != tagVersion) {
    throw FormatException(
      'Tag version $tagVersion did not match pubspec version $packageVersion.',
    );
  }
  return packageVersion;
}

Future<void> generateReleaseMetadata({
  required String tag,
  required String commit,
  required Directory directory,
  required bool requireLicenses,
}) async {
  final packageVersion = await validateReleaseTag(tag);
  if (!await directory.exists()) {
    throw StateError(
      'Release artifact directory does not exist: ${directory.path}',
    );
  }
  final assets = await _releaseAssets(directory);
  if (assets.isEmpty) {
    throw StateError('Release artifact directory contains no package files.');
  }

  final checksums = <String, String>{};
  for (final asset in assets) {
    final name = _relativeName(directory, asset);
    checksums[name] = await _sha256File(asset);
  }
  final checksumFile = File(
    '${directory.path}${Platform.pathSeparator}$_checksumsFile',
  );
  final checksumText = checksums.keys.toList()..sort();
  await checksumFile.writeAsString(
    '${checksumText.map((name) => '${checksums[name]}  $name').join('\n')}\n',
  );

  final dependencyData = await _dependencyData(
    packageVersion: packageVersion,
    requireLicenses: requireLicenses,
  );
  final graph = dependencyData['packages']! as List<Object?>;
  final graphHash = sha256.convert(utf8.encode(jsonEncode(graph))).toString();
  final repository = Platform.environment['GITHUB_REPOSITORY'];
  final server =
      Platform.environment['GITHUB_SERVER_URL'] ?? 'https://github.com';
  final downloadBase = repository == null
      ? null
      : '$server/$repository/releases/download/$tag/';
  final metadata = <String, Object?>{
    'schemaVersion': 1,
    'product': 'gift',
    'version': packageVersion,
    'tag': tag,
    'commit': commit,
    'artifacts': [
      for (final asset in assets)
        {
          'name': _relativeName(directory, asset),
          'size': await asset.length(),
          'sha256': checksums[_relativeName(directory, asset)],
          if (downloadBase != null)
            'url': '$downloadBase${_relativeName(directory, asset)}',
        },
    ],
    'checksums': _checksumsFile,
    'sbom': _sbomFile,
    'dependencyAudit': _auditFile,
  };
  await _writeJson(directory, _metadataFile, metadata);
  await _writeJson(
    directory,
    _sbomFile,
    _cycloneDx(
      packageVersion: packageVersion,
      commit: commit,
      graph: graph,
      graphHash: graphHash,
    ),
  );
  await _writeJson(directory, _auditFile, {
    'schemaVersion': 1,
    'product': 'gift',
    'version': packageVersion,
    'commit': commit,
    'licensePolicy':
        'Every hosted dependency must ship a discoverable license file.',
    ...dependencyData,
  });
  stdout.writeln('Release metadata generated in ${directory.path}.');
  stdout.writeln('  packages: ${assets.length}');
  stdout.writeln('  checksums: ${checksumFile.path}');
  stdout.writeln(
    '  SBOM: ${directory.path}${Platform.pathSeparator}$_sbomFile',
  );
  stdout.writeln(
    '  dependency audit: ${directory.path}${Platform.pathSeparator}$_auditFile',
  );
}

Future<void> verifyChecksums(Directory directory, File checksumFile) async {
  if (!await checksumFile.exists()) {
    throw StateError('Checksum file does not exist: ${checksumFile.path}');
  }
  final lines = await checksumFile.readAsLines();
  var verified = 0;
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final match = RegExp(r'^([0-9a-f]{64})  (.+)$').firstMatch(line);
    if (match == null) throw FormatException('Malformed checksum line: $line');
    final file = File(
      '${directory.path}${Platform.pathSeparator}${match.group(2)}',
    );
    if (!await file.exists()) {
      throw StateError('Missing checksummed asset: ${file.path}');
    }
    final actual = await _sha256File(file);
    if (actual != match.group(1)) {
      throw StateError('Checksum mismatch for ${file.path}.');
    }
    verified++;
  }
  if (verified == 0) throw StateError('Checksum file contained no assets.');
  stdout.writeln('Verified $verified release checksums.');
}

Future<List<File>> _releaseAssets(Directory directory) async {
  final files = <File>[];
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    final name = _relativeName(directory, entity);
    if (name.contains(Platform.pathSeparator) || name.contains('/')) {
      throw StateError('Release assets must be flat: $name');
    }
    if (name == _checksumsFile ||
        name == _metadataFile ||
        name == _sbomFile ||
        name == _auditFile ||
        name.endsWith('.sig') ||
        name.endsWith('.crt')) {
      continue;
    }
    files.add(entity);
  }
  files.sort((left, right) => left.path.compareTo(right.path));
  return files;
}

String _relativeName(Directory root, File file) {
  final rootPath = root.absolute.path;
  final filePath = file.absolute.path;
  final prefix = rootPath.endsWith(Platform.pathSeparator)
      ? rootPath
      : '$rootPath${Platform.pathSeparator}';
  return filePath.startsWith(prefix)
      ? filePath
            .substring(prefix.length)
            .replaceAll(Platform.pathSeparator, '/')
      : file.uri.pathSegments.last;
}

Future<String> _sha256File(File file) async {
  return sha256.convert(await file.readAsBytes()).toString();
}

Future<Map<String, Object?>> _dependencyData({
  required String packageVersion,
  required bool requireLicenses,
}) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'pub',
    'deps',
    '--json',
  ]);
  if (result.exitCode != 0) {
    throw StateError('dart pub deps failed: ${result.stderr}');
  }
  final decoded = jsonDecode(result.stdout as String) as Map<String, Object?>;
  final packages = (decoded['packages']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final licenseFiles = <String, List<String>>{};
  final missing = <String>[];
  final packageConfigFile = File('.dart_tool/package_config.json');
  if (await packageConfigFile.exists()) {
    final packageConfig = jsonDecode(
      await packageConfigFile.readAsString(),
    ) as Map<String, Object?>;
    for (final entry
        in (packageConfig['packages']! as List<Object?>)
            .cast<Map<String, Object?>>()) {
      final name = entry['name']! as String;
      final source = entry['rootUri']! as String;
      final root = _uriToDirectory(source);
      final files = await _findLicenseFiles(root);
      licenseFiles[name] = files;
      final package = packages.firstWhere(
        (candidate) => candidate['name'] == name,
        orElse: () => <String, Object?>{},
      );
      if (package['source'] == 'hosted' && files.isEmpty) missing.add(name);
    }
  }
  if (requireLicenses && missing.isNotEmpty) {
    throw StateError(
      'Hosted packages without license files: ${missing.join(', ')}',
    );
  }
  return {
    'packageVersion': packageVersion,
    'packages': packages,
    'licenseFiles': licenseFiles,
    'missingLicensePackages': missing,
  };
}

Directory _uriToDirectory(String value) {
  final uri = Uri.parse(value);
  return uri.scheme == 'file' ? Directory.fromUri(uri) : Directory(value);
}

Future<List<String>> _findLicenseFiles(Directory root) async {
  if (!await root.exists()) return const [];
  final matches = <String>[];
  await for (final entity in root.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last.toUpperCase();
    if (name == 'LICENSE' ||
        name.startsWith('LICENSE.') ||
        name == 'COPYING' ||
        name.startsWith('COPYING.') ||
        name == 'NOTICE' ||
        name.startsWith('NOTICE.')) {
      matches.add(name);
    }
  }
  matches.sort();
  return matches;
}

Map<String, Object?> _cycloneDx({
  required String packageVersion,
  required String commit,
  required List<Object?> graph,
  required String graphHash,
}) {
  return {
    'bomFormat': 'CycloneDX',
    'specVersion': '1.5',
    'serialNumber': 'urn:uuid:${graphHash.substring(0, 32)}',
    'version': 1,
    'metadata': {
      'component': {
        'type': 'application',
        'name': 'gift',
        'version': packageVersion,
      },
      'properties': [
        {'name': 'git.commit', 'value': commit},
      ],
    },
    'components': [
      for (final package in graph)
        if ((package as Map<String, Object?>)['source'] != 'sdk')
          {
            'type': 'library',
            'bom-ref': 'pkg:dart/${package['name']}@${package['version']}',
            'name': package['name'],
            'version': package['version'],
            'scope': package['kind'],
            'purl': 'pkg:dart/${package['name']}@${package['version']}',
          },
    ],
  };
}

Future<void> _writeJson(
  Directory directory,
  String name,
  Map<String, Object?> value,
) async {
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}

void _requireArguments(List<String> arguments, int count, String usage) {
  if (arguments.length != count) {
    throw FormatException('Usage: dart run tool/release_metadata.dart $usage');
  }
}

void _usage() {
  stderr.writeln(
    '''Usage:
  dart run tool/release_metadata.dart validate <release-tag>
  dart run tool/release_metadata.dart generate <release-tag> <commit> <artifact-directory> [--require-licenses]
  dart run tool/release_metadata.dart verify <artifact-directory> <checksums-file>''',
  );
}
