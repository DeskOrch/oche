import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:oche_benchmark_harness/benchmark_schedule.dart';
import 'package:oche_benchmark_harness/result_aggregation.dart';

const _implementations = [
  'handler_raw',
  'handler_phase1a_direct',
  'handler_specialized',
  'handler_uniform',
];

const _workloadSets = <String, List<_Workload>>{
  'sync': [
    _Workload('literal_sync', 'GET', '/status', 200),
    _Workload('single_int_sync', 'GET', '/users/42', 200),
    _Workload('two_int_sync', 'GET', '/orders/42/items/91', 200),
  ],
  'async': [
    _Workload('async_immediate', 'GET', '/async/immediate/42', 200),
    _Workload('async_boundary', 'GET', '/async/boundary/42', 200),
    _Workload('instance_structured', 'GET', '/instance/42', 200),
  ],
  'request': [
    _Workload('raw_request', 'GET', '/request/raw', 200),
    _Workload('request_view', 'GET', '/request/view', 200),
    _Workload('structured_result', 'POST', '/users/42', 200),
  ],
};

Future<void> main(List<String> arguments) async {
  final options = _SuiteOptions.parse(arguments);
  final builds = _readBuildEntries(options);
  final timestamp =
      options.suiteRunId ??
      DateTime.now().toUtc().toIso8601String().replaceAll(RegExp('[:.]'), '-');

  for (final setName in options.workloadSets) {
    final workloads = _workloadSets[setName]!;
    final trialFiles = <String>[];
    var trialSequence = 0;
    var reusedTrials = 0;
    final totalTrials =
        options.routeCounts.length *
        options.concurrencies.length *
        options.iterations *
        workloads.length *
        _implementations.length;
    final suiteRunId = '$timestamp-$setName';
    final resultsDirectory = Directory(
      '${options.resultsDirectory}/phase1b-$suiteRunId',
    );
    await resultsDirectory.create(recursive: true);

    for (final routeCount in options.routeCounts) {
      for (final concurrency in options.concurrencies) {
        for (var iteration = 1; iteration <= options.iterations; iteration++) {
          final implementationOrder = balancedOrder(
            _implementations,
            iteration,
          );
          final workloadOrder = balancedThreeWayOrder(workloads, iteration);
          final endpointOrder = workloadOrder
              .map((workload) => '${workload.method} ${workload.endpoint}')
              .toList(growable: false);
          for (
            var workloadIndex = 0;
            workloadIndex < workloadOrder.length;
            workloadIndex++
          ) {
            final workload = workloadOrder[workloadIndex];
            for (
              var implementationIndex = 0;
              implementationIndex < implementationOrder.length;
              implementationIndex++
            ) {
              final implementation = implementationOrder[implementationIndex];
              final build = builds.lookup(implementation, routeCount);
              trialSequence++;
              final output =
                  '${resultsDirectory.path}/$implementation-r$routeCount-'
                  '${workload.name}-c$concurrency-i$iteration.json';
              final benchmarkArguments = [
                'run',
                'benchmarks/harness/bin/benchmark.dart',
                '--implementation=$implementation',
                '--mode=${options.mode}',
                '--host=${options.host}',
                '--port=${options.port}',
                '--endpoint=${workload.endpoint}',
                '--readiness-endpoint=/health',
                '--method=${workload.method}',
                '--expected-status=${workload.expectedStatus}',
                '--route-count=$routeCount',
                '--workload=${workload.name}',
                '--concurrency=$concurrency',
                '--duration=${options.durationSeconds}',
                '--warmup=${options.warmupSeconds}',
                '--load-generator=${options.loadGenerator}',
                '--oha=${options.ohaPath}',
                '--output=$output',
                '--suite-run-id=$suiteRunId',
                '--iteration=$iteration',
                '--trial-sequence=$trialSequence',
                '--implementation-order=${implementationOrder.join(',')}',
                '--implementation-position=${implementationIndex + 1}',
                '--endpoint-order=${endpointOrder.join(',')}',
                '--endpoint-position=${workloadIndex + 1}',
                '--cooldown=${options.cooldownSeconds}',
                '--executable=${build.launchPath(options.mode)}',
                '--generated-source=${build.sourcePath}',
                if (build.compileDurationMs != null)
                  '--compile-duration-ms=${build.compileDurationMs}',
                if (options.environmentType != null)
                  '--environment-type=${options.environmentType}',
              ];

              if (_completedTrialMatches(
                output,
                implementation: implementation,
                mode: options.mode,
                endpoint: workload.endpoint,
                requestMethod: workload.method,
                expectedStatus: workload.expectedStatus,
                routeCount: routeCount,
                workload: workload.name,
                concurrency: concurrency,
                durationSeconds: options.durationSeconds,
                warmupSeconds: options.warmupSeconds,
                loadGenerator: options.loadGenerator,
                suiteRunId: suiteRunId,
                iteration: iteration,
                trialSequence: trialSequence,
                implementationOrder: implementationOrder,
                implementationPosition: implementationIndex + 1,
                endpointOrder: endpointOrder,
                endpointPosition: workloadIndex + 1,
                cooldownSeconds: options.cooldownSeconds,
                build: build,
                aot: options.mode == 'aot',
              )) {
                reusedTrials++;
                trialFiles.add(output);
                stdout.writeln(
                  '[$trialSequence/$totalTrials] reuse $implementation '
                  '${workload.method} ${workload.endpoint}',
                );
                continue;
              }

              stdout.writeln(
                '[$trialSequence/$totalTrials, $setName, r=$routeCount, '
                'c=$concurrency, iteration=$iteration/${options.iterations}] '
                '$implementation ${workload.method} ${workload.endpoint}',
              );
              final process = await Process.start(
                Platform.resolvedExecutable,
                benchmarkArguments,
                mode: ProcessStartMode.inheritStdio,
              );
              final code = await process.exitCode;
              if (code != 0) {
                stderr.writeln(
                  'Handler suite stopped after benchmark exit code $code.',
                );
                exitCode = code;
                return;
              }
              trialFiles.add(output);
              if (options.cooldownSeconds > 0 && trialSequence < totalTrials) {
                await Future<void>.delayed(
                  Duration(seconds: options.cooldownSeconds),
                );
              }
            }
          }
        }
      }
    }

    final aggregate = await aggregateResultFiles(trialFiles);
    final aggregateFile = File(
      '${resultsDirectory.path}/phase1b-$suiteRunId-aggregate.json',
    );
    await aggregateFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(aggregate)}\n',
    );
    stdout.writeln(
      'Wrote $setName aggregate for ${trialFiles.length} raw trials to '
      '${aggregateFile.path} ($reusedTrials reused)',
    );
  }
}

