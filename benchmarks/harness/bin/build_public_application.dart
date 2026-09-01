import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final outputDirectory = arguments.isEmpty
      ? 'build/phase2a'
      : arguments.single;
  final directory = Directory(outputDirectory);
  await directory.create(recursive: true);
  final executable = File(
    '${directory.path}/hello_oche${Platform.isWindows ? '.exe' : ''}',
  );
  final source = File('examples/hello_oche/lib/application.oche.dart');
  if (!source.existsSync()) {
    throw StateError(
      '${source.path} is missing. Run the Oche generator before compiling.',
    );
  }

  final watch = Stopwatch()..start();
  final process = await Process.start(Platform.resolvedExecutable, [
    'compile',
    'exe',
    'examples/hello_oche/bin/server.dart',
    '-o',
    executable.path,
  ], mode: ProcessStartMode.inheritStdio);
  final code = await process.exitCode;
  watch.stop();
  if (code != 0) exitCode = code;
  if (code != 0) return;

  final manifest = File('${directory.path}/public-application-build.json');
  final result = <String, Object>{
    'schemaVersion': 1,
    'kind': 'oche-public-application-build',
    'timestampUtc': DateTime.now().toUtc().toIso8601String(),
    'runtime': Platform.version,
    'sourcePath': source.path,
    'generatedSourceBytes': source.lengthSync(),
    'generatedSourceLines': source.readAsLinesSync().length,
    'executablePath': executable.path,
    'executableBytes': executable.lengthSync(),
    'compileDurationMs': watch.elapsedMicroseconds / 1000,
  };
  await manifest.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(result)}\n',
  );
  stdout.writeln('Wrote ${manifest.path}');
}
