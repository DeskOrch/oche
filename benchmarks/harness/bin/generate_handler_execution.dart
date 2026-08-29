import 'dart:io';

import 'package:handler_execution_benchmark/handler_execution_benchmark.dart';
import 'package:handler_execution_benchmark/handler_source_generator.dart';

Future<void> main(List<String> arguments) async {
  final outputDirectory = arguments.isEmpty
      ? 'benchmarks/handler_execution/generated'
      : arguments.single;
  final directory = Directory(outputDirectory);
  await directory.create(recursive: true);
  for (final candidate in HandlerCandidate.values) {
    for (final routeCount in const [10, 100, 1000]) {
      final file = File(
        '${directory.path}/${handlerSourceStem(candidate)}_$routeCount.dart',
      );
      await file.writeAsString(generateHandlerSource(candidate, routeCount));
      stdout.writeln('Wrote ${file.path}');
    }
  }
}
