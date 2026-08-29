import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:handler_execution_benchmark/handler_execution_benchmark.dart';
import 'package:handler_execution_benchmark/handler_source_generator.dart';
import 'package:test/test.dart';

void main() {
  group('generated handler execution candidates', () {
    for (final candidate in HandlerCandidate.values) {
      test('${candidate.name} preserves the complete HTTP contract', () async {
        final server = await _GeneratedServer.start(candidate);
        addTearDown(server.close);
        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        await _expectResponse(
          client,
          server.port,
          'GET',
          '/status',
          HttpStatus.ok,
          ContentType.json.toString(),
          {'status': 'ok'},
        );
        await _expectResponse(
          client,
          server.port,
          'GET',
          '/users/42',
          HttpStatus.ok,
          ContentType.json.toString(),
          {'id': 42},
        );
        await _expectResponse(
          client,
          server.port,
          'POST',
          '/users/42',
          HttpStatus.ok,
          ContentType.json.toString(),
          {'id': 42, 'name': 'user-42'},
        );
        await _expectResponse(
          client,
          server.port,
          'PUT',
          '/users/42',
          HttpStatus.ok,
          ContentType.json.toString(),
          {'id': 42, 'name': 'user-42'},
        );
        await _expectResponse(
          client,
          server.port,
          'GET',
          '/async/immediate/42',
          HttpStatus.ok,
          ContentType.json.toString(),
          {'id': 42},
        );
        await _expectResponse(
          client,
          server.port,
          'GET',
          '/async/boundary/42',
          HttpStatus.ok,
          ContentType.json.toString(),
          {'id': 42},
        );
        await _expectResponse(
          client,
          server.port,
          'GET',
          '/instance/42',
          HttpStatus.ok,
          ContentType.json.toString(),
          {'id': 42, 'name': 'instance-42'},
        );
        await _expectResponse(
          client,
          server.port,
          'POST',
          '/instance/42',
          HttpStatus.ok,
          ContentType.json.toString(),
          {'id': 42, 'name': 'instance-42'},
        );
        await _expectResponse(
          client,
          server.port,
          'GET',
          '/orders/42/items/91',
          HttpStatus.ok,
          ContentType.json.toString(),
          {'userId': 42, 'orderId': 91},
        );
        await _expectResponse(
          client,
          server.port,
          'GET',
          '/catalog/sku-1/items/9',
          HttpStatus.ok,
          ContentType.json.toString(),
          {'sku': 'sku-1', 'id': 9},
        );
        await _expectResponse(
          client,
          server.port,
          'GET',
          '/request/raw',
          HttpStatus.ok,
          ContentType.json.toString(),
          {'request': true},
        );
        await _expectResponse(
          client,
          server.port,
          'GET',
          '/request/view',
          HttpStatus.ok,
          ContentType.json.toString(),
          {'request': true},
        );

        final bytes = await _request(client, server.port, 'GET', '/payload');
        expect(bytes.statusCode, HttpStatus.ok);
        expect(bytes.contentType, ContentType.binary.toString());
        expect(bytes.bodyBytes, [79, 99, 104, 101]);

        for (final method in ['DELETE', 'POST']) {
          final empty = await _request(client, server.port, method, '/payload');
          expect(empty.statusCode, HttpStatus.noContent);
          expect(empty.contentType, ContentType.text.toString());
          expect(empty.bodyBytes, isEmpty);
        }

        final invalid = await _request(
          client,
          server.port,
          'GET',
          '/users/nope',
        );
        expect(invalid.statusCode, HttpStatus.badRequest);
        expect(invalid.contentType, ContentType.json.toString());
        expect(jsonDecode(utf8.decode(invalid.bodyBytes)), {
          'error': 'id must be an integer',
        });

        final expected = await _request(
          client,
          server.port,
          'GET',
          '/errors/expected',
        );
        expect(expected.statusCode, HttpStatus.conflict);
        expect(expected.contentType, ContentType.json.toString());
        expect(utf8.decode(expected.bodyBytes), '{"error":"expected failure"}');

        final unexpected = await _request(
          client,
          server.port,
          'GET',
          '/errors/unexpected',
        );
        expect(unexpected.statusCode, HttpStatus.internalServerError);
        expect(unexpected.contentType, ContentType.json.toString());
        expect(
          utf8.decode(unexpected.bodyBytes),
          '{"error":"internal server error"}',
        );

        final wrongMethod = await _request(
          client,
          server.port,
          'PATCH',
          '/status',
        );
        expect(wrongMethod.statusCode, HttpStatus.methodNotAllowed);
        expect(wrongMethod.contentType, ContentType.text.toString());
        expect(wrongMethod.allow, ['GET']);
        expect(utf8.decode(wrongMethod.bodyBytes), 'Method Not Allowed');

        final missing = await _request(client, server.port, 'GET', '/missing');
        expect(missing.statusCode, HttpStatus.notFound);
        expect(missing.contentType, ContentType.text.toString());
        expect(utf8.decode(missing.bodyBytes), 'Not Found');
      }, timeout: const Timeout(Duration(seconds: 60)));
    }
  });

  test('all adapter candidates retain an identical generated route tree', () {
    final sources = [
      for (final candidate in HandlerCandidate.values)
        generateHandlerSource(candidate, 10),
    ];
    final dispatches = [
      for (final source in sources)
        source.substring(source.indexOf('void generatedHandlerDispatch')),
    ];

    expect(dispatches.toSet(), hasLength(1));
    expect(sources[1], contains('handlerBenchmarkController.findById(id)'));
    expect(sources[1], isNot(contains('executeUniformResult')));
    expect(sources[2], contains('executeUniformResult'));
    for (final source in sources) {
      expect(source, isNot(contains('Function.apply')));
      expect(source, isNot(contains('Map<String, dynamic>')));
      expect(source, isNot(contains('dynamic argument')));
    }
  });

  test('uniform result normalization maps every internal result kind', () {
    expect(
      normalizeUniformResult('ok', ExperimentalResultKind.text).contentType,
      ContentType.text,
    );
    expect(
      utf8.decode(
        normalizeUniformResult(
          '{"ok":true}',
          ExperimentalResultKind.jsonString,
        ).body,
      ),
      '{"ok":true}',
    );
    expect(
      normalizeUniformResult(<int>[1, 2], ExperimentalResultKind.bytes).body,
      [1, 2],
    );
    expect(
      normalizeUniformResult(null, ExperimentalResultKind.noContent).statusCode,
      HttpStatus.noContent,
    );
    expect(
      jsonDecode(
        utf8.decode(
          normalizeUniformResult(
            const UserResult(7, 'Ada'),
            ExperimentalResultKind.user,
          ).body,
        ),
      ),
      {'id': 7, 'name': 'Ada'},
    );
  });
}

