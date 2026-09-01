import 'dart:convert';
import 'dart:io';

import 'package:oche_benchmark_harness/benchmark_schedule.dart';
import 'package:oche_benchmark_harness/result_aggregation.dart';

const _groups = <_Group>[
  _Group('sync_c100', '/users/42', 'sync', 100),
  _Group('sync_c500', '/users/42', 'sync', 500),
  _Group('async_c500', '/async/sync/42', 'async', 500),
];
const _implementationOrder = [
  'oche_public_phase2a',
  'response_lifecycle',
  'middleware_raw',
];

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final publicBuild = _PublicBuild.read(options.publicManifestPath);
  final lifecycle = _Implementation(
    name: 'response_lifecycle',
    executablePath: 'build/middleware_execution/response_lifecycle_r100_d3.exe',
    sourcePath:
        'benchmarks/handler_execution/generated_middleware/'
        'lifecycle_r100_d3.dart',
    middlewareDepth: 3,
    middlewareProfile: 'phase1e_reference',
  );
  final public = _Implementation(
    name: 'oche_public_phase2a',
    executablePath: publicBuild.executablePath,
    sourcePath: publicBuild.sourcePath,
    middlewareDepth: 0,
    middlewareProfile: 'depth_zero',
    compileDurationMs: publicBuild.compileDurationMs,
  );
  const raw = _Implementation(
    name: 'middleware_raw',
    executablePath: 'build/middleware_execution/middleware_raw.exe',
    sourcePath: 'benchmarks/handler_execution/bin/middleware_raw_server.dart',
    middlewareDepth: 0,
    middlewareProfile: 'raw_dart_io',
  );
  final implementations = <String, _Implementation>{
    for (final implementation in [public, lifecycle, raw])
      implementation.name: implementation,
  };
  for (final implementation in implementations.values) {
    implementation.validate();
  }

  final runId = options.runId;
  final directory = Directory('${options.resultsDirectory}/focused-$runId');
  await directory.create(recursive: true);
  final files = <String>[];
  var sequence = 0;
  final total =
      _groups.length * options.iterations * _implementationOrder.length;

  for (final group in _groups) {
    for (var iteration = 1; iteration <= options.iterations; iteration++) {
      final order = balancedOrder(_implementationOrder, iteration);
      for (var position = 0; position < order.length; position++) {
        final implementation = implementations[order[position]]!;
        sequence++;
        final output =
            '${directory.path}/${implementation.name}-${group.name}-'
            'i$iteration.json';
        stdout.writeln(
          '[$sequence/$total, ${group.name}, '
          'iteration=$iteration/${options.iterations}] '
          '${implementation.name}',
        );
        final process = await Process.start(Platform.resolvedExecutable, [
          'run',
          'benchmarks/harness/bin/benchmark.dart',
          '--implementation=${implementation.name}',
          '--mode=aot',
          '--host=127.0.0.1',
          '--port=${options.port}',
          '--endpoint=${group.endpoint}',
          '--readiness-endpoint=${implementation.name == public.name ? '/hello' : '/health'}',
          '--method=GET',
          '--expected-status=200',
          '--route-count=${implementation.name == public.name ? 11 : 100}',
          '--workload=focused_${group.profile}',
          '--middleware-depth=${implementation.middlewareDepth}',
          '--middleware-profile=${implementation.middlewareProfile}',
          '--concurrency=${group.concurrency}',
          '--duration=${options.durationSeconds}',
          '--warmup=${options.warmupSeconds}',
          '--load-generator=oha',
          '--oha=${options.ohaPath}',
          '--output=$output',
          '--suite-run-id=$runId-${group.name}',
          '--iteration=$iteration',
          '--trial-sequence=$sequence',
          '--implementation-order=${order.join(',')}',
          '--implementation-position=${position + 1}',
          '--endpoint-order=GET ${group.endpoint}',
          '--endpoint-position=1',
          '--cooldown=${options.cooldownSeconds}',
          '--executable=${implementation.executablePath}',
          '--generated-source=${implementation.sourcePath}',
          if (implementation.compileDurationMs case final duration?)
            '--compile-duration-ms=$duration',
        ], mode: ProcessStartMode.inheritStdio);
        final code = await process.exitCode;
        if (code != 0) {
          exitCode = code;
          return;
        }
        files.add(output);
        if (options.cooldownSeconds > 0 && sequence < total) {
          await Future<void>.delayed(
            Duration(seconds: options.cooldownSeconds),
          );
        }
      }
    }
  }

  final aggregate = await aggregateResultFiles(files);
  aggregate['pairedRetention'] = await _pairedRetention(files);
  final output = File('${directory.path}/focused-$runId-aggregate.json');
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(aggregate)}\n',
  );
  stdout.writeln('Wrote ${output.path} from ${files.length} trials.');
}