bool _completedTrialMatches(
  String path, {
  required String implementation,
  required String mode,
  required String endpoint,
  required String requestMethod,
  required int expectedStatus,
  required int routeCount,
  required String workload,
  required int concurrency,
  required int durationSeconds,
  required int warmupSeconds,
  required String loadGenerator,
  required String suiteRunId,
  required int iteration,
  required int trialSequence,
  required List<String> implementationOrder,
  required int implementationPosition,
  required List<String> endpointOrder,
  required int endpointPosition,
  required int cooldownSeconds,
  required _BuildEntry build,
  required bool aot,
}) {
  // AOT executable fingerprints cover the generated and imported support
  // sources. JIT trials do not yet record the support-source fingerprint, so
  // rerun them rather than risk reusing a stale result.
  if (!aot) return false;
  final file = File(path);
  if (!file.existsSync()) return false;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) return false;
    final schedule = decoded['schedule'];
    if (schedule is! Map<String, Object?>) return false;
    return decoded['timestampUtc'] is String &&
        decoded['environment'] is Map<String, Object?> &&
        decoded['implementation'] == implementation &&
        decoded['mode'] == mode &&
        decoded['endpoint'] == endpoint &&
        decoded['requestMethod'] == requestMethod &&
        decoded['expectedStatus'] == expectedStatus &&
        decoded['routeCount'] == routeCount &&
        decoded['workload'] == workload &&
        decoded['concurrency'] == concurrency &&
        decoded['durationSeconds'] == durationSeconds &&
        decoded['warmupSeconds'] == warmupSeconds &&
        decoded['loadGenerator'] == loadGenerator &&
        schedule['suiteRunId'] == suiteRunId &&
        schedule['iteration'] == iteration &&
        schedule['trialSequence'] == trialSequence &&
        _sameStrings(schedule['implementationOrder'], implementationOrder) &&
        schedule['implementationPosition'] == implementationPosition &&
        _sameStrings(schedule['endpointOrder'], endpointOrder) &&
        schedule['endpointPosition'] == endpointPosition &&
        schedule['cooldownSeconds'] == cooldownSeconds &&
        decoded['generatedSourceBytes'] == build.generatedSourceBytes &&
        decoded['generatedSourceLines'] == build.generatedSourceLines &&
        decoded['generatedSourceSha256'] == build.sourceSha256 &&
        decoded['compileDurationMs'] == build.compileDurationMs &&
        decoded['binarySizeMb'] == (aot ? build.aotBinarySizeMb : null) &&
        decoded['executableSha256'] == (aot ? build.executableSha256 : null);
  } on FormatException {
    return false;
  } on FileSystemException {
    return false;
  }
}

