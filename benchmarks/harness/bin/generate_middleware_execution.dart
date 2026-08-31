import 'dart:io';

import 'package:handler_execution_benchmark/middleware_execution_benchmark.dart';
import 'package:handler_execution_benchmark/middleware_source_generator.dart';

Future<void> main(List<String> arguments) async {
  final outputDirectory = arguments.isEmpty
      ? 'benchmarks/handler_execution/generated_middleware'
      : arguments.single;
  final directory = Directory(outputDirectory);
  await directory.create(recursive: true);
  for (final candidate in MiddlewareCandidate.values) {
    for (final routeCount in const [10, 100, 1000]) {
      final depths = candidate == MiddlewareCandidate.phase1b
          ? const [0]
          : routeCount == 100
          ? middlewareDepths
          : const [0, 1, 3];
      for (final depth in depths) {
        final file = File(
          '${directory.path}/${middlewareSourceStem(candidate)}_'
          'r${routeCount}_d$depth.dart',
        );
        await file.writeAsString(
          generateMiddlewareSource(candidate, routeCount, depth),
        );
        stdout.writeln('Wrote ${file.path}');
      }
    }
  }
  final lifecycle = File('${directory.path}/lifecycle_r100_d3.dart');
  await lifecycle.writeAsString(generateResponseLifecycleSource());
  stdout.writeln('Wrote ${lifecycle.path}');
}
