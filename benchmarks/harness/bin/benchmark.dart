import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:oche_benchmark_harness/benchmark_result.dart';
import 'package:oche_benchmark_harness/benchmark_schedule.dart';
import 'package:oche_benchmark_harness/environment_metadata.dart';

Future<void> main(List<String> arguments) async {
  final configuration = _Configuration.parse(arguments);
  final result = await _run(configuration);
  final output = const JsonEncoder.withIndent('  ').convert(result.toJson());

  if (configuration.outputPath case final path?) {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('$output\n');
    stdout.writeln('Wrote ${file.path}');
  } else {
    stdout.writeln(output);
  }
}

Future<BenchmarkResult> _run(_Configuration configuration) async {
  final environment = await collectEnvironmentMetadata(
    loadGenerator: configuration.loadGenerator,
    ohaPath: configuration.ohaPath,
    environmentTypeOverride: configuration.environmentType,
  );
  final launch = _serverLaunch(configuration);
  final executableFile = configuration.mode == 'aot'
      ? File(launch.command)
      : null;
  if (executableFile != null && !executableFile.existsSync()) {
    throw StateError(
      'AOT executable not found: ${executableFile.path}. '
      'Build it first or pass --executable.',
    );
  }

  final startupWatch = Stopwatch()..start();
  final process = await Process.start(launch.command, launch.arguments);
  final stdoutText = StringBuffer();
  final stderrText = StringBuffer();
  process.stdout.transform(systemEncoding.decoder).listen(stdoutText.write);
  process.stderr.transform(systemEncoding.decoder).listen(stderrText.write);

  try {
    await _waitUntilReady(
      configuration.readinessUrl,
      process,
      startupWatch,
      stdoutText,
      stderrText,
    );
    startupWatch.stop();

    final probe = _ProcessProbe(process.pid);
    final idle = await probe.snapshot();
    await _warmUp(
      configuration.url,
      configuration.warmupSeconds,
      method: configuration.requestMethod,
      expectedStatus: configuration.expectedStatus,
    );

    _LoadMetrics? load;
    double? peakLoadRssMb;
    double? cpuUtilizationPercent;
    if (configuration.loadGenerator == 'oha') {
      final cpuBefore = await probe.snapshot();
      var maxRssBytes = idle?.rssBytes ?? 0;
      var sampleInProgress = false;
      final timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (sampleInProgress) return;
        sampleInProgress = true;
        unawaited(
          probe
              .snapshot()
              .then((snapshot) {
                if (snapshot != null) {
                  maxRssBytes = max(maxRssBytes, snapshot.rssBytes);
                }
              })
              .whenComplete(() => sampleInProgress = false),
        );
      });

      final loadWatch = Stopwatch()..start();
      try {
        load = await _runOha(configuration);
      } finally {
        loadWatch.stop();
        timer.cancel();
      }
      final cpuAfter = await probe.snapshot();
      if (maxRssBytes > 0) peakLoadRssMb = _bytesToMb(maxRssBytes);
      if (cpuBefore != null && cpuAfter != null) {
        final cpuDelta = cpuAfter.cpuSeconds - cpuBefore.cpuSeconds;
        if (cpuDelta >= 0 && loadWatch.elapsedMicroseconds > 0) {
          cpuUtilizationPercent =
              cpuDelta / (loadWatch.elapsedMicroseconds / 1000000) * 100;
        }
      }
    }

    final unavailable = <String>[];
    if (load == null) {
      unavailable.addAll([
        'requestsPerSecond',
        'latency.p50Ms',
        'latency.p95Ms',
        'latency.p99Ms',
        'peakLoadRssMb',
        'cpuUtilizationPercent',
      ]);
    } else if (load.successRate == null) {
      unavailable.add('successRate');
    }
    if (idle == null) unavailable.add('idleRssMb');
    if (executableFile == null) unavailable.add('binarySizeMb');

    return BenchmarkResult(
      timestampUtc: DateTime.now().toUtc(),
      implementation: configuration.implementation,
      mode: configuration.mode,
      host: configuration.host,
      port: configuration.port,
      endpoint: configuration.endpoint,
      concurrency: configuration.concurrency,
      durationSeconds: configuration.durationSeconds,
      warmupSeconds: configuration.warmupSeconds,
      loadGenerator: configuration.loadGenerator,
      startupMs: startupWatch.elapsedMicroseconds / 1000,
      environment: environment,
      schedule: configuration.scheduleMetadata,
      requestMethod: configuration.requestMethod,
      expectedStatus: configuration.expectedStatus,
      routeCount: configuration.routeCount,
      workload: configuration.workload,
      middlewareDepth: configuration.middlewareDepth,
      middlewareProfile: configuration.middlewareProfile,
      generatedSourceBytes: configuration.generatedSourceBytes,
      generatedSourceLines: configuration.generatedSourceLines,
      generatedSourceSha256: await configuration.generatedSourceSha256,
      compileDurationMs: configuration.compileDurationMs,
      requestsPerSecond: load?.requestsPerSecond,
      successRate: load?.successRate,
      p50Ms: load?.p50Ms,
      p95Ms: load?.p95Ms,
      p99Ms: load?.p99Ms,
      idleRssMb: idle == null ? null : _bytesToMb(idle.rssBytes),
      peakLoadRssMb: peakLoadRssMb,
      cpuUtilizationPercent: cpuUtilizationPercent,
      binarySizeMb: executableFile == null
          ? null
          : _bytesToMb(executableFile.lengthSync()),
      executableSha256: executableFile == null
          ? null
          : await _sha256(executableFile),
      unavailableMetrics: unavailable,
    );
  } finally {
    await _stopProcess(process);
  }
}