Future<List<Map<String, Object>>> _pairedRetention(List<String> files) async {
  final trials =
      <
        ({
          String workload,
          int concurrency,
          int iteration,
          String implementation,
          double requestsPerSecond,
        })
      >[];
  for (final path in files) {
    final json = jsonDecode(await File(path).readAsString());
    if (json is! Map<String, Object?>) {
      throw FormatException('Invalid focused benchmark result: $path');
    }
    final schedule = json['schedule'];
    if (schedule is! Map<String, Object?>) {
      throw FormatException('Missing focused schedule: $path');
    }
    trials.add((
      workload: json['workload']! as String,
      concurrency: json['concurrency']! as int,
      iteration: schedule['iteration']! as int,
      implementation: json['implementation']! as String,
      requestsPerSecond: (json['requestsPerSecond']! as num).toDouble(),
    ));
  }

  final groupKeys =
      {for (final trial in trials) (trial.workload, trial.concurrency)}.toList()
        ..sort((left, right) {
          final workload = left.$1.compareTo(right.$1);
          return workload != 0 ? workload : left.$2.compareTo(right.$2);
        });
  final comparisons = <Map<String, Object>>[];
  for (final key in groupKeys) {
    final phase1e = <double>[];
    final raw = <double>[];
    final group = trials
        .where(
          (trial) => trial.workload == key.$1 && trial.concurrency == key.$2,
        )
        .toList();
    final iterations = group.map((trial) => trial.iteration).toSet().toList()
      ..sort();
    for (final iteration in iterations) {
      final values = {
        for (final trial in group.where(
          (trial) => trial.iteration == iteration,
        ))
          trial.implementation: trial.requestsPerSecond,
      };
      final public = values['oche_public_phase2a'];
      final lifecycle = values['response_lifecycle'];
      final rawValue = values['middleware_raw'];
      if (public == null || lifecycle == null || rawValue == null) {
        throw StateError(
          'Focused ${key.$1}/c${key.$2}/i$iteration is incomplete.',
        );
      }
      phase1e.add(100 * public / lifecycle);
      raw.add(100 * public / rawValue);
    }
    comparisons.add({
      'workload': key.$1,
      'concurrency': key.$2,
      'pairedIterationCount': iterations.length,
      'publicThroughputPercentOfPhase1E': _median(phase1e),
      'publicThroughputPercentOfRaw': _median(raw),
    });
  }
  return comparisons;
}

double _median(List<double> values) {
  final sorted = values.toList()..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

final class _Group {
  const _Group(this.name, this.endpoint, this.profile, this.concurrency);

  final String name;
  final String endpoint;
  final String profile;
  final int concurrency;
}

final class _Implementation {
  const _Implementation({
    required this.name,
    required this.executablePath,
    required this.sourcePath,
    required this.middlewareDepth,
    required this.middlewareProfile,
    this.compileDurationMs,
  });

  final String name;
  final String executablePath;
  final String sourcePath;
  final int middlewareDepth;
  final String middlewareProfile;
  final double? compileDurationMs;

  void validate() {
    for (final path in [executablePath, sourcePath]) {
      if (!File(path).existsSync()) {
        throw StateError('Focused comparison input is missing: $path');
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
      throw FormatException('Invalid Phase 2A build manifest: $path');
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
    required this.port,
    required this.warmupSeconds,
    required this.durationSeconds,
    required this.iterations,
    required this.cooldownSeconds,
    required this.ohaPath,
    required this.resultsDirectory,
    required this.publicManifestPath,
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
    int integer(String name, int fallback) =>
        int.parse(values[name] ?? '$fallback');
    return _Options(
      port: integer('port', 8080),
      warmupSeconds: integer('warmup', 5),
      durationSeconds: integer('duration', 30),
      iterations: integer('iterations', 10),
      cooldownSeconds: integer('cooldown', 2),
      ohaPath: values['oha'] ?? 'oha',
      resultsDirectory:
          values['results-dir'] ?? 'benchmarks/results/phase2a-windows',
      publicManifestPath:
          values['public-manifest'] ??
          'build/phase2a/public-application-build.json',
      runId: values['run-id'] ?? 'phase2a-focused',
    );
  }

  final int port;
  final int warmupSeconds;
  final int durationSeconds;
  final int iterations;
  final int cooldownSeconds;
  final String ohaPath;
  final String resultsDirectory;
  final String publicManifestPath;
  final String runId;
}
