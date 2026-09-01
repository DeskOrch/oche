import 'dart:convert';
import 'dart:io';

import 'package:oche_benchmark_harness/benchmark_schedule.dart';
import 'package:oche_benchmark_harness/result_aggregation.dart';

const _implementationNames = <String>[
  'raw_dart_io',
  'relic',
  'oche_public_phase2a',
];

const _workloads = <_Workload>[
  _Workload('linux_sync', '/validation/sync'),
  _Workload('linux_async', '/validation/async'),
  _Workload('linux_typed_int', '/validation/users/42'),
];

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final publicBuild = _PublicBuild.read(options.publicManifestPath);
  final implementations = <String, _Implementation>{
    'raw_dart_io': _Implementation(
      name: 'raw_dart_io',
      executablePath: options.rawExecutablePath,
    ),
    'relic': _Implementation(
      name: 'relic',
      executablePath: options.relicExecutablePath,
    ),
    'oche_public_phase2a': _Implementation(
      name: 'oche_public_phase2a',
      executablePath: publicBuild.executablePath,
      generatedSourcePath: publicBuild.sourcePath,
      compileDurationMs: publicBuild.compileDurationMs,
    ),
  };
  for (final implementation in implementations.values) {
    implementation.validate();
  }

  final runId =
      options.runId ??
      DateTime.now().toUtc().toIso8601String().replaceAll(RegExp('[:.]'), '-');
  final directory = Directory('${options.resultsDirectory}/$runId');
  await directory.create(recursive: true);
  final rawTrialFiles = <String>[];
  var trialSequence = 0;
  final totalTrials =
      options.concurrencies.length *
      options.iterations *
      _workloads.length *
      _implementationNames.length;

  for (final concurrency in options.concurrencies) {
    for (var iteration = 1; iteration <= options.iterations; iteration++) {
      final implementationOrder = balancedThreeWayOrder(
        _implementationNames,
        iteration,
      );
      final workloadOrder = balancedThreeWayOrder(_workloads, iteration);
      final endpointOrder = workloadOrder
          .map((workload) => 'GET ${workload.endpoint}')
          .toList(growable: false);

      for (
        var workloadIndex = 0;
        workloadIndex < workloadOrder.length;
        workloadIndex++
      ) {
        final workload = workloadOrder[workloadIndex];
        for (
          var implementationIndex = 0;
          implementationIndex < implementationOrder.length;
          implementationIndex++
        ) {
          final implementation =
              implementations[implementationOrder[implementationIndex]]!;
          trialSequence++;
          final output =
              '${directory.path}/${implementation.name}-${workload.name}-'
              'c$concurrency-i$iteration.json';
          stdout.writeln(
            '[$trialSequence/$totalTrials, c=$concurrency, '
            'iteration=$iteration/${options.iterations}] '
            '${implementation.name} GET ${workload.endpoint}',
          );

          final process = await Process.start(Platform.resolvedExecutable, [
            'run',
            'benchmarks/harness/bin/benchmark.dart',
            '--implementation=${implementation.name}',
            '--mode=aot',
            '--host=${options.host}',
            '--port=${options.port}',
            '--endpoint=${workload.endpoint}',
            '--readiness-endpoint=/validation/sync',
            '--method=GET',
            '--expected-status=200',
            '--workload=${workload.name}',
            '--concurrency=$concurrency',
            '--duration=${options.durationSeconds}',
            '--warmup=${options.warmupSeconds}',
            '--load-generator=oha',
            '--oha=${options.ohaPath}',
            '--output=$output',
            '--suite-run-id=$runId',
            '--iteration=$iteration',
            '--trial-sequence=$trialSequence',
            '--implementation-order=${implementationOrder.join(',')}',
            '--implementation-position=${implementationIndex + 1}',
            '--endpoint-order=${endpointOrder.join(',')}',
            '--endpoint-position=${workloadIndex + 1}',
            '--cooldown=${options.cooldownSeconds}',
            '--environment-type=${options.environmentType}',
            '--executable=${implementation.executablePath}',
            if (implementation.generatedSourcePath case final source?)
              '--generated-source=$source',
            if (implementation.compileDurationMs case final duration?)
              '--compile-duration-ms=$duration',
          ], mode: ProcessStartMode.inheritStdio);
          final code = await process.exitCode;
          if (code != 0) {
            stderr.writeln(
              'Linux validation stopped after benchmark exit code $code.',
            );
            exitCode = code;
            return;
          }
          rawTrialFiles.add(output);
          if (options.cooldownSeconds > 0 && trialSequence < totalTrials) {
            await Future<void>.delayed(
              Duration(seconds: options.cooldownSeconds),
            );
          }
        }
      }
    }
  }

  final aggregate = await aggregateResultFiles(rawTrialFiles);
  _requireRawNormalization(aggregate);
  aggregate['linuxValidationGate'] = <String, Object>{
    'environmentType': options.environmentType,
    'implementations': _implementationNames,
    'workloads': [
      for (final workload in _workloads)
        {'name': workload.name, 'endpoint': workload.endpoint},
    ],
    'protocol': {
      'concurrency': options.concurrencies,
      'warmupSeconds': options.warmupSeconds,
      'measurementSeconds': options.durationSeconds,
      'iterations': options.iterations,
      'cooldownSeconds': options.cooldownSeconds,
    },
    'publicBuildManifest': options.publicManifestPath,
  };
  final aggregateFile = File('${directory.path}/$runId-aggregate.json');
  await aggregateFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(aggregate)}\n',
  );
  stdout.writeln(
    'Wrote Linux validation aggregate for ${rawTrialFiles.length} trials to '
    '${aggregateFile.path}',
  );
}

