import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../benchmarks/harness/bin/routing_kernel_suite.dart' as suite;

void main() {
  test('resume identity rejects trials from a different build', () async {
    final directory = await Directory.systemTemp.createTemp(
      'oche-kernel-resume-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final trial = File('${directory.path}/trial.json');
    await trial.writeAsString(
      jsonEncode({
        'timestampUtc': '2026-08-28T00:00:00Z',
        'environment': {'operatingSystem': 'windows'},
        'implementation': 'oche_tree',
        'mode': 'aot',
        'endpoint': '/users/42',
        'requestMethod': 'GET',
        'expectedStatus': 200,
        'routeCount': 100,
        'workload': 'single_parameter',
        'concurrency': 10,
        'durationSeconds': 30,
        'warmupSeconds': 5,
        'loadGenerator': 'oha',
        'generatedSourceBytes': 41502,
        'generatedSourceLines': 1028,
        'generatedSourceSha256':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'compileDurationMs': 3054.459,
        'binarySizeMb': 6.3232421875,
        'executableSha256':
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'schedule': {
          'suiteRunId': 'run-success',
          'iteration': 1,
          'trialSequence': 1,
          'implementationOrder': ['raw_dart_io', 'oche_tree', 'oche_indexed'],
          'implementationPosition': 2,
          'endpointOrder': [
            'GET /api/v1/status',
            'GET /users/42',
            'GET /users/42/orders/91',
          ],
          'endpointPosition': 2,
          'cooldownSeconds': 2,
        },
      }),
    );

    bool matches({
      int sourceBytes = 41502,
      int sourceLines = 1028,
      double compileMs = 3054.459,
      double binaryMb = 6.3232421875,
      String sourceSha256 =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      String executableSha256 =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    }) => suite.completedTrialMatches(
      trial.path,
      implementation: 'oche_tree',
      mode: 'aot',
      endpoint: '/users/42',
      requestMethod: 'GET',
      expectedStatus: 200,
      routeCount: 100,
      workload: 'single_parameter',
      concurrency: 10,
      durationSeconds: 30,
      warmupSeconds: 5,
      loadGenerator: 'oha',
      suiteRunId: 'run-success',
      iteration: 1,
      trialSequence: 1,
      implementationOrder: const ['raw_dart_io', 'oche_tree', 'oche_indexed'],
      implementationPosition: 2,
      endpointOrder: const [
        'GET /api/v1/status',
        'GET /users/42',
        'GET /users/42/orders/91',
      ],
      endpointPosition: 2,
      cooldownSeconds: 2,
      generatedSourceBytes: sourceBytes,
      generatedSourceLines: sourceLines,
      compileDurationMs: compileMs,
      generatedSourceSha256: sourceSha256,
      binarySizeMb: binaryMb,
      executableSha256: executableSha256,
    );

    expect(matches(), isTrue);
    expect(matches(sourceBytes: 41503), isFalse);
    expect(matches(sourceLines: 1029), isFalse);
    expect(matches(compileMs: 3054.460), isFalse);
    expect(matches(binaryMb: 6.4), isFalse);
    expect(
      matches(
        sourceSha256:
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      ),
      isFalse,
    );
    expect(
      matches(
        executableSha256:
            'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      ),
      isFalse,
    );
  });
}