({String command, List<String> arguments}) _serverLaunch(
  _Configuration configuration,
) {
  final serverArguments = [
    '--host',
    configuration.host,
    '--port',
    '${configuration.port}',
  ];
  if (configuration.mode == 'jit') {
    if (configuration.executablePath case final source?) {
      return (
        command: Platform.resolvedExecutable,
        arguments: ['run', source, ...serverArguments],
      );
    }
    return (
      command: Platform.resolvedExecutable,
      arguments: [
        'run',
        'benchmarks/${configuration.implementation}/bin/server.dart',
        ...serverArguments,
      ],
    );
  }

  final suffix = Platform.isWindows ? '.exe' : '';
  return (
    command:
        configuration.executablePath ??
        'build/${configuration.implementation}$suffix',
    arguments: serverArguments,
  );
}

Future<void> _waitUntilReady(
  Uri url,
  Process process,
  Stopwatch stopwatch,
  StringBuffer stdoutText,
  StringBuffer stderrText,
) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(milliseconds: 200);
  var exited = false;
  int? exitCode;
  unawaited(
    process.exitCode.then((code) {
      exited = true;
      exitCode = code;
    }),
  );

  try {
    while (stopwatch.elapsed < const Duration(seconds: 15)) {
      if (exited) {
        throw StateError(
          'Server exited with code $exitCode before readiness.\n'
          'stdout: $stdoutText\nstderr: $stderrText',
        );
      }
      try {
        final request = await client
            .getUrl(url)
            .timeout(const Duration(milliseconds: 250));
        final response = await request.close().timeout(
          const Duration(milliseconds: 250),
        );
        await response.drain<void>();
        if (response.statusCode == HttpStatus.ok) return;
      } on Object {
        // The process has not bound the listening socket yet.
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  } finally {
    client.close(force: true);
  }
  throw TimeoutException(
    'Server did not become ready at $url within 15 seconds.',
  );
}

Future<void> _warmUp(
  Uri url,
  int seconds, {
  required String method,
  required int expectedStatus,
}) async {
  if (seconds == 0) return;
  final client = HttpClient();
  final watch = Stopwatch()..start();
  try {
    while (watch.elapsed < Duration(seconds: seconds)) {
      final request = await client.openUrl(method, url);
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode != expectedStatus) {
        throw StateError(
          'Warmup received HTTP ${response.statusCode}; '
          'expected $expectedStatus.',
        );
      }
    }
  } finally {
    client.close(force: true);
  }
}

