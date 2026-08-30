import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final measurements = <Map<String, Object>>[];
  final syncCases = <String, _SyncRunner>{
    'direct_handler': _runDirect,
    'generated_1': _runGenerated1,
    'generated_3': _runGenerated3,
    'generated_5': _runGenerated5,
    'runtime_1': _runRuntime1,
    'runtime_3': _runRuntime3,
    'runtime_5': _runRuntime5,
    'shared_1': _runShared1,
    'shared_3': _runShared3,
    'shared_5': _runShared5,
    'generated_short_circuit_3': _runGeneratedShort3,
    'runtime_short_circuit_3': _runRuntimeShort3,
    'generated_before_after_3': _runGenerated3,
  };
  for (final entry in syncCases.entries) {
    entry.value(options.warmupCalls, 0);
    measurements.add(
      _measureSync(entry.key, entry.value, options.calls, options.iterations),
    );
  }

  final asyncCalls = max(10000, options.calls ~/ 100);
  final boundaryCalls = max(1000, options.calls ~/ 1000);
  await _runAsyncSyncMiddleware(asyncCalls ~/ 10, 0);
  measurements.add(
    await _measureAsync(
      'sync_middleware_async_handler',
      _runAsyncSyncMiddleware,
      asyncCalls,
      options.iterations,
    ),
  );
  await _runAsyncMiddleware(asyncCalls ~/ 10, 0);
  measurements.add(
    await _measureAsync(
      'async_middleware',
      _runAsyncMiddleware,
      asyncCalls,
      options.iterations,
    ),
  );
  await _runMixedBoundary(boundaryCalls ~/ 10, 0);
  measurements.add(
    await _measureAsync(
      'mixed_real_boundary',
      _runMixedBoundary,
      boundaryCalls,
      options.iterations,
    ),
  );

  final result = <String, Object>{
    'schemaVersion': 1,
    'kind': 'oche-middleware-execution-microbenchmark',
    'timestampUtc': DateTime.now().toUtc().toIso8601String(),
    'runtime': Platform.version,
    'platform': Platform.operatingSystem,
    'binarySizeBytes': File(Platform.resolvedExecutable).lengthSync(),
    'configuration': {
      'syncCalls': options.calls,
      'warmupCalls': options.warmupCalls,
      'asyncCalls': asyncCalls,
      'realBoundaryCalls': boundaryCalls,
      'iterations': options.iterations,
    },
    'measurements': measurements,
  };
  final encoded = const JsonEncoder.withIndent('  ').convert(result);
  if (options.outputPath case final path?) {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('$encoded\n');
    stdout.writeln('Wrote middleware microbenchmark to $path');
  } else {
    stdout.writeln(encoded);
  }
}

typedef _SyncRunner = int Function(int calls, int offset);
typedef _AsyncRunner = Future<int> Function(int calls, int offset);

int _handler(int value) => value + 1;

int _before(int value, int index) => ((value * 31) + index + 17) & 0x7fffffff;

int _after(int value, int index) => ((value * 17) + index + 31) & 0x7fffffff;

int _runDirect(int calls, int offset) {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    checksum = (checksum + _handler((index + offset) & 1023)) & 0x7fffffff;
  }
  return checksum;
}

int _runGenerated1(int calls, int offset) {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    var value = _before((index + offset) & 1023, 0);
    value = _handler(value);
    value = _after(value, 0);
    checksum = (checksum + value) & 0x7fffffff;
  }
  return checksum;
}

int _runGenerated3(int calls, int offset) {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    var value = _before((index + offset) & 1023, 0);
    value = _before(value, 1);
    value = _before(value, 2);
    value = _handler(value);
    value = _after(value, 2);
    value = _after(value, 1);
    value = _after(value, 0);
    checksum = (checksum + value) & 0x7fffffff;
  }
  return checksum;
}

int _runGenerated5(int calls, int offset) {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    var value = _before((index + offset) & 1023, 0);
    value = _before(value, 1);
    value = _before(value, 2);
    value = _before(value, 3);
    value = _before(value, 4);
    value = _handler(value);
    value = _after(value, 4);
    value = _after(value, 3);
    value = _after(value, 2);
    value = _after(value, 1);
    value = _after(value, 0);
    checksum = (checksum + value) & 0x7fffffff;
  }
  return checksum;
}

const _steps1 = <int>[0];
const _steps3 = <int>[0, 1, 2];
const _steps5 = <int>[0, 1, 2, 3, 4];

int _runtime(int value, List<int> steps, {bool shortCircuit = false}) {
  var entered = 0;
  for (final step in steps) {
    value = _before(value, step);
    if (shortCircuit && step == 0) return value;
    entered++;
  }
  value = _handler(value);
  for (var index = entered - 1; index >= 0; index--) {
    value = _after(value, steps[index]);
  }
  return value;
}

int _runRuntime1(int calls, int offset) => _runRuntime(calls, offset, _steps1);

int _runRuntime3(int calls, int offset) => _runRuntime(calls, offset, _steps3);

