import 'dart:convert';
import 'dart:io';

import 'package:oche_benchmark_harness/benchmark_schedule.dart';
import 'package:oche_benchmark_harness/result_aggregation.dart';

const _workloads = <_Workload>[
  _Workload('public_sync_int', '/users/42'),
  _Workload('public_async_int', '/async/sync/42'),
];

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final build = _Build.read(options.manifestPath);
  final runId =
      options.runId ??
      DateTime.now().toUtc().toIso8601String().replaceAll(RegExp('[:.]'), '-');
  final directory = Directory('${options.resultsDirectory}/phase2a-$runId');
  await directory.create(recursive: true);
  final files = <String>[];
  var sequence = 0;
  final total =
      options.concurrencies.length * options.iterations * _workloads.length;

  for (final concurrency in options.concurrencies) {
    for (var iteration = 1; iteration <= options.iterations; iteration++) {
      final workloads = balancedOrder(_workloads, iteration);
      final endpointOrder = workloads
          .map((workload) => 'GET ${workload.endpoint}')
          .toList(growable: false);
      for (
        var endpointIndex = 0;
        endpointIndex < workloads.length;
        endpointIndex++
      ) {
        final workload = workloads[endpointIndex];
        sequence++;
        final output =
            '${directory.path}/${workload.name}-c$concurrency-i$iteration.json';
        stdout.writeln(
          '[$sequence/$total, c=$concurrency, '
          'iteration=$iteration/${options.iterations}] '
          'GET ${workload.endpoint}',
        );
        final benchmarkArguments = <String>[
          'run',
          'benchmarks/harness/bin/benchmark.dart',
          '--implementation=oche_public_phase2a',
          '--mode=aot',
          '--host=${options.host}',
          '--port=${options.port}',
          '--endpoint=${workload.endpoint}',
          '--readiness-endpoint=/hello',
          '--method=GET',
          '--expected-status=200',
          '--route-count=11',
          '--workload=${workload.name}',
          '--middleware-depth=0',
          '--middleware-profile=depth_zero',
          '--concurrency=$concurrency',
          '--duration=${options.durationSeconds}',
          '--warmup=${options.warmupSeconds}',
          '--load-generator=oha',
          '--oha=${options.ohaPath}',
          '--output=$output',
          '--executable=${build.executablePath}',
          '--generated-source=${build.sourcePath}',
          '--compile-duration-ms=${build.compileDurationMs}',
        ];
        stdout.writeln('endpoint order: ${endpointOrder.join(', ')}');
        final process = await Process.start(
          Platform.resolvedExecutable,
          benchmarkArguments,
          mode: ProcessStartMode.inheritStdio,
        );
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
  final output = File('${directory.path}/phase2a-$runId-aggregate.json');
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(aggregate)}\n',
  );
  stdout.writeln('Wrote ${output.path} from ${files.length} trials.');
}

final class _Workload {
  const _Workload(this.name, this.endpoint);

  final String name;
  final String endpoint;
}

final class _Build {
  const _Build({
    required this.sourcePath,
    required this.executablePath,
    required this.compileDurationMs,
  });

  factory _Build.read(String path) {
    final value = jsonDecode(File(path).readAsStringSync());
    if (value is! Map<String, Object?> ||
        value['kind'] != 'oche-public-application-build') {
      throw FormatException('Invalid Phase 2A build manifest: $path');
    }
    return _Build(
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
    required this.manifestPath,
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
    final concurrencies = (values['concurrency-sweep'] ?? '10,100,500')
        .split(',')
        .map(int.parse)
        .toList(growable: false);
    return _Options(
      host: values['host'] ?? '127.0.0.1',
      port: integer('port', 8080),
      concurrencies: concurrencies,
      warmupSeconds: integer('warmup', 5),
      durationSeconds: integer('duration', 30),
      iterations: integer('iterations', 5),
      cooldownSeconds: integer('cooldown', 2),
      ohaPath: values['oha'] ?? 'oha',
      resultsDirectory:
          values['results-dir'] ?? 'benchmarks/results/phase2a-windows',
      manifestPath:
          values['manifest'] ?? 'build/phase2a/public-application-build.json',
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
  final String manifestPath;
  final String? runId;
}
