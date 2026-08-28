import 'dart:convert';
import 'dart:io';

import 'package:routing_kernel_benchmark/kernel_source_generator.dart';

Future<void> main(List<String> arguments) async {
  final outputDirectory = arguments.isEmpty
      ? 'benchmarks/routing_kernel/generated'
      : arguments.single;
  final directory = Directory(outputDirectory);
  await directory.create(recursive: true);
  final files = <Map<String, Object>>[];
  for (final candidate in KernelCandidate.values) {
    for (final routeCount in const [10, 100, 1000]) {
      final source = generateKernelSource(candidate, routeCount);
      final file = File('${directory.path}/${candidate.name}_$routeCount.dart');
      await file.writeAsString(source);
      await _format(file);
      final lines = await file.readAsLines();
      files.add({
        'candidate': candidate.name,
        'routeCount': routeCount,
        'path': file.path,
        'bytes': file.lengthSync(),
        'lines': lines.length,
      });
      stdout.writeln('Generated ${file.path}');
    }
  }
  final manifest = File('${directory.path}/manifest.json');
  await manifest.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({'files': files})}\n',
  );
  stdout.writeln('Wrote ${manifest.path}');
}

Future<void> _format(File file) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'format',
    file.path,
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'Formatting failed for ${file.path}.\n'
      'stdout: ${result.stdout}\nstderr: ${result.stderr}',
    );
  }
}
