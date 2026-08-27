import 'package:oche_benchmark_harness/numeric_summary.dart';
import 'package:test/test.dart';

void main() {
  test('summarizes odd repeated samples', () {
    final summary = summarizeNumbers([5, 1, 3]);

    expect(summary, isNotNull);
    expect(summary?.sampleCount, 3);
    expect(summary?.minimum, 1);
    expect(summary?.median, 3);
    expect(summary?.maximum, 5);
    expect(summary?.standardDeviation, closeTo(1.632993, 0.000001));
  });

  test('uses the midpoint for an even sample count', () {
    final summary = summarizeNumbers([4, 1, 2, 3]);

    expect(summary?.median, 2.5);
  });

  test('returns null for unavailable measurements', () {
    expect(summarizeNumbers(const []), isNull);
  });
}
