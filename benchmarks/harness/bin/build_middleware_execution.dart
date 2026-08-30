import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:handler_execution_benchmark/middleware_execution_benchmark.dart';
import 'package:handler_execution_benchmark/middleware_source_generator.dart';

const _supportPaths = <String>[
  'benchmarks/handler_execution/lib/handler_execution_benchmark.dart',
  'benchmarks/handler_execution/lib/middleware_execution_benchmark.dart',
];

Future<void> main(List<String> arguments) async {
  final options = _BuildOptions.parse(arguments);
  final generatedDirectory = Directory(options.generatedDirectory);
  final outputDirectory = Directory(options.outputDirectory);
  await generatedDirectory.create(recursive: true);
  await outputDirectory.create(recursive: true);

  final entries = <Map<String, Object>>[
    await _compile(
      implementation: 'middleware_raw',
      sourcePath: 'benchmarks/handler_execution/bin/middleware_raw_server.dart',
      outputPath: '${outputDirectory.path}/middleware_raw${_suffix()}',
    ),
  ];
  for (final candidate in MiddlewareCandidate.values) {
    for (final routeCount in const [10, 100, 1000]) {
      final depths = candidate == MiddlewareCandidate.phase1b
          ? const [0]
          : routeCount == 100
          ? middlewareDepths
          : const [0, 1, 3];
      for (final depth in depths) {
        final sourcePath =
            '${generatedDirectory.path}/${middlewareSourceStem(candidate)}_'
            'r${routeCount}_d$depth.dart';
        final source = File(sourcePath);
        await source.writeAsString(
          generateMiddlewareSource(candidate, routeCount, depth),
        );
        await _format(source);
        final implementation = middlewareImplementationName(candidate);
        entries.add(
          await _compile(
            implementation: implementation,
            routeCount: routeCount,
            middlewareDepth: depth,
            sourcePath: sourcePath,
            outputPath:
                '${outputDirectory.path}/${implementation}_r${routeCount}_'
                'd$depth${_suffix()}',
          ),
        );
      }
    }
  }
  entries.add(
    await _compile(
      implementation: 'middleware_microbenchmark',
      sourcePath:
          'benchmarks/handler_execution/bin/middleware_microbenchmark.dart',
      outputPath:
          '${outputDirectory.path}/middleware_microbenchmark${_suffix()}',
      supportPaths: const [],
    ),
  );

  final manifest = <String, Object>{
    'schemaVersion': 1,
    'kind': 'oche-middleware-execution-build',
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
  int? middlewareDepth,
  List<String> supportPaths = _supportPaths,
}) async {
  final source = File(sourcePath);
  if (!source.existsSync()) throw StateError('Source not found: $sourcePath');
  final supportSources = <Map<String, Object>>[];
  for (final path in supportPaths) {
    final file = File(path);
    if (!file.existsSync()) throw StateError('Support source not found: $path');
    supportSources.add({'path': path, 'sha256': await _sha256(file)});
  }

  stdout.writeln(
    'Compiling $implementation r=${routeCount ?? "baseline"} '
    'd=${middlewareDepth ?? "baseline"}...',
  );
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
    'middlewareDepth': ?middlewareDepth,
    'sourcePath': sourcePath,
    'sourceSha256': await _sha256(source),
    'supportSources': supportSources,
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
    throw StateError('Formatting failed for ${file.path}: ${result.stderr}');
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
          values['generated-dir'] ??
          'benchmarks/handler_execution/generated_middleware',
      outputDirectory: values['output-dir'] ?? 'build/middleware_execution',
      manifestPath:
          values['manifest'] ??
          'benchmarks/results/phase1c-build-${Platform.operatingSystem}.json',
    );
  }
}