bool _sameStrings(Object? actual, List<String> expected) {
  if (actual is! List<Object?> || actual.length != expected.length) {
    return false;
  }
  for (var index = 0; index < expected.length; index++) {
    if (actual[index] != expected[index]) return false;
  }
  return true;
}

_BuildEntries _readBuildEntries(_SuiteOptions options) {
  if (options.mode == 'jit') return const _BuildEntries([]);
  final manifest = File(options.buildManifestPath);
  if (!manifest.existsSync()) {
    throw StateError(
      'Build manifest not found: ${manifest.path}. '
      'Run the handler-execution build first.',
    );
  }
  final decoded = jsonDecode(manifest.readAsStringSync());
  if (decoded is! Map<String, Object?> ||
      decoded['kind'] != 'oche-handler-execution-build' ||
      decoded['entries'] is! List<Object?>) {
    throw const FormatException('Invalid handler-execution build manifest.');
  }
  final entries = [
    for (final entry in decoded['entries']! as List<Object?>)
      _BuildEntry.fromJson(entry! as Map<String, Object?>),
  ].where((entry) => _implementations.contains(entry.implementation)).toList();
  for (final entry in entries) {
    entry.validate();
  }
  return _BuildEntries(entries);
}

final class _Workload {
  const _Workload(this.name, this.method, this.endpoint, this.expectedStatus);

  final String name;
  final String method;
  final String endpoint;
  final int expectedStatus;
}

final class _BuildEntries {
  const _BuildEntries(this.entries);

  final List<_BuildEntry> entries;

