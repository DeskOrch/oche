/// Machine-readable result model for the Oche benchmark harness.
library;

/// Measurements from one implementation, mode, and endpoint run.
final class BenchmarkResult {
  const BenchmarkResult({
    required this.timestampUtc,
    required this.implementation,
    required this.mode,
    required this.host,
    required this.port,
    required this.endpoint,
    required this.concurrency,
    required this.durationSeconds,
    required this.warmupSeconds,
    required this.loadGenerator,
    required this.startupMs,
    required this.environment,
    this.schedule,
    this.requestsPerSecond,
    this.successRate,
    this.p50Ms,
    this.p95Ms,
    this.p99Ms,
    this.idleRssMb,
    this.peakLoadRssMb,
    this.cpuUtilizationPercent,
    this.binarySizeMb,
    this.unavailableMetrics = const [],
  });

  final DateTime timestampUtc;
  final String implementation;
  final String mode;
  final String host;
  final int port;
  final String endpoint;
  final int concurrency;
  final int durationSeconds;
  final int warmupSeconds;
  final String loadGenerator;
  final double startupMs;
  final Map<String, Object> environment;
  final Map<String, Object>? schedule;
  final double? requestsPerSecond;
  final double? successRate;
  final double? p50Ms;
  final double? p95Ms;
  final double? p99Ms;
  final double? idleRssMb;
  final double? peakLoadRssMb;
  final double? cpuUtilizationPercent;
  final double? binarySizeMb;
  final List<String> unavailableMetrics;

  /// Encodes only measurements that were actually obtained.
  Map<String, Object> toJson() {
    final json = <String, Object>{
      'timestampUtc': timestampUtc.toIso8601String(),
      'implementation': implementation,
      'mode': mode,
      'host': host,
      'port': port,
      'endpoint': endpoint,
      'concurrency': concurrency,
      'durationSeconds': durationSeconds,
      'warmupSeconds': warmupSeconds,
      'loadGenerator': loadGenerator,
      'startupMs': startupMs,
      'environment': environment,
      'schedule': ?schedule,
    };

    if (requestsPerSecond case final value?) {
      json['requestsPerSecond'] = value;
    }
    if (successRate case final value?) json['successRate'] = value;

    final latency = <String, Object>{};
    if (p50Ms case final value?) latency['p50Ms'] = value;
    if (p95Ms case final value?) latency['p95Ms'] = value;
    if (p99Ms case final value?) latency['p99Ms'] = value;
    if (latency.isNotEmpty) json['latency'] = latency;

    final memory = <String, Object>{};
    if (idleRssMb case final value?) memory['idleRssMb'] = value;
    if (peakLoadRssMb case final value?) memory['peakLoadRssMb'] = value;
    if (memory.isNotEmpty) json['memory'] = memory;

    if (cpuUtilizationPercent case final value?) {
      json['cpuUtilizationPercent'] = value;
    }
    if (binarySizeMb case final value?) json['binarySizeMb'] = value;
    if (unavailableMetrics.isNotEmpty) {
      json['unavailableMetrics'] = unavailableMetrics;
    }
    return json;
  }
}
