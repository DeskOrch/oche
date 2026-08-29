import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:handler_execution_benchmark/handler_execution_benchmark.dart';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final measurements = <Map<String, Object>>[];

  final syncCases = <String, _SyncRunner>{
    'direct_top_level_call': _runDirectTopLevel,
    'direct_instance_method_call': _runDirectInstance,
    'function_tear_off': _runTearOff,
    'specialized_adapter': _runSpecializedAdapter,
    'uniform_adapter': _runUniformAdapter,
    'sync_result_normalization': _runSyncResultNormalization,
    'future_or_sync_normalization': _runFutureOrSyncNormalization,
    'try_catch_boundary': _runTryCatchBoundary,
  };
  for (final entry in syncCases.entries) {
    entry.value(options.warmupCalls, 0);
    measurements.add(
      _measureSync(entry.key, entry.value, options.calls, options.iterations),
    );
  }

  final completedCalls = max(10000, options.calls ~/ 100);
  final boundaryCalls = max(1000, options.calls ~/ 1000);
  await _executeAsync(immediateAsyncHandler, completedCalls ~/ 10);
  measurements.add(
    await _measureAsync(
      'already_completed_future',
      immediateAsyncHandler,
      completedCalls,
      options.iterations,
    ),
  );
  await _executeAsync(boundaryAsyncHandler, boundaryCalls ~/ 10);
  measurements.add(
    await _measureAsync(
      'real_async_boundary',
      boundaryAsyncHandler,
      boundaryCalls,
      options.iterations,
    ),
  );

  final result = <String, Object>{
    'schemaVersion': 1,
    'kind': 'oche-handler-execution-microbenchmark',
    'timestampUtc': DateTime.now().toUtc().toIso8601String(),
    'runtime': Platform.version,
    'platform': Platform.operatingSystem,
    'binarySizeBytes': File(Platform.resolvedExecutable).lengthSync(),
    'configuration': {
      'syncCalls': options.calls,
      'warmupCalls': options.warmupCalls,
      'completedFutureCalls': completedCalls,
      'realBoundaryCalls': boundaryCalls,
      'iterations': options.iterations,
    },
    'measurements': measurements,
  };
  final encoded = const JsonEncoder.withIndent('  ').convert(result);
  if (options.outputPath case final outputPath?) {
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsString('$encoded\n');
    stdout.writeln('Wrote handler microbenchmark to ${file.path}');
  } else {
    stdout.writeln(encoded);
  }
}

int _specializedAdapter(int id) => microValueHandler(id);

int _uniformAdapter(int id) {
  final FutureOr<Object> result = microValueHandler(id);
  if (result is Future<Object>) {
    throw StateError('The synchronous benchmark returned a Future.');
  }
  return result as int;
}

int _syncResultNormalization(int id) =>
    phase1aJsonResponse(stringIdHandler(id)).body.length;

int _futureOrSyncNormalization(int id) {
  final FutureOr<int> result = microValueHandler(id);
  return switch (result) {
    final int value => value,
    Future<int>() => throw StateError('Unexpected Future.'),
  };
}

int _tryCatchBoundary(int id) {
  try {
    return microValueHandler(id);
  } on Object {
    return -1;
  }
}

typedef _SyncRunner = int Function(int calls, int offset);

int _runDirectTopLevel(int calls, int offset) {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    checksum =
        (checksum + microValueHandler((index + offset) & 1023)) & 0x7fffffff;
  }
  return checksum;
}

int _runDirectInstance(int calls, int offset) {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    checksum =
        (checksum +
            handlerBenchmarkController.microValue((index + offset) & 1023)) &
        0x7fffffff;
  }
  return checksum;
}

int _runTearOff(int calls, int offset) {
  final tearOff = microValueHandler;
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    checksum = (checksum + tearOff((index + offset) & 1023)) & 0x7fffffff;
  }
  return checksum;
}

int _runSpecializedAdapter(int calls, int offset) {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    checksum =
        (checksum + _specializedAdapter((index + offset) & 1023)) & 0x7fffffff;
  }
  return checksum;
}

int _runUniformAdapter(int calls, int offset) {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    checksum =
        (checksum + _uniformAdapter((index + offset) & 1023)) & 0x7fffffff;
  }
  return checksum;
}