Future<_LoadMetrics> _runOha(_Configuration configuration) async {
  ProcessResult result;
  try {
    result = await Process.run(configuration.ohaPath, [
      '--no-tui',
      '--output-format',
      'json',
      '-z',
      '${configuration.durationSeconds}s',
      '-c',
      '${configuration.concurrency}',
      '-m',
      configuration.requestMethod,
      '${configuration.url}',
    ]);
  } on ProcessException catch (error) {
    throw StateError(
      'Could not run ${configuration.ohaPath}: ${error.message}. '
      'Install oha, pass --oha, or use --load-generator=none.',
    );
  }
  if (result.exitCode != 0) {
    throw StateError(
      'oha exited with ${result.exitCode}.\nstdout: ${result.stdout}\n'
      'stderr: ${result.stderr}',
    );
  }

  final decoded = jsonDecode(result.stdout as String) as Map<String, Object?>;
  final metrics = decoded['metrics'];
  if (metrics is Map<String, Object?>) {
    final latency = metrics['latency_ms'];
    if (latency is Map<String, Object?>) {
      return _LoadMetrics(
        requestsPerSecond: _requiredNumber(metrics, 'requests_per_sec'),
        successRate: _expectedStatusRate(
          decoded,
          configuration.expectedStatus,
          fallback:
              configuration.expectedStatus >= 200 &&
                  configuration.expectedStatus < 400
              ? _requiredNumber(metrics, 'success_rate')
              : null,
        ),
        p50Ms: _requiredNumber(latency, 'p50'),
        p95Ms: _requiredNumber(latency, 'p95'),
        p99Ms: _requiredNumber(latency, 'p99'),
      );
    }
  }

  final summary = decoded['summary'] as Map<String, Object?>;
  final percentiles = decoded['latencyPercentiles'] as Map<String, Object?>;
  return _LoadMetrics(
    requestsPerSecond: _requiredNumber(summary, 'requestsPerSec'),
    successRate: _expectedStatusRate(
      decoded,
      configuration.expectedStatus,
      fallback:
          configuration.expectedStatus >= 200 &&
              configuration.expectedStatus < 400
          ? _requiredNumber(summary, 'successRate')
          : null,
    ),
    p50Ms: _requiredNumber(percentiles, 'p50') * 1000,
    p95Ms: _requiredNumber(percentiles, 'p95') * 1000,
    p99Ms: _requiredNumber(percentiles, 'p99') * 1000,
  );
}

double? _expectedStatusRate(
  Map<String, Object?> json,
  int expectedStatus, {
  required double? fallback,
}) {
  final metrics = json['metrics'];
  final candidates = <Object?>[
    json['statusCodeDistribution'],
    json['status_code_distribution'],
    if (metrics is Map<String, Object?>) ...[
      metrics['statusCodeDistribution'],
      metrics['status_code_distribution'],
    ],
  ];
  for (final candidate in candidates) {
    if (candidate is! Map<String, Object?>) continue;
    var total = 0.0;
    var expected = 0.0;
    for (final entry in candidate.entries) {
      if (entry.value case final num count) {
        total += count.toDouble();
        if (entry.key == '$expectedStatus') expected += count.toDouble();
      }
    }
    if (total > 0) return expected / total;
  }
  return fallback;
}

double _requiredNumber(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  throw FormatException('Expected numeric oha field "$key", got $value.');
}

Future<void> _stopProcess(Process process) async {
  if (Platform.isWindows) {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(milliseconds: 500));
      return;
    } on TimeoutException {
      await Process.run('taskkill.exe', ['/PID', '${process.pid}', '/T', '/F']);
      await process.exitCode;
      return;
    }
  }
  process.kill(ProcessSignal.sigterm);
  try {
    await process.exitCode.timeout(const Duration(seconds: 3));
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
  }
}

double _bytesToMb(int bytes) => bytes / (1024 * 1024);

final class _ProcessProbe {
  const _ProcessProbe(this.pid);

  final int pid;

  Future<_ProcessSnapshot?> snapshot() async {
    if (Platform.isWindows) return _windowsSnapshot();
    if (Platform.isLinux || Platform.isMacOS) return _posixSnapshot();
    return null;
  }

  Future<_ProcessSnapshot?> _windowsSnapshot() async {
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      'Get-Process -Id $pid -ErrorAction Stop | '
          'Select-Object WorkingSet64,CPU | ConvertTo-Json -Compress',
    ]);
    if (result.exitCode != 0) return null;
    final json = jsonDecode(result.stdout as String) as Map<String, Object?>;
    final rss = json['WorkingSet64'];
    final cpu = json['CPU'];
    if (rss is! num || cpu is! num) return null;
    return _ProcessSnapshot(rssBytes: rss.toInt(), cpuSeconds: cpu.toDouble());
  }

  Future<_ProcessSnapshot?> _posixSnapshot() async {
    final result = await Process.run('ps', ['-o', 'rss=,time=', '-p', '$pid']);
    if (result.exitCode != 0) return null;
    final parts = (result.stdout as String).trim().split(RegExp(r'\s+'));
    if (parts.length != 2) return null;
    final rssKb = int.tryParse(parts.first);
    final cpuSeconds = _parseCpuTime(parts.last);
    if (rssKb == null || cpuSeconds == null) return null;
    return _ProcessSnapshot(rssBytes: rssKb * 1024, cpuSeconds: cpuSeconds);
  }
}