Future<void> _expectResponse(
  HttpClient client,
  int port,
  String method,
  String path,
  int statusCode,
  String contentType,
  Object body,
) async {
  final response = await _request(client, port, method, path);
  expect(response.statusCode, statusCode);
  expect(response.contentType, contentType);
  expect(jsonDecode(utf8.decode(response.bodyBytes)), body);
}

Future<
  ({
    int statusCode,
    String? contentType,
    List<String> allow,
    List<int> bodyBytes,
  })
>
_request(HttpClient client, int port, String method, String path) async {
  final request = await client.openUrl(
    method,
    Uri.http('127.0.0.1:$port', path),
  );
  final response = await request.close();
  return (
    statusCode: response.statusCode,
    contentType: response.headers.value(HttpHeaders.contentTypeHeader),
    allow: response.headers[HttpHeaders.allowHeader] ?? const [],
    bodyBytes: await response.fold<List<int>>(
      <int>[],
      (bytes, chunk) => bytes..addAll(chunk),
    ),
  );
}

final class _GeneratedServer {
  const _GeneratedServer({
    required this.port,
    required this.process,
    required this.directory,
    required this.stdoutText,
    required this.stderrText,
  });

  final int port;
  final Process process;
  final Directory directory;
  final StringBuffer stdoutText;
  final StringBuffer stderrText;

  static Future<_GeneratedServer> start(HandlerCandidate candidate) async {
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    final directory = await Directory.systemTemp.createTemp('oche-handler-');
    final source = File('${directory.path}/${candidate.name}_server.dart');
    await source.writeAsString(generateHandlerSource(candidate, 10));
    final process = await Process.start(Platform.resolvedExecutable, [
      '--packages=.dart_tool/package_config.json',
      'run',
      source.path,
      '--host=127.0.0.1',
      '--port=$port',
    ], workingDirectory: Directory.current.path);
    final stdoutText = StringBuffer();
    final stderrText = StringBuffer();
    process.stdout.transform(systemEncoding.decoder).listen(stdoutText.write);
    process.stderr.transform(systemEncoding.decoder).listen(stderrText.write);
    final server = _GeneratedServer(
      port: port,
      process: process,
      directory: directory,
      stdoutText: stdoutText,
      stderrText: stderrText,
    );
    try {
      await server._waitUntilReady();
      return server;
    } on Object {
      await server.close();
      rethrow;
    }
  }

  Future<void> _waitUntilReady() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 200);
    final watch = Stopwatch()..start();
    var exited = false;
    int? processExitCode;
    unawaited(
      process.exitCode.then((code) {
        exited = true;
        processExitCode = code;
      }),
    );
    try {
      while (watch.elapsed < const Duration(seconds: 20)) {
        if (exited) {
          throw StateError(
            'Generated server exited with $processExitCode.\n'
            'stdout: $stdoutText\nstderr: $stderrText',
          );
        }
        try {
          final request = await client.getUrl(
            Uri.http('127.0.0.1:$port', '/health'),
          );
          final response = await request.close();
          await response.drain<void>();
          if (response.statusCode == HttpStatus.ok) return;
        } on SocketException {
          // The generated process has not bound yet.
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } finally {
      client.close(force: true);
    }
    throw StateError(
      'Generated server did not become ready.\n'
      'stdout: $stdoutText\nstderr: $stderrText',
    );
  }

  Future<void> close() async {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}
