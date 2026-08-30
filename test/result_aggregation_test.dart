import 'dart:convert';
import 'dart:io';

import 'package:oche_benchmark_harness/result_aggregation.dart';
import 'package:test/test.dart';

void main() {
  test('retains raw trials and aggregates only available metrics', () async {
    final directory = await Directory.systemTemp.createTemp('oche-aggregate-');
    addTearDown(() => directory.delete(recursive: true));
    final paths = <String>[];
    for (final startup in [10.0, 20.0]) {
      final file = File('${directory.path}/trial-$startup.json');
      await file.writeAsString(
        jsonEncode({
          'implementation': 'oche_static',
          'mode': 'aot',
          'host': '127.0.0.1',
          'endpoint': '/plaintext',
          'concurrency': 100,
          'durationSeconds': 30,
          'warmupSeconds': 5,
          'loadGenerator': 'none',
          'startupMs': startup,
          'unavailableMetrics': ['requestsPerSecond'],
        }),
      );
      paths.add(file.path);
    }

    final aggregate = await aggregateResultFiles(paths);
    final groups = aggregate['groups'] as List<Map<String, Object>>;
    final group = groups.single;
    final metrics = group['metrics'] as Map<String, Object>;
    final startup = metrics['startupMs'] as Map<String, Object>;

    expect(aggregate['rawTrialCount'], 2);
    expect(group['rawTrialFiles'], paths);
    expect(group['trialCount'], 2);
    expect(startup['median'], 15);
    expect(startup['minimum'], 10);
    expect(startup['maximum'], 20);
    expect(metrics, isNot(contains('requestsPerSecond')));
  });

  test('normalizes selected metric medians relative to raw dart:io', () async {
    final directory = await Directory.systemTemp.createTemp('oche-relative-');
    addTearDown(() => directory.delete(recursive: true));
    final paths = <String>[];
    for (final implementation in ['raw_dart_io', 'oche_static']) {
      final isRaw = implementation == 'raw_dart_io';
      final file = File('${directory.path}/$implementation.json');
      await file.writeAsString(
        jsonEncode({
          'implementation': implementation,
          'mode': 'aot',
          'host': '127.0.0.1',
          'endpoint': '/plaintext',
          'concurrency': 100,
          'durationSeconds': 30,
          'warmupSeconds': 5,
          'loadGenerator': 'oha',
          'startupMs': 10,
          'requestsPerSecond': isRaw ? 1000 : 950,
          'latency': {'p99Ms': isRaw ? 10 : 12},
          'memory': {
            'idleRssMb': isRaw ? 20 : 18,
            'peakLoadRssMb': isRaw ? 30 : 33,
          },
          'binarySizeMb': isRaw ? 6 : 7,
          'environment': {
            'operatingSystem': 'linux',
            'environmentType': 'native-linux',
          },
        }),
      );
      paths.add(file.path);
    }

    final aggregate = await aggregateResultFiles(paths);
    final groups = aggregate['groups'] as List<Map<String, Object>>;
    final staticGroup = groups.singleWhere(
      (group) => group['implementation'] == 'oche_static',
    );
    final relative = staticGroup['relativeToRaw'] as Map<String, Object>;
    final throughput = relative['requestsPerSecond'] as Map<String, Object>;
    final latency = relative['p99Ms'] as Map<String, Object>;

    expect(throughput['percentOfRaw'], 95);
    expect(throughput['preferredDirection'], 'higherIsBetter');
    expect(latency['percentOfRaw'], 120);
    expect(latency['preferredDirection'], 'lowerIsBetter');
  });

  test(
    'keeps route counts separate and normalizes against ten routes',
    () async {
      final directory = await Directory.systemTemp.createTemp('oche-routes-');
      addTearDown(() => directory.delete(recursive: true));
      final paths = <String>[];
      for (final routeCount in [10, 100, 1000]) {
        final file = File('${directory.path}/tree-$routeCount.json');
        await file.writeAsString(
          jsonEncode({
            'implementation': 'oche_tree',
            'mode': 'aot',
            'host': '127.0.0.1',
            'endpoint': '/users/42',
            'requestMethod': 'GET',
            'expectedStatus': 200,
            'routeCount': routeCount,
            'workload': 'single_parameter',
            'concurrency': 100,
            'durationSeconds': 30,
            'warmupSeconds': 5,
            'loadGenerator': 'oha',
            'startupMs': 10,
            'requestsPerSecond': routeCount == 10 ? 1000 : 970,
            'generatedSourceBytes': routeCount * 100,
          }),
        );
        paths.add(file.path);
      }

      final aggregate = await aggregateResultFiles(paths);
      final groups = aggregate['groups'] as List<Map<String, Object>>;
      expect(groups, hasLength(3));
      final thousand = groups.singleWhere(
        (group) => group['routeCount'] == 1000,
      );
      final relative = thousand['relativeToTenRoutes'] as Map<String, Object>;
      final throughput = relative['requestsPerSecond'] as Map<String, Object>;
      final source = relative['generatedSourceBytes'] as Map<String, Object>;
      expect(throughput['percentOfRaw'], 97);
      expect(source['percentOfRaw'], 10000);
    },
  );

  test(
    'normalizes Phase 1B candidates against the Phase 1A direct handler',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'oche-handler-relative-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final paths = <String>[];
      for (final implementation in [
        'handler_phase1a_direct',
        'handler_specialized',
        'handler_uniform',
      ]) {
        final file = File('${directory.path}/$implementation.json');
        await file.writeAsString(
          jsonEncode({
            'implementation': implementation,
            'mode': 'aot',
            'host': '127.0.0.1',
            'endpoint': '/users/42',
            'requestMethod': 'GET',
            'expectedStatus': 200,
            'routeCount': 100,
            'workload': 'single_int_sync',
            'concurrency': 100,
            'durationSeconds': 30,
            'warmupSeconds': 5,
            'loadGenerator': 'oha',
            'startupMs': 10,
            'requestsPerSecond': switch (implementation) {
              'handler_phase1a_direct' => 1000,
              'handler_specialized' => 990,
              _ => 970,
            },
            'latency': {'p99Ms': 10},
          }),
        );
        paths.add(file.path);
      }

      final aggregate = await aggregateResultFiles(paths);
      final groups = aggregate['groups'] as List<Map<String, Object>>;
      final specialized = groups.singleWhere(
        (group) => group['implementation'] == 'handler_specialized',
      );
      final relative =
          specialized['relativeToPhase1ADirect'] as Map<String, Object>;
      final throughput = relative['requestsPerSecond'] as Map<String, Object>;
      expect(throughput['percentOfRaw'], 99);
    },
  );

  test(
    'keeps middleware depth separate and normalizes against Phase 1B',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'oche-middleware-relative-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final paths = <String>[];
      for (final depth in [1, 3]) {
        for (final implementation in [
          'middleware_phase1b',
          'middleware_generated',
        ]) {
          final file = File('${directory.path}/$implementation-d$depth.json');
          await file.writeAsString(
            jsonEncode({
              'implementation': implementation,
              'mode': 'aot',
              'host': '127.0.0.1',
              'endpoint': '/users/42',
              'requestMethod': 'GET',
              'expectedStatus': 200,
              'routeCount': 100,
              'workload': 'single_int_sync',
              'middlewareDepth': depth,
              'middlewareProfile': 'sync_continue',
              'concurrency': 100,
              'durationSeconds': 30,
              'warmupSeconds': 5,
              'loadGenerator': 'oha',
              'startupMs': 10,
              'requestsPerSecond': implementation == 'middleware_phase1b'
                  ? 1000
                  : depth == 1
                  ? 985
                  : 970,
            }),
          );
          paths.add(file.path);
        }
      }

      final aggregate = await aggregateResultFiles(paths);
      final groups = aggregate['groups'] as List<Map<String, Object>>;
      expect(groups, hasLength(4));
      final depthOne = groups.singleWhere(
        (group) =>
            group['implementation'] == 'middleware_generated' &&
            group['middlewareDepth'] == 1,
      );
      final depthThree = groups.singleWhere(
        (group) =>
            group['implementation'] == 'middleware_generated' &&
            group['middlewareDepth'] == 3,
      );
      final depthOneRelative =
          depthOne['relativeToPhase1BSpecialized'] as Map<String, Object>;
      final depthThreeRelative =
          depthThree['relativeToPhase1BSpecialized'] as Map<String, Object>;
      expect(
        (depthOneRelative['requestsPerSecond']!
            as Map<String, Object>)['percentOfRaw'],
        98.5,
      );
      expect(
        (depthThreeRelative['requestsPerSecond']!
            as Map<String, Object>)['percentOfRaw'],
        97,
      );
    },
  );
}