double? _parseCpuTime(String value) {
  var days = 0;
  var time = value;
  if (value.contains('-')) {
    final parts = value.split('-');
    if (parts.length != 2) return null;
    days = int.tryParse(parts.first) ?? -1;
    time = parts.last;
  }
  final fields = time.split(':');
  if (days < 0 || fields.length < 2 || fields.length > 3) return null;
  final seconds = double.tryParse(fields.last);
  final minutes = int.tryParse(fields[fields.length - 2]);
  final hours = fields.length == 3 ? int.tryParse(fields.first) : 0;
  if (seconds == null || minutes == null || hours == null) return null;
  return days * 86400 + hours * 3600 + minutes * 60 + seconds;
}

final class _ProcessSnapshot {
  const _ProcessSnapshot({required this.rssBytes, required this.cpuSeconds});

  final int rssBytes;
  final double cpuSeconds;
}

final class _LoadMetrics {
  const _LoadMetrics({
    required this.requestsPerSecond,
    required this.successRate,
    required this.p50Ms,
    required this.p95Ms,
    required this.p99Ms,
  });

  final double requestsPerSecond;
  final double? successRate;
  final double p50Ms;
  final double p95Ms;
  final double p99Ms;
}

final class _Configuration {
  const _Configuration({
    required this.implementation,
    required this.mode,
    required this.host,
    required this.port,
    required this.endpoint,
    required this.concurrency,
    required this.durationSeconds,
    required this.warmupSeconds,
    required this.loadGenerator,
    required this.ohaPath,
    required this.executablePath,
    required this.outputPath,
    required this.environmentType,
    required this.scheduleMetadata,
    required this.requestMethod,
    required this.expectedStatus,
    required this.readinessEndpoint,
    required this.routeCount,
    required this.workload,
    required this.middlewareDepth,
    required this.middlewareProfile,
    required this.generatedSourcePath,
    required this.compileDurationMs,
  });

  final String implementation;
  final String mode;
  final String host;
  final int port;
  final String endpoint;
  final int concurrency;
  final int durationSeconds;
  final int warmupSeconds;
  final String loadGenerator;
  final String ohaPath;
  final String? executablePath;
  final String? outputPath;
  final String? environmentType;
  final Map<String, Object>? scheduleMetadata;
  final String requestMethod;
  final int expectedStatus;
  final String readinessEndpoint;
  final int? routeCount;
  final String? workload;
  final int? middlewareDepth;
  final String? middlewareProfile;
  final String? generatedSourcePath;
  final double? compileDurationMs;

  Uri get url => Uri.http('$host:$port', endpoint);
  Uri get readinessUrl => Uri.http('$host:$port', readinessEndpoint);
  int? get generatedSourceBytes => generatedSourcePath == null
      ? null
      : File(generatedSourcePath!).lengthSync();
  int? get generatedSourceLines => generatedSourcePath == null
      ? null
      : File(generatedSourcePath!).readAsLinesSync().length;
  Future<String?> get generatedSourceSha256 => generatedSourcePath == null
      ? Future.value()
      : _sha256(File(generatedSourcePath!));

  static _Configuration parse(List<String> arguments) {
    final values = <String, String>{};
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (!argument.startsWith('--')) {
        throw FormatException('Expected an option, got: $argument');
      }
      final equals = argument.indexOf('=');
      if (equals >= 0) {
        values[argument.substring(2, equals)] = argument.substring(equals + 1);
      } else {
        if (index + 1 >= arguments.length) {
          throw FormatException('Missing value for $argument.');
        }
        values[argument.substring(2)] = arguments[++index];
      }
    }

    const known = {
      'implementation',
      'mode',
      'host',
      'port',
      'endpoint',
      'concurrency',
      'duration',
      'warmup',
      'load-generator',
      'oha',
      'executable',
      'output',
      'environment-type',
      'suite-run-id',
      'iteration',
      'trial-sequence',
      'implementation-order',
      'implementation-position',
      'endpoint-order',
      'endpoint-position',
      'cooldown',
      'method',
      'expected-status',
      'readiness-endpoint',
      'route-count',
      'workload',
      'middleware-depth',
      'middleware-profile',
      'generated-source',
      'compile-duration-ms',
    };
    final unknown = values.keys.where((key) => !known.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown options: ${unknown.join(', ')}');
    }

