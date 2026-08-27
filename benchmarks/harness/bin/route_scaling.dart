import 'dart:convert';
import 'dart:io';

import 'package:oche_benchmark_harness/numeric_summary.dart';
import 'package:oche_benchmark_harness/route_scaling.dart';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final trials = <_Trial>[];

  for (final routeCount in options.routeCounts) {
    final routes = generateSyntheticRoutes(routeCount);
    final strategies = <SyntheticRouteLookup>[
      LinearRouteLookup(routes),
      SegmentedRouteLookup(routes),
      HashRouteLookup(routes),
    ];
    final queries = _generateQueries(routes);

    for (final strategy in strategies) {
      _executeLookups(strategy, queries, options.warmupLookups);
    }

    for (var iteration = 1; iteration <= options.iterations; iteration++) {
      for (var offset = 0; offset < strategies.length; offset++) {
        final strategy = strategies[(offset + iteration) % strategies.length];
        final watch = Stopwatch()..start();
        final checksum = _executeLookups(
          strategy,
          queries,
          options.lookupsPerTrial,
        );
        watch.stop();
        final elapsedSeconds = watch.elapsedTicks / watch.frequency;
        trials.add(
          _Trial(
            routeCount: routeCount,
            strategy: strategy.name,
            iteration: iteration,
            lookups: options.lookupsPerTrial,
            elapsedMicroseconds: watch.elapsedMicroseconds,
            lookupsPerSecond: options.lookupsPerTrial / elapsedSeconds,
            nanosecondsPerLookup:
                elapsedSeconds * 1000000000 / options.lookupsPerTrial,
            checksum: checksum,
          ),
        );
      }
    }
  }

  final output = <String, Object>{
    'schemaVersion': 1,
    'kind': 'oche-static-route-scaling',
    'timestampUtc': DateTime.now().toUtc().toIso8601String(),
    'runtime': Platform.version,
    'configuration': {
      'routeCounts': options.routeCounts,
      'lookupsPerTrial': options.lookupsPerTrial,
      'warmupLookups': options.warmupLookups,
      'iterations': options.iterations,
      'queryCount': 1024,
      'hitRatio': 0.9,
    },
    'trials': trials.map((trial) => trial.toJson()).toList(),
    'aggregates': _aggregate(trials),
  };
  final encoded = const JsonEncoder.withIndent('  ').convert(output);
  if (options.outputPath case final path?) {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('$encoded\n');
    stdout.writeln('Wrote route-scaling results to ${file.path}');
  } else {
    stdout.writeln(encoded);
  }
}

List<String> _generateQueries(List<String> routes) => List.generate(
  1024,
  (index) => index % 10 == 0
      ? '/missing/route$index'
      : routes[(index * 31) % routes.length],
  growable: false,
);

int _executeLookups(
  SyntheticRouteLookup strategy,
  List<String> queries,
  int lookups,
) {
  var checksum = 0;
  for (var index = 0; index < lookups; index++) {
    checksum += strategy.lookup(queries[index & 1023]);
  }
  return checksum;
}

List<Map<String, Object>> _aggregate(List<_Trial> trials) {
  final groups = <({int routeCount, String strategy}), List<_Trial>>{};
  for (final trial in trials) {
    final key = (routeCount: trial.routeCount, strategy: trial.strategy);
    groups.putIfAbsent(key, () => []).add(trial);
  }
  final entries = groups.entries.toList()
    ..sort((left, right) {
      final countComparison = left.key.routeCount.compareTo(
        right.key.routeCount,
      );
      return countComparison != 0
          ? countComparison
          : left.key.strategy.compareTo(right.key.strategy);
    });
  return entries.map((entry) {
    final throughput = summarizeNumbers(
      entry.value.map((trial) => trial.lookupsPerSecond),
    );
    final latency = summarizeNumbers(
      entry.value.map((trial) => trial.nanosecondsPerLookup),
    );
    return <String, Object>{
      'routeCount': entry.key.routeCount,
      'strategy': entry.key.strategy,
      'trialCount': entry.value.length,
      'lookupsPerSecond': throughput!.toJson(),
      'nanosecondsPerLookup': latency!.toJson(),
    };
  }).toList();
}

final class _Trial {
  const _Trial({
    required this.routeCount,
    required this.strategy,
    required this.iteration,
    required this.lookups,
    required this.elapsedMicroseconds,
    required this.lookupsPerSecond,
    required this.nanosecondsPerLookup,
    required this.checksum,
  });

  final int routeCount;
  final String strategy;
  final int iteration;
  final int lookups;
  final int elapsedMicroseconds;
  final double lookupsPerSecond;
  final double nanosecondsPerLookup;
  final int checksum;

  Map<String, Object> toJson() => {
    'routeCount': routeCount,
    'strategy': strategy,
    'iteration': iteration,
    'lookups': lookups,
    'elapsedMicroseconds': elapsedMicroseconds,
    'lookupsPerSecond': lookupsPerSecond,
    'nanosecondsPerLookup': nanosecondsPerLookup,
    'checksum': checksum,
  };
}

final class _Options {
  const _Options({
    required this.routeCounts,
    required this.lookupsPerTrial,
    required this.warmupLookups,
    required this.iterations,
    required this.outputPath,
  });

  final List<int> routeCounts;
  final int lookupsPerTrial;
  final int warmupLookups;
  final int iterations;
  final String? outputPath;

  static _Options parse(List<String> arguments) {
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
    const known = {
      'route-counts',
      'lookups',
      'warmup-lookups',
      'iterations',
      'output',
    };
    final unknown = values.keys.where((key) => !known.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown options: ${unknown.join(', ')}');
    }

    final routeCounts =
        (values['route-counts'] ?? '10,100,1000')
            .split(',')
            .map((value) => int.parse(value.trim()))
            .toSet()
            .toList()
          ..sort();
    final lookups = int.parse(values['lookups'] ?? '200000');
    final warmup = int.parse(values['warmup-lookups'] ?? '20000');
    final iterations = int.parse(values['iterations'] ?? '5');
    if (routeCounts.isEmpty ||
        routeCounts.any((value) => value < 1) ||
        lookups < 1 ||
        warmup < 0 ||
        iterations < 1) {
      throw RangeError(
        'route counts, lookups, and iterations must be positive; warmup >= 0.',
      );
    }
    return _Options(
      routeCounts: routeCounts,
      lookupsPerTrial: lookups,
      warmupLookups: warmup,
      iterations: iterations,
      outputPath: values['output'],
    );
  }
}
