import 'dart:convert';
import 'dart:io';

import 'package:oche_benchmark_harness/result_aggregation.dart';

const _implementations = ['raw_dart_io', 'relic', 'oche_static'];
const _endpoints = ['/plaintext', '/json', '/users/42'];

Future<void> main(List<String> arguments) async {
  final options = _SuiteOptions.parse(arguments);
  final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
    RegExp('[:.]'),
    '-',
  );
  final rawTrialFiles = <String>[];

  for (final concurrency in options.concurrencies) {
    for (var iteration = 1; iteration <= options.iterations; iteration++) {
      for (final endpoint in _endpoints) {
        for (final implementation in _implementations) {
          final endpointName = endpoint.substring(1).replaceAll('/', '-');
          final output =
              '${options.resultsDirectory}/$timestamp-$implementation-'
              '$endpointName-c$concurrency-$iteration.json';
          final benchmarkArguments = [
            'run',
            'benchmarks/harness/bin/benchmark.dart',
            '--implementation=$implementation',
            '--mode=${options.mode}',
            '--host=${options.host}',
            '--port=${options.port}',
            '--endpoint=$endpoint',
            '--concurrency=$concurrency',
            '--duration=${options.durationSeconds}',
            '--warmup=${options.warmupSeconds}',
            '--load-generator=${options.loadGenerator}',
            '--oha=${options.ohaPath}',
            '--output=$output',
          ];
          final customExecutable = options.executableFor(implementation);
          if (customExecutable != null) {
            benchmarkArguments.add('--executable=$customExecutable');
          }

          stdout.writeln(
            '[c=$concurrency, $iteration/${options.iterations}] '
            '$implementation $endpoint',
          );
          final process = await Process.start(
            Platform.resolvedExecutable,
            benchmarkArguments,
            mode: ProcessStartMode.inheritStdio,
          );
          final code = await process.exitCode;
          if (code != 0) {
            stderr.writeln('Suite stopped after benchmark exit code $code.');
            exitCode = code;
            return;
          }
          rawTrialFiles.add(output);
        }
      }
    }
  }

  final aggregate = await aggregateResultFiles(rawTrialFiles);
  final aggregateFile = File(
    '${options.resultsDirectory}/$timestamp-aggregate.json',
  );
  await aggregateFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(aggregate)}\n',
  );
  stdout.writeln(
    'Wrote aggregate for ${rawTrialFiles.length} raw trials to '
    '${aggregateFile.path}',
  );
}

final class _SuiteOptions {
  const _SuiteOptions({
    required this.mode,
    required this.host,
    required this.port,
    required this.concurrencies,
    required this.durationSeconds,
    required this.warmupSeconds,
    required this.iterations,
    required this.loadGenerator,
    required this.ohaPath,
    required this.resultsDirectory,
    required this.rawExecutable,
    required this.relicExecutable,
    required this.ocheStaticExecutable,
  });

  final String mode;
  final String host;
  final int port;
  final List<int> concurrencies;
  final int durationSeconds;
  final int warmupSeconds;
  final int iterations;
  final String loadGenerator;
  final String ohaPath;
  final String resultsDirectory;
  final String? rawExecutable;
  final String? relicExecutable;
  final String? ocheStaticExecutable;

  String? executableFor(String implementation) => switch (implementation) {
    'raw_dart_io' => rawExecutable,
    'relic' => relicExecutable,
    'oche_static' => ocheStaticExecutable,
    _ => throw ArgumentError.value(implementation, 'implementation'),
  };

  static _SuiteOptions parse(List<String> arguments) {
    final values = <String, String>{};
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (!argument.startsWith('--')) {
        throw FormatException('Expected an option, got: $argument');
      }
      final equals = argument.indexOf('=');
      if (equals >= 0) {
        values[argument.substring(2, equals)] = argument.substring(equals + 1);
      } else {
        if (index + 1 >= arguments.length) {
          throw FormatException('Missing value for $argument.');
        }
        values[argument.substring(2)] = arguments[++index];
      }
    }

    const known = {
      'mode',
      'host',
      'port',
      'concurrency',
      'concurrency-sweep',
      'duration',
      'warmup',
      'iterations',
      'load-generator',
      'oha',
      'results-dir',
      'raw-executable',
      'relic-executable',
      'oche-static-executable',
    };
    final unknown = values.keys.where((key) => !known.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown options: ${unknown.join(', ')}');
    }

    final mode = values['mode'] ?? 'aot';
    if (mode != 'jit' && mode != 'aot') {
      throw FormatException('--mode must be jit or aot.');
    }
    final loadGenerator = values['load-generator'] ?? 'oha';
    if (loadGenerator != 'oha' && loadGenerator != 'none') {
      throw FormatException('--load-generator must be oha or none.');
    }

    final port = int.parse(values['port'] ?? '8080');
    final concurrency = int.parse(values['concurrency'] ?? '100');
    final concurrencySweep = values['concurrency-sweep'];
    final concurrencies = concurrencySweep == null
        ? [concurrency]
        : concurrencySweep
              .split(',')
              .map((value) => int.parse(value.trim()))
              .toSet()
              .toList();
    final duration = int.parse(values['duration'] ?? '30');
    final warmup = int.parse(values['warmup'] ?? '5');
    final iterations = int.parse(values['iterations'] ?? '5');
    if (port < 1 || port > 65535) {
      throw RangeError.range(port, 1, 65535, 'port');
    }
    if (concurrencies.isEmpty ||
        concurrencies.any((value) => value < 1) ||
        duration < 1 ||
        warmup < 0 ||
        iterations < 1) {
      throw RangeError(
        'concurrency, duration, and iterations must be positive; warmup >= 0.',
      );
    }

    return _SuiteOptions(
      mode: mode,
      host: values['host'] ?? '127.0.0.1',
      port: port,
      concurrencies: concurrencies,
      durationSeconds: duration,
      warmupSeconds: warmup,
      iterations: iterations,
      loadGenerator: loadGenerator,
      ohaPath: values['oha'] ?? 'oha',
      resultsDirectory: values['results-dir'] ?? 'benchmarks/results',
      rawExecutable: values['raw-executable'],
      relicExecutable: values['relic-executable'],
      ocheStaticExecutable: values['oche-static-executable'],
    );
  }
}
