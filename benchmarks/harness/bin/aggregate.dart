import 'dart:convert';
import 'dart:io';

import 'package:oche_benchmark_harness/result_aggregation.dart';

Future<void> main(List<String> arguments) async {
  final options = _AggregateOptions.parse(arguments);
  final files =
      Directory(options.inputDirectory)
          .listSync()
          .whereType<File>()
          .where(
            (file) =>
                file.path.endsWith('.json') &&
                _basename(file.path).startsWith(options.prefix) &&
                !_basename(file.path).contains('-aggregate'),
          )
          .map((file) => file.path)
          .toList()
        ..sort();
  if (files.isEmpty) {
    throw StateError(
      'No raw JSON trials beginning with "${options.prefix}" in '
      '${options.inputDirectory}.',
    );
  }

  final aggregate = await aggregateResultFiles(files);
  final output = File(options.outputPath);
  await output.parent.create(recursive: true);
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(aggregate)}\n',
  );
  stdout.writeln('Aggregated ${files.length} trials into ${output.path}');
}

String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

final class _AggregateOptions {
  const _AggregateOptions({
    required this.inputDirectory,
    required this.prefix,
    required this.outputPath,
  });

  final String inputDirectory;
  final String prefix;
  final String outputPath;

  static _AggregateOptions parse(List<String> arguments) {
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
    const known = {'input-dir', 'prefix', 'output'};
    final unknown = values.keys.where((key) => !known.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown options: ${unknown.join(', ')}');
    }
    final prefix = values['prefix'];
    if (prefix == null || prefix.isEmpty) {
      throw FormatException('--prefix is required.');
    }
    return _AggregateOptions(
      inputDirectory: values['input-dir'] ?? 'benchmarks/results',
      prefix: prefix,
      outputPath:
          values['output'] ?? 'benchmarks/results/$prefix-aggregate.json',
    );
  }
}