void _requireRawNormalization(Map<String, Object> aggregate) {
  final groups = aggregate['groups'];
  if (groups is! List<Object?>) {
    throw StateError('Linux validation aggregate has no groups.');
  }
  for (final value in groups) {
    if (value is! Map<String, Object>) {
      throw StateError('Linux validation aggregate contains an invalid group.');
    }
    if (value['implementation'] != 'raw_dart_io' &&
        value['relativeToRaw'] == null) {
      throw StateError(
        'Missing raw normalization for ${value['implementation']} '
        '${value['workload']} at c=${value['concurrency']}.',
      );
    }
  }
}

final class _Workload {
  const _Workload(this.name, this.endpoint);

  final String name;
  final String endpoint;
}

final class _Implementation {
  const _Implementation({
    required this.name,
    required this.executablePath,
    this.generatedSourcePath,
    this.compileDurationMs,
  });

  final String name;
  final String executablePath;
  final String? generatedSourcePath;
  final double? compileDurationMs;

  void validate() {
    for (final path in [executablePath, ?generatedSourcePath]) {
      if (!File(path).existsSync()) {
        throw StateError('Linux validation input is missing: $path');
      }
    }
  }
}

final class _PublicBuild {
  const _PublicBuild({
    required this.sourcePath,
    required this.executablePath,
    required this.compileDurationMs,
  });

  factory _PublicBuild.read(String path) {
    final value = jsonDecode(File(path).readAsStringSync());
    if (value is! Map<String, Object?> ||
        value['kind'] != 'oche-public-application-build') {
      throw FormatException('Invalid public application build manifest: $path');
    }
    return _PublicBuild(
      sourcePath: value['sourcePath']! as String,
      executablePath: value['executablePath']! as String,
      compileDurationMs: (value['compileDurationMs']! as num).toDouble(),
    );
  }

  final String sourcePath;
  final String executablePath;
  final double compileDurationMs;
}

final class _Options {
  const _Options({
    required this.host,
    required this.port,
    required this.concurrencies,
    required this.warmupSeconds,
    required this.durationSeconds,
    required this.iterations,
    required this.cooldownSeconds,
    required this.ohaPath,
    required this.resultsDirectory,
    required this.rawExecutablePath,
    required this.relicExecutablePath,
    required this.publicManifestPath,
    required this.environmentType,
    required this.runId,
  });

  factory _Options.parse(List<String> arguments) {
    final values = <String, String>{};
    for (final argument in arguments) {
      if (!argument.startsWith('--') || !argument.contains('=')) {
        throw FormatException('Expected --name=value, got $argument');
      }
      final separator = argument.indexOf('=');
      values[argument.substring(2, separator)] = argument.substring(
        separator + 1,
      );
    }
    const known = <String>{
      'host',
      'port',
      'concurrency-sweep',
      'warmup',
      'duration',
      'iterations',
      'cooldown',
      'oha',
      'results-dir',
      'raw-executable',
      'relic-executable',
      'public-manifest',
      'environment-type',
      'run-id',
    };
    final unknown = values.keys.where((key) => !known.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown options: ${unknown.join(', ')}');
    }
    int integer(String name, int fallback) =>
        int.parse(values[name] ?? '$fallback');
    final concurrencies = (values['concurrency-sweep'] ?? '10,100,500')
        .split(',')
        .map((value) => int.parse(value.trim()))
        .toSet()
        .toList(growable: false);
    final port = integer('port', 8080);
    final warmup = integer('warmup', 5);
    final duration = integer('duration', 30);
    final iterations = integer('iterations', 5);
    final cooldown = integer('cooldown', 2);
    if (port < 1 || port > 65535) {
      throw RangeError.range(port, 1, 65535, 'port');
    }
    if (concurrencies.isEmpty ||
        concurrencies.any((value) => value < 1) ||
        warmup < 0 ||
        duration < 1 ||
        iterations < 1 ||
        cooldown < 0) {
      throw RangeError(
        'Concurrency, duration, and iterations must be positive; '
        'warmup and cooldown must be non-negative.',
      );
    }
    final suffix = Platform.isWindows ? '.exe' : '';
    return _Options(
      host: values['host'] ?? '127.0.0.1',
      port: port,
      concurrencies: concurrencies,
      warmupSeconds: warmup,
      durationSeconds: duration,
      iterations: iterations,
      cooldownSeconds: cooldown,
      ohaPath: values['oha'] ?? 'oha',
      resultsDirectory:
          values['results-dir'] ?? 'benchmarks/results/linux-validation',
      rawExecutablePath:
          values['raw-executable'] ??
          'build/linux-validation/raw_dart_io$suffix',
      relicExecutablePath:
          values['relic-executable'] ?? 'build/linux-validation/relic$suffix',
      publicManifestPath:
          values['public-manifest'] ??
          'build/linux-validation/public-application-build.json',
      environmentType: values['environment-type'] ?? 'Hyper-V VM',
      runId: values['run-id'],
    );
  }

  final String host;
  final int port;
  final List<int> concurrencies;
  final int warmupSeconds;
  final int durationSeconds;
  final int iterations;
  final int cooldownSeconds;
  final String ohaPath;
  final String resultsDirectory;
  final String rawExecutablePath;
  final String relicExecutablePath;
  final String publicManifestPath;
  final String environmentType;
  final String? runId;
}