  _BuildEntry lookup(String implementation, int routeCount) {
    if (entries.isEmpty) {
      final candidate = switch (implementation) {
        'handler_phase1a_direct' => 'phase1a_direct',
        'handler_specialized' => 'specialized',
        'handler_uniform' => 'uniform',
        _ => null,
      };
      final sourcePath = candidate == null
          ? 'benchmarks/handler_execution/bin/raw_server.dart'
          : 'benchmarks/handler_execution/generated/'
                '${candidate}_$routeCount.dart';
      final source = File(sourcePath);
      return _BuildEntry(
        implementation: implementation,
        routeCount: candidate == null ? null : routeCount,
        sourcePath: sourcePath,
        executablePath: '',
        compileDurationMs: null,
        generatedSourceBytes: source.lengthSync(),
        generatedSourceLines: source.readAsLinesSync().length,
        sourceSha256: _sha256(source),
        supportSourcePath:
            'benchmarks/handler_execution/lib/handler_execution_benchmark.dart',
        supportSourceSha256: _sha256(
          File(
            'benchmarks/handler_execution/lib/'
            'handler_execution_benchmark.dart',
          ),
        ),
        executableBytes: null,
        executableSha256: null,
      );
    }
    return entries.singleWhere(
      (entry) =>
          entry.implementation == implementation &&
          (implementation == 'handler_raw' || entry.routeCount == routeCount),
      orElse: () => throw StateError(
        'No build entry for $implementation at $routeCount routes.',
      ),
    );
  }
}

final class _BuildEntry {
  const _BuildEntry({
    required this.implementation,
    required this.routeCount,
    required this.sourcePath,
    required this.executablePath,
    required this.compileDurationMs,
    required this.generatedSourceBytes,
    required this.generatedSourceLines,
    required this.sourceSha256,
    required this.supportSourcePath,
    required this.supportSourceSha256,
    required this.executableBytes,
    required this.executableSha256,
  });

  factory _BuildEntry.fromJson(Map<String, Object?> json) => _BuildEntry(
    implementation: json['implementation']! as String,
    routeCount: json['routeCount'] as int?,
    sourcePath: json['sourcePath']! as String,
    executablePath: json['executablePath']! as String,
    compileDurationMs: (json['compileDurationMs'] as num?)?.toDouble(),
    generatedSourceBytes: json['generatedSourceBytes']! as int,
    generatedSourceLines: json['generatedSourceLines']! as int,
    sourceSha256: json['sourceSha256']! as String,
    supportSourcePath: json['supportSourcePath']! as String,
    supportSourceSha256: json['supportSourceSha256']! as String,
    executableBytes: json['executableBytes']! as int,
    executableSha256: json['executableSha256']! as String,
  );

  final String implementation;
  final int? routeCount;
  final String sourcePath;
  final String executablePath;
  final double? compileDurationMs;
  final int generatedSourceBytes;
  final int generatedSourceLines;
  final String sourceSha256;
  final String supportSourcePath;
  final String supportSourceSha256;
  final int? executableBytes;
  final String? executableSha256;

  double? get aotBinarySizeMb =>
      executableBytes == null ? null : executableBytes! / (1024 * 1024);

  void validate() {
    final source = File(sourcePath);
    if (!source.existsSync() ||
        source.lengthSync() != generatedSourceBytes ||
        source.readAsLinesSync().length != generatedSourceLines ||
        _sha256(source) != sourceSha256) {
      throw StateError('Build manifest source is stale: $sourcePath');
    }
    final executable = File(executablePath);
    final supportSource = File(supportSourcePath);
    if (!supportSource.existsSync() ||
        _sha256(supportSource) != supportSourceSha256) {
      throw StateError(
        'Build manifest support source is stale: $supportSourcePath',
      );
    }
    if (!executable.existsSync() ||
        executable.lengthSync() != executableBytes ||
        _sha256(executable) != executableSha256) {
      throw StateError('Build manifest executable is stale: $executablePath');
    }
  }

  String launchPath(String mode) => mode == 'jit' ? sourcePath : executablePath;
}

final class _SuiteOptions {
  const _SuiteOptions({
    required this.mode,
    required this.host,
    required this.port,
    required this.routeCounts,
    required this.concurrencies,
    required this.durationSeconds,
    required this.warmupSeconds,
    required this.iterations,
    required this.loadGenerator,
    required this.ohaPath,
    required this.resultsDirectory,
    required this.cooldownSeconds,
    required this.environmentType,
    required this.workloadSets,
    required this.buildManifestPath,
    required this.suiteRunId,
  });