int _runRuntime5(int calls, int offset) => _runRuntime(calls, offset, _steps5);

int _sharedEnter1(int value) => _before(value, 0);

int _sharedExit1(int value) => _after(value, 0);

int _sharedEnter3(int value) {
  value = _before(value, 0);
  value = _before(value, 1);
  return _before(value, 2);
}

int _sharedExit3(int value) {
  value = _after(value, 2);
  value = _after(value, 1);
  return _after(value, 0);
}

int _sharedEnter5(int value) {
  value = _sharedEnter3(value);
  value = _before(value, 3);
  return _before(value, 4);
}

int _sharedExit5(int value) {
  value = _after(value, 4);
  value = _after(value, 3);
  return _sharedExit3(value);
}

int _runShared1(int calls, int offset) {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    var value = _sharedEnter1((index + offset) & 1023);
    value = _handler(value);
    value = _sharedExit1(value);
    checksum = (checksum + value) & 0x7fffffff;
  }
  return checksum;
}

int _runShared3(int calls, int offset) {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    var value = _sharedEnter3((index + offset) & 1023);
    value = _handler(value);
    value = _sharedExit3(value);
    checksum = (checksum + value) & 0x7fffffff;
  }
  return checksum;
}

int _runShared5(int calls, int offset) {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    var value = _sharedEnter5((index + offset) & 1023);
    value = _handler(value);
    value = _sharedExit5(value);
    checksum = (checksum + value) & 0x7fffffff;
  }
  return checksum;
}

int _runRuntime(int calls, int offset, List<int> steps) {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    checksum =
        (checksum + _runtime((index + offset) & 1023, steps)) & 0x7fffffff;
  }
  return checksum;
}

int _runGeneratedShort3(int calls, int offset) {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    final value = _before((index + offset) & 1023, 0);
    checksum = (checksum + value) & 0x7fffffff;
  }
  return checksum;
}

int _runRuntimeShort3(int calls, int offset) {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    checksum =
        (checksum +
            _runtime((index + offset) & 1023, _steps3, shortCircuit: true)) &
        0x7fffffff;
  }
  return checksum;
}

Future<int> _runAsyncSyncMiddleware(int calls, int offset) async {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    var value = _before((index + offset) & 1023, 0);
    value = _before(value, 1);
    value = _before(value, 2);
    value = await Future<int>.value(_handler(value));
    value = _after(value, 2);
    value = _after(value, 1);
    value = _after(value, 0);
    checksum = (checksum + value) & 0x7fffffff;
  }
  return checksum;
}

Future<int> _runAsyncMiddleware(int calls, int offset) async {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    var value = await Future<int>.value(_before((index + offset) & 1023, 0));
    value = await Future<int>.value(_before(value, 1));
    value = await Future<int>.value(_before(value, 2));
    value = _handler(value);
    value = await Future<int>.value(_after(value, 2));
    value = await Future<int>.value(_after(value, 1));
    value = await Future<int>.value(_after(value, 0));
    checksum = (checksum + value) & 0x7fffffff;
  }
  return checksum;
}

Future<int> _runMixedBoundary(int calls, int offset) async {
  var checksum = 0;
  for (var index = 0; index < calls; index++) {
    var value = _before((index + offset) & 1023, 0);
    await Future<void>.delayed(Duration.zero);
    value = _before(value, 1);
    value = _before(value, 2);
    value = _handler(value);
    value = _after(value, 2);
    value = _after(value, 1);
    value = _after(value, 0);
    checksum = (checksum + value) & 0x7fffffff;
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
  _AsyncRunner runner,
  int calls,
  int iterations,
) async {
  final trials = <Map<String, Object>>[];
  for (var iteration = 1; iteration <= iterations; iteration++) {
    final watch = Stopwatch()..start();
    final checksum = await runner(calls, iteration * 17);
    watch.stop();
    trials.add(
      _trial(iteration, calls, watch.elapsedTicks / watch.frequency, checksum),
    );
  }
  return _measurement(name, trials);
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
    'mean': mean,
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
      final equals = argument.indexOf('=');
      if (!argument.startsWith('--') || equals < 0) {
        throw FormatException('Expected --name=value, got: $argument');
      }
      values[argument.substring(2, equals)] = argument.substring(equals + 1);
    }
    const known = {'calls', 'warmup-calls', 'iterations', 'output'};
    final unknown = values.keys.where((key) => !known.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown options: $unknown');
    }
    final calls = int.parse(values['calls'] ?? '5000000');
    final warmupCalls = int.parse(values['warmup-calls'] ?? '500000');
    final iterations = int.parse(values['iterations'] ?? '5');
    if (calls < 1 || warmupCalls < 0 || iterations < 1) {
      throw RangeError('calls/iterations must be positive; warmup >= 0.');
    }
    return _Options(
      calls: calls,
      warmupCalls: warmupCalls,
      iterations: iterations,
      outputPath: values['output'],
    );
  }
}
