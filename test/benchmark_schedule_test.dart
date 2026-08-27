import 'package:oche_benchmark_harness/benchmark_schedule.dart';
import 'package:test/test.dart';

void main() {
  test('five-iteration schedule matches the documented balanced rotation', () {
    const implementations = ['raw_dart_io', 'relic', 'oche_static'];

    expect(
      [
        for (var iteration = 1; iteration <= 5; iteration++)
          balancedThreeWayOrder(implementations, iteration),
      ],
      [
        ['raw_dart_io', 'relic', 'oche_static'],
        ['relic', 'oche_static', 'raw_dart_io'],
        ['oche_static', 'raw_dart_io', 'relic'],
        ['raw_dart_io', 'oche_static', 'relic'],
        ['relic', 'raw_dart_io', 'oche_static'],
      ],
    );
  });

  test('six-iteration cycle gives every item every position twice', () {
    const items = ['a', 'b', 'c'];
    final counts = {for (final item in items) item: List<int>.filled(3, 0)};

    for (var iteration = 1; iteration <= 6; iteration++) {
      final order = balancedThreeWayOrder(items, iteration);
      for (var position = 0; position < order.length; position++) {
        counts[order[position]]![position]++;
      }
    }

    expect(counts, {
      'a': [2, 2, 2],
      'b': [2, 2, 2],
      'c': [2, 2, 2],
    });
  });

  test('schedule metadata requires a complete suite context', () {
    expect(benchmarkScheduleMetadata(), isNull);
    expect(
      () => benchmarkScheduleMetadata(suiteRunId: 'partial'),
      throwsFormatException,
    );

    expect(
      benchmarkScheduleMetadata(
        suiteRunId: 'run-1',
        iteration: 2,
        trialSequence: 10,
        implementationOrder: const ['raw', 'relic', 'static'],
        implementationPosition: 2,
        endpointOrder: const ['/json', '/users/42', '/plaintext'],
        endpointPosition: 1,
        cooldownSeconds: 2,
      ),
      {
        'suiteRunId': 'run-1',
        'iteration': 2,
        'trialSequence': 10,
        'implementationOrder': ['raw', 'relic', 'static'],
        'implementationPosition': 2,
        'endpointOrder': ['/json', '/users/42', '/plaintext'],
        'endpointPosition': 1,
        'cooldownSeconds': 2,
      },
    );
  });

  test('schedule metadata rejects invalid orders and positions', () {
    Map<String, Object>? build({
      List<String> implementations = const ['raw', 'relic', 'static'],
      int implementationPosition = 2,
      int cooldown = 2,
    }) => benchmarkScheduleMetadata(
      suiteRunId: 'run-1',
      iteration: 1,
      trialSequence: 1,
      implementationOrder: implementations,
      implementationPosition: implementationPosition,
      endpointOrder: const ['/plaintext', '/json', '/users/42'],
      endpointPosition: 1,
      cooldownSeconds: cooldown,
    );

    expect(
      () => build(implementations: const ['raw', 'raw', 'static']),
      throwsFormatException,
    );
    expect(() => build(implementationPosition: 4), throwsRangeError);
    expect(() => build(cooldown: -1), throwsRangeError);
  });
}
