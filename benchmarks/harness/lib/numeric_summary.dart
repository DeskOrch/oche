/// Numeric summaries shared by benchmark aggregation tools.
library;

import 'dart:math';

/// Mean, median, extrema, and population standard deviation for samples.
final class NumericSummary {
  const NumericSummary({
    required this.sampleCount,
    required this.mean,
    required this.median,
    required this.minimum,
    required this.maximum,
    required this.standardDeviation,
  });

  final int sampleCount;
  final double mean;
  final double median;
  final double minimum;
  final double maximum;
  final double standardDeviation;

  Map<String, Object> toJson() => {
    'sampleCount': sampleCount,
    'mean': mean,
    'median': median,
    'minimum': minimum,
    'maximum': maximum,
    'standardDeviation': standardDeviation,
  };
}

/// Summarizes [values], or returns `null` when no measurements are available.
NumericSummary? summarizeNumbers(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return null;

  final middle = sorted.length ~/ 2;
  final median = sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
  final mean = sorted.reduce((left, right) => left + right) / sorted.length;
  final variance =
      sorted
          .map((value) => pow(value - mean, 2).toDouble())
          .reduce((left, right) => left + right) /
      sorted.length;

  return NumericSummary(
    sampleCount: sorted.length,
    mean: mean,
    median: median,
    minimum: sorted.first,
    maximum: sorted.last,
    standardDeviation: sqrt(variance),
  );
}
