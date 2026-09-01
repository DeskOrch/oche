import 'dart:convert';
import 'dart:io';

import 'package:oche_static_benchmark/oche_static_benchmark.dart';
import 'package:raw_dart_io_benchmark/raw_dart_io_benchmark.dart';
import 'package:relic_benchmark/relic_benchmark.dart';
import 'package:test/test.dart';

typedef _StartedServer = ({int port, Future<void> Function() close});
typedef _ServerFactory = Future<_StartedServer> Function();

void main() {
  _verifyServerContract('raw dart:io', () async {
    final server = await startRawDartIoBenchmarkServer(port: 0);
    return (port: server.port, close: server.close);
  }, supportsLinuxValidation: true);

  _verifyServerContract('Relic', () async {
    final server = await startRelicBenchmarkServer(port: 0);
    return (port: server.port, close: server.close);
  }, supportsLinuxValidation: true);

  _verifyServerContract('Oche static', () async {
    final server = await startOcheStaticBenchmarkServer(port: 0);
    return (port: server.port, close: server.close);
  });
}

void _verifyServerContract(
  String implementation,
  _ServerFactory start, {
  bool supportsLinuxValidation = false,
}) {
  group(implementation, () {
    late HttpClient client;
    late _StartedServer server;

    setUp(() async {
      client = HttpClient();
      server = await start();
    });

    tearDown(() async {
      client.close(force: true);
      await server.close();
    });

    test('GET /plaintext returns the plaintext workload', () async {
      final response = await _get(client, server.port, '/plaintext');

      expect(response.statusCode, HttpStatus.ok);
      expect(response.mimeType, ContentType.text.mimeType);
      expect(response.body, 'Hello, World!');
    });

    test('GET /json returns the fixed JSON workload', () async {
      final response = await _get(client, server.port, '/json');

      expect(response.statusCode, HttpStatus.ok);
      expect(response.mimeType, ContentType.json.mimeType);
      expect(jsonDecode(response.body), {'message': 'Hello, World!'});
    });

    test('GET /users/{id} returns the parsed route parameter', () async {
      final response = await _get(client, server.port, '/users/42');

      expect(response.statusCode, HttpStatus.ok);
      expect(response.mimeType, ContentType.json.mimeType);
      expect(jsonDecode(response.body), {'id': 42});
    });

    test('GET /users/{id} rejects a non-integer route parameter', () async {
      final response = await _get(client, server.port, '/users/not-an-int');

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.mimeType, ContentType.json.mimeType);
      expect(jsonDecode(response.body), {'error': 'id must be an integer'});
    });

    test('unknown routes return the same plain 404 response', () async {
      final response = await _get(client, server.port, '/missing');

      expect(response.statusCode, HttpStatus.notFound);
      expect(response.mimeType, ContentType.text.mimeType);
      expect(response.body, 'Not Found');
    });

    test('a known path with an incorrect method returns 405', () async {
      final response = await _request(
        client,
        server.port,
        '/plaintext',
        method: 'POST',
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
      expect(response.allow, contains('GET'));
    });

    test('an extra user path segment does not match', () async {
      final response = await _get(client, server.port, '/users/42/extra');

      expect(response.statusCode, HttpStatus.notFound);
      expect(response.body, 'Not Found');
    });

    if (supportsLinuxValidation) {
      test('exposes equivalent Linux validation workloads', () async {
        await _expectValidationResponse(
          client,
          server.port,
          '/validation/sync',
          'Hello, World!',
        );
        await _expectValidationResponse(
          client,
          server.port,
          '/validation/async',
          'Hello, World!',
        );
        await _expectValidationResponse(
          client,
          server.port,
          '/validation/users/42',
          'User 42',
        );
      });
    }
  });
}

Future<void> _expectValidationResponse(
  HttpClient client,
  int port,
  String path,
  String body,
) async {
  final response = await _get(client, port, path);
  expect(response.statusCode, HttpStatus.ok);
  expect(response.mimeType, ContentType.text.mimeType);
  expect(response.allow, isEmpty);
  expect(response.body, body);
}

Future<({int statusCode, String? mimeType, List<String> allow, String body})>
_get(HttpClient client, int port, String path) =>
    _request(client, port, path, method: 'GET');

Future<({int statusCode, String? mimeType, List<String> allow, String body})>
_request(
  HttpClient client,
  int port,
  String path, {
  required String method,
}) async {
  final request = await client.openUrl(
    method,
    Uri.http('127.0.0.1:$port', path),
  );
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  return (
    statusCode: response.statusCode,
    mimeType: response.headers.contentType?.mimeType,
    allow: response.headers[HttpHeaders.allowHeader] ?? const [],
    body: body,
  );
}
