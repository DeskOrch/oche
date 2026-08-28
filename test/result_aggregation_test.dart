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
}