int _runSyncResultNormalization(int calls, int offset) {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    checksum =
        (checksum + _syncResultNormalization((index + offset) & 1023)) &
        0x7fffffff;
  }
  return checksum;
}

int _runFutureOrSyncNormalization(int calls, int offset) {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    checksum =
        (checksum + _futureOrSyncNormalization((index + offset) & 1023)) &
        0x7fffffff;
  }
  return checksum;
}

int _runTryCatchBoundary(int calls, int offset) {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    checksum =
        (checksum + _tryCatchBoundary((index + offset) & 1023)) & 0x7fffffff;
  }
  return checksum;
}

Map<String, Object> _measureSync(
  String name,
  _SyncRunner runner,
  int calls,
  int iterations,
) {
  final trials = <Map<String, Object>>[];
  for (var iteration = 1; iteration <= iterations; iteration++) {
    final watch = Stopwatch()..start();
    final checksum = runner(calls, iteration * 17);
    watch.stop();
    trials.add(
      _trial(iteration, calls, watch.elapsedTicks / watch.frequency, checksum),
    );
  }
  return _measurement(name, trials);
}

Future<Map<String, Object>> _measureAsync(
  String name,
  Future<String> Function(int) operation,
  int calls,
  int iterations,
) async {
  final trials = <Map<String, Object>>[];
  for (var iteration = 1; iteration <= iterations; iteration++) {
    final watch = Stopwatch()..start();
    final checksum = await _executeAsync(
      operation,
      calls,
      offset: iteration * 17,
    );
    watch.stop();
    trials.add(
      _trial(iteration, calls, watch.elapsedTicks / watch.frequency, checksum),
    );
  }
  return _measurement(name, trials);
}

Future<int> _executeAsync(
  Future<String> Function(int) operation,
  int calls, {
  int offset = 0,
}) async {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    final result = await operation((index + offset) & 1023);
    checksum = (checksum + result.length) & 0x7fffffff;
  }
  return checksum;
}

Map<String, Object> _trial(
  int iteration,
  int calls,
  double seconds,
  int checksum,
) => {
  'iteration': iteration,
  'calls': calls,
  'elapsedMicroseconds': seconds * 1000000,
  'callsPerSecond': calls / seconds,
  'nanosecondsPerCall': seconds * 1000000000 / calls,
  'checksum': checksum,
};

Map<String, Object> _measurement(
  String name,
  List<Map<String, Object>> trials,
) => {
  'name': name,
  'trials': trials,
  'aggregate': {
    'callsPerSecond': _summary(
      trials.map((trial) => trial['callsPerSecond']! as double),
    ),
    'nanosecondsPerCall': _summary(
      trials.map((trial) => trial['nanosecondsPerCall']! as double),
    ),
  },
};

Map<String, double> _summary(Iterable<double> input) {
  final values = input.toList()..sort();
  final middle = values.length ~/ 2;
  final median = values.length.isOdd
      ? values[middle]
      : (values[middle - 1] + values[middle]) / 2;
  final mean = values.reduce((left, right) => left + right) / values.length;
  var squaredDifferenceSum = 0.0;
  for (final value in values) {
    final difference = value - mean;
    squaredDifferenceSum += difference * difference;
  }
  return {
    'median': median,
    'minimum': values.first,
    'maximum': values.last,
    'standardDeviation': sqrt(squaredDifferenceSum / values.length),
  };
}

final class _Options {
  const _Options({
    required this.calls,
    required this.warmupCalls,
    required this.iterations,
    required this.outputPath,
  });

  final int calls;
  final int warmupCalls;
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
    const known = {'calls', 'warmup-calls', 'iterations', 'output'};
    final unknown = values.keys.where((key) => !known.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown options: ${unknown.join(', ')}');
    }
    final calls = int.parse(values['calls'] ?? '5000000');
    final warmupCalls = int.parse(values['warmup-calls'] ?? '500000');
    final iterations = int.parse(values['iterations'] ?? '5');
    if (calls < 1 || warmupCalls < 0 || iterations < 1) {
      throw RangeError('calls and iterations must be positive; warmup >= 0.');
    }
    return _Options(
      calls: calls,
      warmupCalls: warmupCalls,
      iterations: iterations,
      outputPath: values['output'],
    );
  }
}