  final String mode;
  final String host;
  final int port;
  final List<int> routeCounts;
  final List<int> concurrencies;
  final int durationSeconds;
  final int warmupSeconds;
  final int iterations;
  final String loadGenerator;
  final String ohaPath;
  final String resultsDirectory;
  final int cooldownSeconds;
  final String? environmentType;
  final List<String> workloadSets;
  final String buildManifestPath;
  final String? suiteRunId;

  static _SuiteOptions parse(List<String> arguments) {
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
    const known = {
      'mode',
      'host',
      'port',
      'route-counts',
      'concurrency-sweep',
      'duration',
      'warmup',
      'iterations',
      'load-generator',
      'oha',
      'results-dir',
      'cooldown',
      'environment-type',
      'workload-sets',
      'build-manifest',
      'suite-run-id',
    };
    final unknown = values.keys.where((key) => !known.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown options: ${unknown.join(', ')}');
    }
    final mode = values['mode'] ?? 'aot';
    if (mode != 'jit' && mode != 'aot') {
      throw FormatException('--mode must be jit or aot.');
    }
    final loadGenerator = values['load-generator'] ?? 'oha';
    if (loadGenerator != 'oha' && loadGenerator != 'none') {
      throw FormatException('--load-generator must be oha or none.');
    }
    final routeCounts = _integerList(values['route-counts'] ?? '10,100,1000');
    if (routeCounts.any((value) => !const {10, 100, 1000}.contains(value))) {
      throw FormatException('--route-counts supports only 10, 100, and 1000.');
    }
    final concurrencies = _integerList(
      values['concurrency-sweep'] ?? '10,100,500',
    );
    final workloadSets = (values['workload-sets'] ?? 'sync,async')
        .split(',')
        .map((value) => value.trim())
        .toSet()
        .toList(growable: false);
    if (workloadSets.isEmpty ||
        workloadSets.any((value) => !_workloadSets.containsKey(value))) {
      throw FormatException(
        '--workload-sets must contain sync, async, and/or request.',
      );
    }
    final port = int.parse(values['port'] ?? '8080');
    final duration = int.parse(values['duration'] ?? '30');
    final warmup = int.parse(values['warmup'] ?? '5');
    final iterations = int.parse(values['iterations'] ?? '5');
    final cooldown = int.parse(values['cooldown'] ?? '2');
    final suiteRunId = values['suite-run-id'];
    if (port < 1 || port > 65535) {
      throw RangeError.range(port, 1, 65535, 'port');
    }
    if (concurrencies.isEmpty ||
        concurrencies.any((value) => value < 1) ||
        duration < 1 ||
        warmup < 0 ||
        iterations < 1 ||
        cooldown < 0) {
      throw RangeError(
        'Invalid benchmark duration, repetition, or load value.',
      );
    }
    if (suiteRunId != null &&
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(suiteRunId)) {
      throw FormatException(
        '--suite-run-id may contain only letters, digits, dot, underscore, '
        'and hyphen.',
      );
    }
    return _SuiteOptions(
      mode: mode,
      host: values['host'] ?? '127.0.0.1',
      port: port,
      routeCounts: routeCounts,
      concurrencies: concurrencies,
      durationSeconds: duration,
      warmupSeconds: warmup,
      iterations: iterations,
      loadGenerator: loadGenerator,
      ohaPath: values['oha'] ?? 'oha',
      resultsDirectory: values['results-dir'] ?? 'benchmarks/results',
      cooldownSeconds: cooldown,
      environmentType: values['environment-type'],
      workloadSets: workloadSets,
      buildManifestPath:
          values['build-manifest'] ??
          'benchmarks/results/phase1b-build-${Platform.operatingSystem}.json',
      suiteRunId: suiteRunId,
    );
  }
}

List<int> _integerList(String value) => value
    .split(',')
    .map((item) => int.parse(item.trim()))
    .toSet()
    .toList(growable: false);

String _sha256(File file) => sha256.convert(file.readAsBytesSync()).toString();
