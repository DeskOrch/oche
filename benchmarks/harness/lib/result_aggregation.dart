/// Aggregation of raw Oche HTTP benchmark trials.
library;

import 'dart:convert';
import 'dart:io';

import 'package:oche_benchmark_harness/numeric_summary.dart';

const _metricPaths = <String, List<String>>{
  'startupMs': ['startupMs'],
  'requestsPerSecond': ['requestsPerSecond'],
  'successRate': ['successRate'],
  'p50Ms': ['latency', 'p50Ms'],
  'p95Ms': ['latency', 'p95Ms'],
  'p99Ms': ['latency', 'p99Ms'],
  'idleRssMb': ['memory', 'idleRssMb'],
  'peakLoadRssMb': ['memory', 'peakLoadRssMb'],
  'cpuUtilizationPercent': ['cpuUtilizationPercent'],
  'binarySizeMb': ['binarySizeMb'],
};

const _relativeMetricDirections = <String, String>{
  'requestsPerSecond': 'higherIsBetter',
  'p99Ms': 'lowerIsBetter',
  'idleRssMb': 'lowerIsBetter',
  'peakLoadRssMb': 'lowerIsBetter',
  'binarySizeMb': 'lowerIsBetter',
};

/// Reads raw trial JSON files and returns a grouped aggregate document.
Future<Map<String, Object>> aggregateResultFiles(List<String> paths) async {
  if (paths.isEmpty) {
    throw ArgumentError.value(
      paths,
      'paths',
      'At least one trial is required.',
    );
  }

  final groups = <_GroupKey, List<_Trial>>{};
  for (final path in paths) {
    final decoded =
        jsonDecode(await File(path).readAsString()) as Map<String, Object?>;
    final key = _GroupKey.fromJson(decoded);
    groups.putIfAbsent(key, () => []).add(_Trial(path, decoded));
  }

  final sortedEntries = groups.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  final aggregateGroups = <Map<String, Object>>[];
  final aggregateByKey = <_GroupKey, Map<String, Object>>{};
  for (final entry in sortedEntries) {
    final metrics = <String, Object>{};
    for (final metric in _metricPaths.entries) {
      final values = entry.value
          .map((trial) => _readNumber(trial.json, metric.value))
          .whereType<double>();
      final summary = summarizeNumbers(values);
      if (summary != null) metrics[metric.key] = summary.toJson();
    }

    final unavailable =
        entry.value
            .expand((trial) => _readStrings(trial.json, 'unavailableMetrics'))
            .toSet()
            .toList()
          ..sort();
    final aggregateGroup = <String, Object>{
      ...entry.key.toJson(),
      'trialCount': entry.value.length,
      'rawTrialFiles': entry.value.map((trial) => trial.path).toList(),
      'metrics': metrics,
      if (unavailable.isNotEmpty) 'unavailableMetrics': unavailable,
    };
    aggregateGroups.add(aggregateGroup);
    aggregateByKey[entry.key] = aggregateGroup;
  }

  final rawByComparison = <String, Map<String, Object>>{};
  for (final entry in aggregateByKey.entries) {
    if (entry.key.implementation == 'raw_dart_io') {
      rawByComparison[entry.key.comparisonFingerprint] = entry.value;
    }
  }
  for (final entry in aggregateByKey.entries) {
    final raw = rawByComparison[entry.key.comparisonFingerprint];
    if (raw == null) continue;
    final relative = _relativeMetrics(entry.value, raw);
    if (relative.isNotEmpty) entry.value['relativeToRaw'] = relative;
  }

  return {
    'schemaVersion': 1,
    'kind': 'oche-http-benchmark-aggregate',
    'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'rawTrialCount': paths.length,
    'groups': aggregateGroups,
  };
}

