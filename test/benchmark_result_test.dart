import 'package:oche_benchmark_harness/benchmark_result.dart';
import 'package:test/test.dart';

void main() {
  test('unavailable measurements are absent instead of fabricated', () {
    final result = BenchmarkResult(
      timestampUtc: DateTime.utc(2026),
      implementation: 'raw_dart_io',
      mode: 'jit',
      host: '127.0.0.1',
      port: 8080,
      endpoint: '/plaintext',
      concurrency: 100,
      durationSeconds: 30,
      warmupSeconds: 5,
      loadGenerator: 'none',
      startupMs: 12.5,
      environment: const {
        'operatingSystem': 'windows',
        'environmentType': 'native-windows',
      },
      unavailableMetrics: const ['requestsPerSecond'],
    ).toJson();

    expect(result['startupMs'], 12.5);
    expect(result, isNot(contains('requestsPerSecond')));
    expect(result, isNot(contains('latency')));
    expect(result, isNot(contains('memory')));
    expect(result['unavailableMetrics'], ['requestsPerSecond']);
    expect(result['environment'], {
      'operatingSystem': 'windows',
      'environmentType': 'native-windows',
    });
  });
}
