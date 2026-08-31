import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:handler_execution_benchmark/middleware_execution_benchmark.dart';
import 'package:handler_execution_benchmark/middleware_source_generator.dart';
import 'package:test/test.dart';

void main() {
  final variants = <(MiddlewareCandidate, int)>[
    (MiddlewareCandidate.phase1b, 0),
    (MiddlewareCandidate.generated, 0),
    (MiddlewareCandidate.generated, 1),
    (MiddlewareCandidate.generated, 3),
    (MiddlewareCandidate.runtime, 0),
    (MiddlewareCandidate.runtime, 1),
    (MiddlewareCandidate.runtime, 3),
    (MiddlewareCandidate.shared, 0),
    (MiddlewareCandidate.shared, 1),
    (MiddlewareCandidate.shared, 3),
    (MiddlewareCandidate.shared, 5),
    (MiddlewareCandidate.shared, 10),
  ];

  for (final variant in variants) {
    final (candidate, depth) = variant;
    test(
      '${candidate.name} depth $depth preserves middleware semantics',
      () async {
        final server = await _GeneratedMiddlewareServer.start(candidate, depth);
        addTearDown(server.close);
        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        if (depth > 0) {
          for (final kind in ['short-sync', 'short-async']) {
            final short = await _request(
              client,
              server.port,
              'GET',
              '/middleware/$kind/42',
            );
            expect(short.statusCode, HttpStatus.unauthorized);
            expect(short.contentType, ContentType.json.toString());
            expect(short.header('x-handler-invocations'), ['0']);
            expect(jsonDecode(short.body), {'error': 'unauthorized'});
          }
        }

        await _expectJson(client, server.port, 'GET', '/users/42', {'id': 42});

        if (depth == 3) {
          for (final profile in ['sync', 'async', 'mixed']) {
            await _expectJson(
              client,
              server.port,
              'GET',
              '/async/$profile/42',
              {'id': 42},
            );
          }

          final order = await _request(
            client,
            server.port,
            'GET',
            '/middleware/order/42',
          );
          expect(order.statusCode, HttpStatus.ok);
          expect(order.header('x-middleware-order'), [
            'M0.before,M1.before,M2.before,handler,M2.after,M1.after,M0.after',
          ]);

          for (final kind in [
            'error-before',
            'error-handler',
            'error-after',
            'error-async',
          ]) {
            final error = await _request(
              client,
              server.port,
              'GET',
              '/middleware/$kind/42',
            );
            expect(error.statusCode, HttpStatus.internalServerError);
            expect(error.contentType, ContentType.json.toString());
            expect(error.body, '{"error":"internal server error"}');
            expect(error.body, isNot(contains('sensitive')));
          }

          for (final state in ['none', 'lazy', 'typed']) {
            await _expectJson(
              client,
              server.port,
              'GET',
              '/middleware/state-$state/42',
              {'id': 42},
            );
          }
          await _expectJson(
            client,
            server.port,
            'GET',
            '/middleware/instance/42',
            {'id': 42},
          );
          await _expectJson(client, server.port, 'GET', '/orders/42/items/91', {
            'userId': 42,
            'orderId': 91,
          });

          final expected = await _request(
            client,
            server.port,
            'GET',
            '/errors/expected',
          );
          expect(expected.statusCode, HttpStatus.conflict);
          expect(expected.body, '{"error":"expected failure"}');

          final invalid = await _request(
            client,
            server.port,
            'GET',
            '/users/nope',
          );
          expect(invalid.statusCode, HttpStatus.badRequest);
          expect(invalid.body, '{"error":"id must be an integer"}');

          final wrongMethod = await _request(
            client,
            server.port,
            'PATCH',
            '/users/42',
          );
          expect(wrongMethod.statusCode, HttpStatus.methodNotAllowed);
          expect(wrongMethod.header(HttpHeaders.allowHeader), ['GET']);

          final missing = await _request(
            client,
            server.port,
            'GET',
            '/missing',
          );
          expect(missing.statusCode, HttpStatus.notFound);
          expect(missing.body, 'Not Found');
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }

  test(
    'generated response-lifecycle candidate preserves the Phase 1D kernel',
    () async {
      final source = generateResponseLifecycleSource();
      expect(source, contains('enterSharedSyncPipeline3'));
      expect(source, contains('writeLifecycleJsonStringResult'));
      expect(source, contains('runResponseLifecycleBenchmarkServer'));
      expect(source, isNot(contains('runHandlerBenchmarkServer(')));

      final server = await _GeneratedMiddlewareServer.startResponseLifecycle();
      addTearDown(server.close);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      await _expectJson(client, server.port, 'GET', '/users/42', {'id': 42});
      await _expectJson(client, server.port, 'GET', '/async/sync/42', {
        'id': 42,
      });
      final short = await _request(
        client,
        server.port,
        'GET',
        '/middleware/short-sync/42',
      );
      expect(short.statusCode, HttpStatus.unauthorized);
      expect(short.body, '{"error":"unauthorized"}');
      final stream = await _request(client, server.port, 'GET', '/stream');
      expect(stream.statusCode, HttpStatus.ok);
      expect(stream.body, 'chunk 1\nchunk 2\nchunk 3\n');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('candidates retain an identical segmented dispatch tree', () {
    final sources = [
      for (final candidate in MiddlewareCandidate.values)
        generateMiddlewareSource(candidate, 10, 0),
    ];
    final dispatches = [
      for (final source in sources)
        source.substring(source.indexOf('void generatedMiddlewareDispatch')),
    ];
    expect(dispatches.toSet(), hasLength(1));
  });

  test('all middleware candidates remain statically typed', () {
    final generated = generateMiddlewareSource(
      MiddlewareCandidate.generated,
      100,
      3,
    );
    final runtime = generateMiddlewareSource(
      MiddlewareCandidate.runtime,
      100,
      3,
    );
    final shared = generateMiddlewareSource(MiddlewareCandidate.shared, 100, 3);
    expect(generated, contains('middlewareTwoIntHandler(userId, orderId)'));
    expect(generated, contains('generatedMiddlewareBefore'));
    expect(runtime, contains('runtimeMiddlewareSteps'));
    expect(runtime, contains('() => middlewareSyncHandler(id)'));
    expect(shared, contains('enterSharedSyncPipeline3'));
    expect(shared, contains('middlewareTwoIntHandler(userId, orderId)'));
    expect(shared, contains('middlewareImmediateAsyncHandler(id)'));
    expect(shared, isNot(contains('() =>')));
    expect(shared, isNot(contains('runtimeMiddlewareSteps')));
    for (final source in [generated, runtime, shared]) {
      expect(source, isNot(contains('Function.apply')));
      expect(source, isNot(contains('Map<String, dynamic>')));
      expect(source, isNot(contains('service locator')));
    }
  });
}

Future<void> _expectJson(
  HttpClient client,
  int port,
  String method,
  String path,
  Object body,
) async {
  final response = await _request(client, port, method, path);
  expect(response.statusCode, HttpStatus.ok);
  expect(response.contentType, ContentType.json.toString());
  expect(jsonDecode(response.body), body);
}

Future<
  ({
    int statusCode,
    String? contentType,
    Map<String, List<String>> headers,
    String body,
  })
>
_request(HttpClient client, int port, String method, String path) async {
  final request = await client.openUrl(
    method,
    Uri.http('127.0.0.1:$port', path),
  );
  final response = await request.close();
  final headers = <String, List<String>>{};
  response.headers.forEach((name, values) => headers[name] = values);
  return (
    statusCode: response.statusCode,
    contentType: response.headers.value(HttpHeaders.contentTypeHeader),
    headers: headers,
    body: await response.transform(utf8.decoder).join(),
  );
}

extension
    on
        ({
          int statusCode,
          String? contentType,
          Map<String, List<String>> headers,
          String body,
        }) {
  List<String> header(String name) => headers[name] ?? const [];
}

final class _GeneratedMiddlewareServer {
  const _GeneratedMiddlewareServer({
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

  static Future<_GeneratedMiddlewareServer> start(
    MiddlewareCandidate candidate,
    int depth,
  ) => _startSource(
    generateMiddlewareSource(candidate, 10, depth),
    'oche-middleware-',
  );

  static Future<_GeneratedMiddlewareServer> startResponseLifecycle() =>
      _startSource(generateResponseLifecycleSource(), 'oche-lifecycle-');

  static Future<_GeneratedMiddlewareServer> _startSource(
    String generatedSource,
    String temporaryPrefix,
  ) async {
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    final directory = await Directory.systemTemp.createTemp(temporaryPrefix);
    final source = File('${directory.path}/server.dart');
    await source.writeAsString(generatedSource);
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
    final server = _GeneratedMiddlewareServer(
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
