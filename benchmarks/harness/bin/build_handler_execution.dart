import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:handler_execution_benchmark/handler_execution_benchmark.dart';
import 'package:handler_execution_benchmark/handler_source_generator.dart';

Future<void> main(List<String> arguments) async {
  final options = _BuildOptions.parse(arguments);
  final generatedDirectory = Directory(options.generatedDirectory);
  final outputDirectory = Directory(options.outputDirectory);
  await generatedDirectory.create(recursive: true);
  await outputDirectory.create(recursive: true);

  final entries = <Map<String, Object>>[
    await _compile(
      implementation: 'handler_raw',
      sourcePath: 'benchmarks/handler_execution/bin/raw_server.dart',
      outputPath: '${outputDirectory.path}/handler_raw${_suffix()}',
    ),
  ];
  for (final candidate in HandlerCandidate.values) {
    for (final routeCount in const [10, 100, 1000]) {
      final sourcePath =
          '${generatedDirectory.path}/${handlerSourceStem(candidate)}'
          '_$routeCount.dart';
      final source = File(sourcePath);
      await source.writeAsString(generateHandlerSource(candidate, routeCount));
      await _format(source);
      entries.add(
        await _compile(
          implementation: handlerImplementationName(candidate),
          routeCount: routeCount,
          sourcePath: sourcePath,
          outputPath:
              '${outputDirectory.path}/${handlerImplementationName(candidate)}'
              '_$routeCount${_suffix()}',
        ),
      );
    }
  }
  entries.add(
    await _compile(
      implementation: 'handler_microbenchmark',
      sourcePath:
          'benchmarks/handler_execution/bin/execution_microbenchmark.dart',
      outputPath:
          '${outputDirectory.path}/execution_microbenchmark${_suffix()}',
    ),
  );

  final manifest = <String, Object>{
    'schemaVersion': 1,
    'kind': 'oche-handler-execution-build',
    'timestampUtc': DateTime.now().toUtc().toIso8601String(),
    'platform': Platform.operatingSystem,
    'dartVersion': Platform.version,
    'entries': entries,
  };
  final manifestFile = File(options.manifestPath);
  await manifestFile.parent.create(recursive: true);
  await manifestFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
  stdout.writeln('Wrote build measurements to ${manifestFile.path}');
}

Future<Map<String, Object>> _compile({
  required String implementation,
  required String sourcePath,
  required String outputPath,
  int? routeCount,
}) async {
  final source = File(sourcePath);
  final supportSource = File(
    'benchmarks/handler_execution/lib/handler_execution_benchmark.dart',
  );
  if (!source.existsSync()) throw StateError('Source not found: $sourcePath');
  if (!supportSource.existsSync()) {
    throw StateError('Support source not found: ${supportSource.path}');
  }
  stdout.writeln('Compiling $implementation ${routeCount ?? "baseline"}...');
  final watch = Stopwatch()..start();
  final result = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'exe',
    sourcePath,
    '-o',
    outputPath,
  ]);
  watch.stop();
  if (result.exitCode != 0) {
    throw StateError(
      'Compilation failed for $sourcePath.\n'
      'stdout: ${result.stdout}\nstderr: ${result.stderr}',
    );
  }
  stdout.write(result.stdout);
  final executable = File(outputPath);
  return {
    'implementation': implementation,
    'routeCount': ?routeCount,
    'sourcePath': sourcePath,
    'sourceSha256': await _sha256(source),
    'supportSourcePath': supportSource.path,
    'supportSourceSha256': await _sha256(supportSource),
    'generatedSourceBytes': source.lengthSync(),
    'generatedSourceLines': source.readAsLinesSync().length,
    'compileDurationMs': watch.elapsedMicroseconds / 1000,
    'executablePath': outputPath,
    'executableSha256': await _sha256(executable),
    'executableBytes': executable.lengthSync(),
  };
}

Future<void> _format(File file) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'format',
    file.path,
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'Formatting failed for ${file.path}.\n'
      'stdout: ${result.stdout}\nstderr: ${result.stderr}',
    );
  }
}

Future<String> _sha256(File file) async =>
    sha256.bind(file.openRead()).first.then((digest) => digest.toString());

String _suffix() => Platform.isWindows ? '.exe' : '';

final class _BuildOptions {
  const _BuildOptions({
    required this.generatedDirectory,
    required this.outputDirectory,
    required this.manifestPath,
  });

  final String generatedDirectory;
  final String outputDirectory;
  final String manifestPath;

  static _BuildOptions parse(List<String> arguments) {
    final values = <String, String>{};
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (!argument.startsWith('--')) {
        throw FormatException('Expected an option, got: $argument');
      }
      final equals = argument.indexOf('=');
      if (equals >= 0) {
        values[argument.substring(2, equals)] = argument.substring(equals + 1);
      } else if (index + 1 < arguments.length) {
        values[argument.substring(2)] = arguments[++index];
      } else {
        throw FormatException('Missing value for $argument.');
      }
    }
    const known = {'generated-dir', 'output-dir', 'manifest'};
    final unknown = values.keys.where((key) => !known.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown options: ${unknown.join(', ')}');
    }
    return _BuildOptions(
      generatedDirectory:
          values['generated-dir'] ?? 'benchmarks/handler_execution/generated',
      outputDirectory: values['output-dir'] ?? 'build/handler_execution',
      manifestPath:
          values['manifest'] ??
          'benchmarks/results/phase1b-build-${Platform.operatingSystem}.json',
    );
  }
}