    final implementation = switch (values['implementation']) {
      'raw_dart_io' => 'raw_dart_io',
      'relic' => 'relic',
      'oche_static' => 'oche_static',
      'oche_tree' => 'oche_tree',
      'oche_indexed' => 'oche_indexed',
      'handler_raw' => 'handler_raw',
      'handler_phase1a_direct' => 'handler_phase1a_direct',
      'handler_specialized' => 'handler_specialized',
      'handler_uniform' => 'handler_uniform',
      'middleware_raw' => 'middleware_raw',
      'middleware_phase1b' => 'middleware_phase1b',
      'middleware_generated' => 'middleware_generated',
      'middleware_runtime' => 'middleware_runtime',
      _ => throw FormatException('--implementation is not recognized.'),
    };
    final mode = values['mode'] ?? 'jit';
    if (mode != 'jit' && mode != 'aot') {
      throw FormatException('--mode must be jit or aot.');
    }
    final loadGenerator = values['load-generator'] ?? 'oha';
    if (loadGenerator != 'oha' && loadGenerator != 'none') {
      throw FormatException('--load-generator must be oha or none.');
    }

    final port = int.parse(values['port'] ?? '8080');
    final concurrency = int.parse(values['concurrency'] ?? '100');
    final duration = int.parse(values['duration'] ?? '30');
    final warmup = int.parse(values['warmup'] ?? '5');
    final endpoint = values['endpoint'] ?? '/plaintext';
    final requestMethod = (values['method'] ?? 'GET').toUpperCase();
    final expectedStatus = int.parse(values['expected-status'] ?? '200');
    final readinessEndpoint = values['readiness-endpoint'] ?? endpoint;
    if (port < 1 || port > 65535) {
      throw RangeError.range(port, 1, 65535, 'port');
    }
    if (concurrency < 1 || duration < 1 || warmup < 0) {
      throw RangeError(
        'concurrency and duration must be positive; warmup >= 0.',
      );
    }
    if (!endpoint.startsWith('/') || !readinessEndpoint.startsWith('/')) {
      throw FormatException('endpoint options must start with /.');
    }
    const supportedMethods = {'GET', 'POST', 'PUT', 'PATCH', 'DELETE'};
    if (!supportedMethods.contains(requestMethod)) {
      throw FormatException('--method is not supported by this experiment.');
    }
    if (expectedStatus < 100 || expectedStatus > 599) {
      throw RangeError.range(expectedStatus, 100, 599, 'expected-status');
    }
    final middlewareDepth = _optionalInt(values, 'middleware-depth');
    if (middlewareDepth != null &&
        !const {0, 1, 3, 5, 10}.contains(middlewareDepth)) {
      throw FormatException('--middleware-depth supports 0, 1, 3, 5, and 10.');
    }

    return _Configuration(
      implementation: implementation,
      mode: mode,
      host: values['host'] ?? '127.0.0.1',
      port: port,
      endpoint: endpoint,
      concurrency: concurrency,
      durationSeconds: duration,
      warmupSeconds: warmup,
      loadGenerator: loadGenerator,
      ohaPath: values['oha'] ?? 'oha',
      executablePath: values['executable'],
      outputPath: values['output'],
      environmentType: values['environment-type'],
      requestMethod: requestMethod,
      expectedStatus: expectedStatus,
      readinessEndpoint: readinessEndpoint,
      routeCount: _optionalInt(values, 'route-count'),
      workload: values['workload'],
      middlewareDepth: middlewareDepth,
      middlewareProfile: values['middleware-profile'],
      generatedSourcePath: values['generated-source'],
      compileDurationMs: _optionalDouble(values, 'compile-duration-ms'),
      scheduleMetadata: benchmarkScheduleMetadata(
        suiteRunId: values['suite-run-id'],
        iteration: _optionalInt(values, 'iteration'),
        trialSequence: _optionalInt(values, 'trial-sequence'),
        implementationOrder: _optionalList(values, 'implementation-order'),
        implementationPosition: _optionalInt(values, 'implementation-position'),
        endpointOrder: _optionalList(values, 'endpoint-order'),
        endpointPosition: _optionalInt(values, 'endpoint-position'),
        cooldownSeconds: _optionalInt(values, 'cooldown'),
      ),
    );
  }
}

int? _optionalInt(Map<String, String> values, String key) {
  final value = values[key];
  return value == null ? null : int.parse(value);
}

List<String>? _optionalList(Map<String, String> values, String key) {
  final value = values[key];
  return value?.split(',');
}

double? _optionalDouble(Map<String, String> values, String key) {
  final value = values[key];
  return value == null ? null : double.parse(value);
}

Future<String> _sha256(File file) async =>
    sha256.bind(file.openRead()).first.then((digest) => digest.toString());
