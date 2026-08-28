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

  test('serializes routing-kernel experiment dimensions when present', () {
    final result = BenchmarkResult(
      timestampUtc: DateTime.utc(2026),
      implementation: 'oche_tree',
      mode: 'aot',
      host: '127.0.0.1',
      port: 8080,
      endpoint: '/users',
      concurrency: 100,
      durationSeconds: 30,
      warmupSeconds: 5,
      loadGenerator: 'oha',
      startupMs: 10,
      environment: const {},
      requestMethod: 'DELETE',
      expectedStatus: 405,
      routeCount: 1000,
      workload: 'method_mismatch',
      generatedSourceBytes: 400000,
      generatedSourceLines: 10000,
      generatedSourceSha256: 'source-hash',
      compileDurationMs: 5000,
      executableSha256: 'executable-hash',
    ).toJson();

    expect(result, containsPair('requestMethod', 'DELETE'));
    expect(result, containsPair('expectedStatus', 405));
    expect(result, containsPair('routeCount', 1000));
    expect(result, containsPair('workload', 'method_mismatch'));
    expect(result, containsPair('generatedSourceBytes', 400000));
    expect(result, containsPair('generatedSourceSha256', 'source-hash'));
    expect(result, containsPair('compileDurationMs', 5000));
    expect(result, containsPair('executableSha256', 'executable-hash'));
  });
}