Map<String, Object> _relativeMetrics(
  Map<String, Object> group,
  Map<String, Object> rawGroup,
) {
  final metrics = group['metrics'];
  final rawMetrics = rawGroup['metrics'];
  if (metrics is! Map<String, Object> || rawMetrics is! Map<String, Object>) {
    return const {};
  }

  final relative = <String, Object>{};
  for (final specification in _relativeMetricDirections.entries) {
    final summary = metrics[specification.key];
    final rawSummary = rawMetrics[specification.key];
    if (summary is! Map<String, Object> || rawSummary is! Map<String, Object>) {
      continue;
    }
    final median = summary['median'];
    final rawMedian = rawSummary['median'];
    if (median is! num || rawMedian is! num || rawMedian == 0) continue;
    final percentOfRaw = median.toDouble() / rawMedian.toDouble() * 100;
    relative[specification.key] = {
      'basis': 'groupMedian',
      'percentOfRaw': percentOfRaw,
      'deltaPercent': percentOfRaw - 100,
      'preferredDirection': specification.value,
    };
  }
  return relative;
}

double? _readNumber(Map<String, Object?> json, List<String> path) {
  Object? current = json;
  for (final segment in path) {
    if (current is! Map<String, Object?>) return null;
    current = current[segment];
  }
  return current is num ? current.toDouble() : null;
}

Iterable<String> _readStrings(Map<String, Object?> json, String key) sync* {
  final values = json[key];
  if (values is! List<Object?>) return;
  for (final value in values) {
    if (value is String) yield value;
  }
}

final class _Trial {
  const _Trial(this.path, this.json);

  final String path;
  final Map<String, Object?> json;
}

final class _GroupKey implements Comparable<_GroupKey> {
  const _GroupKey({
    required this.implementation,
    required this.mode,
    required this.host,
    required this.endpoint,
    required this.concurrency,
    required this.durationSeconds,
    required this.warmupSeconds,
    required this.loadGenerator,
    required this.environment,
  });

  factory _GroupKey.fromJson(Map<String, Object?> json) => _GroupKey(
    implementation: _requiredString(json, 'implementation'),
    mode: _requiredString(json, 'mode'),
    host: _requiredString(json, 'host'),
    endpoint: _requiredString(json, 'endpoint'),
    concurrency: _requiredInt(json, 'concurrency'),
    durationSeconds: _requiredInt(json, 'durationSeconds'),
    warmupSeconds: _requiredInt(json, 'warmupSeconds'),
    loadGenerator: _requiredString(json, 'loadGenerator'),
    environment: _optionalMap(json, 'environment'),
  );

  final String implementation;
  final String mode;
  final String host;
  final String endpoint;
  final int concurrency;
  final int durationSeconds;
  final int warmupSeconds;
  final String loadGenerator;
  final Map<String, Object?> environment;

  Map<String, Object> toJson() => {
    'implementation': implementation,
    'mode': mode,
    'host': host,
    'endpoint': endpoint,
    'concurrency': concurrency,
    'durationSeconds': durationSeconds,
    'warmupSeconds': warmupSeconds,
    'loadGenerator': loadGenerator,
    if (environment.isNotEmpty) 'environment': environment,
  };

  @override
  int compareTo(_GroupKey other) => _sortKey.compareTo(other._sortKey);

  String get _sortKey =>
      '$implementation\u0000$endpoint\u0000$concurrency\u0000$mode\u0000'
      '${jsonEncode(environment)}';

  String get comparisonFingerprint => jsonEncode({
    'mode': mode,
    'host': host,
    'endpoint': endpoint,
    'concurrency': concurrency,
    'durationSeconds': durationSeconds,
    'warmupSeconds': warmupSeconds,
    'loadGenerator': loadGenerator,
    'environment': environment,
  });

  @override
  bool operator ==(Object other) =>
      other is _GroupKey &&
      implementation == other.implementation &&
      mode == other.mode &&
      host == other.host &&
      endpoint == other.endpoint &&
      concurrency == other.concurrency &&
      durationSeconds == other.durationSeconds &&
      warmupSeconds == other.warmupSeconds &&
      loadGenerator == other.loadGenerator &&
      jsonEncode(environment) == jsonEncode(other.environment);

  @override
  int get hashCode => Object.hash(
    implementation,
    mode,
    host,
    endpoint,
    concurrency,
    durationSeconds,
    warmupSeconds,
    loadGenerator,
    jsonEncode(environment),
  );
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('Expected string field "$key", got $value.');
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FormatException('Expected integer field "$key", got $value.');
}

Map<String, Object?> _optionalMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const {};
  if (value is Map<String, Object?>) return value;
  throw FormatException('Expected object field "$key", got $value.');
}
