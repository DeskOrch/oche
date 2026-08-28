import 'dart:convert';
import 'dart:io';

typedef _Invocation = int Function(int value);

const _runtimeStages = <_Invocation>[
  _trivialMiddleware,
  _trivialMiddleware,
  _trivialMiddleware,
  _trivialMiddleware,
  _trivialMiddleware,
];

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final results = <Map<String, Object>>[];
  for (final strategy in ['generated_direct_chain', 'runtime_list_traversal']) {
    for (final count in const [0, 1, 5]) {
      final invocation = strategy == 'generated_direct_chain'
          ? _directInvocation(count)
          : (int value) => _runtimeInvocation(value, count);
      _measure(invocation, options.warmupCalls);
      for (var iteration = 1; iteration <= options.iterations; iteration++) {
        final measurement = _measure(invocation, options.calls);
        results.add({
          'strategy': strategy,
          'middlewareCount': count,
          'iteration': iteration,
          'calls': options.calls,
          ...measurement,
        });
      }
    }
  }
  final document = <String, Object>{
    'schemaVersion': 1,
    'kind': 'oche-middleware-invocation-scaling',
    'timestampUtc': DateTime.now().toUtc().toIso8601String(),
    'runtime': Platform.version,
    'configuration': {
      'calls': options.calls,
      'warmupCalls': options.warmupCalls,
      'iterations': options.iterations,
    },
    'trials': results,
  };
  final encoded = const JsonEncoder.withIndent('  ').convert(document);
  if (options.outputPath case final path?) {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('$encoded\n');
    stdout.writeln('Wrote middleware experiment to ${file.path}');
  } else {
    stdout.writeln(encoded);
  }
}

Map<String, Object> _measure(_Invocation invocation, int calls) {
  var checksum = 0;
  final watch = Stopwatch()..start();
  for (var index = 0; index < calls; index++) {
    checksum = (checksum + invocation(index)) & 0x7fffffff;
  }
  watch.stop();
  final seconds = watch.elapsedTicks / watch.frequency;
  return {
    'elapsedMicroseconds': watch.elapsedMicroseconds,
    'callsPerSecond': calls / seconds,
    'nanosecondsPerCall': seconds * 1000000000 / calls,
    'checksum': checksum,
  };
}

_Invocation _directInvocation(int count) => switch (count) {
  0 => _direct0,
  1 => _direct1,
  5 => _direct5,
  _ => throw ArgumentError.value(count, 'count'),
};

int _direct0(int value) => _handler(value);
int _direct1(int value) => _handler(_trivialMiddleware(value));
int _direct5(int value) => _handler(
  _trivialMiddleware(
    _trivialMiddleware(
      _trivialMiddleware(_trivialMiddleware(_trivialMiddleware(value))),
    ),
  ),
);

int _runtimeInvocation(int value, int count) {
  var current = value;
  for (var index = 0; index < count; index++) {
    current = _runtimeStages[index](current);
  }
  return _handler(current);
}

int _trivialMiddleware(int value) => value ^ 1;
int _handler(int value) => value * 3 + 7;

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
      if (!argument.startsWith('--')) {
        throw FormatException('Expected an option, got: $argument');
      }
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
    final warmup = int.parse(values['warmup-calls'] ?? '500000');
    final iterations = int.parse(values['iterations'] ?? '5');
    if (calls < 1 || warmup < 0 || iterations < 1) {
      throw RangeError('Invalid middleware benchmark configuration.');
    }
    return _Options(
      calls: calls,
      warmupCalls: warmup,
      iterations: iterations,
      outputPath: values['output'],
    );
  }
}
