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
}
