import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('generated public application HTTP behavior', () {
    late Process server;
    late HttpClient client;
    late int port;
    final stderr = StringBuffer();

    setUpAll(() async {
      port = await _unusedPort();
      server = await Process.start(Platform.resolvedExecutable, [
        'run',
        'examples/hello_oche/bin/server.dart',
        '--port=$port',
      ], workingDirectory: Directory.current.path);
      server.stderr
          .transform(utf8.decoder)
          .listen(stderr.write, onError: (_) {});
      final ready = Completer<void>();
      server.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.contains('ready on')) ready.complete();
          });
      await Future.any<void>([
        ready.future,
        server.exitCode.then<void>((code) {
          throw StateError('Example server exited with $code: $stderr');
        }),
      ]).timeout(const Duration(seconds: 20));
      client = HttpClient();
    });

    tearDownAll(() async {
      client.close(force: true);
      server.kill();
      await server.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          server.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    });

    test('runs literal, String, int, sync, and async handlers', () async {
      expect(
        await _request(client, port, 'GET', '/hello'),
        _response(200, 'Hello, World!'),
      );
      expect(
        await _request(client, port, 'GET', '/hello/Guilherme'),
        _response(200, 'Hello, Guilherme!'),
      );
      expect(
        await _request(client, port, 'GET', '/users/42'),
        _response(200, 'User 42'),
      );
      expect(
        await _request(client, port, 'GET', '/users/search'),
        _response(200, 'User search'),
      );
    });

    test('maps invalid, missing, and method-mismatch routes', () async {
      expect(
        (await _request(client, port, 'GET', '/users/nope')).status,
        HttpStatus.badRequest,
      );
      expect(
        (await _request(client, port, 'GET', '/missing')).status,
        HttpStatus.notFound,
      );
      final mismatch = await _request(client, port, 'POST', '/users/42');
      expect(mismatch.status, HttpStatus.methodNotAllowed);
      expect(mismatch.allow, 'GET, PUT, PATCH, DELETE');
    });

    test('maps void and byte return shapes', () async {
      expect(
        (await _request(client, port, 'POST', '/hello/Ada')).status,
        HttpStatus.noContent,
      );
      expect(
        await _request(client, port, 'PATCH', '/users/42'),
        _response(200, '42'),
      );
      expect(
        await _request(client, port, 'DELETE', '/users/42'),
        _response(200, 'deleted 42'),
      );
    });

    test('maps sync and async failures without leaking details', () async {
      for (final path in const ['/errors/sync', '/errors/async']) {
        final response = await _request(client, port, 'GET', path);
        expect(response.status, HttpStatus.internalServerError);
        expect(response.body, '{"error":"internal server error"}');
        expect(response.body, isNot(contains('sensitive')));
      }
    });

    test('exposes equivalent Linux validation workloads', () async {
      expect(
        await _request(client, port, 'GET', '/validation/sync'),
        _response(200, 'Hello, World!'),
      );
      expect(
        await _request(client, port, 'GET', '/validation/async'),
        _response(200, 'Hello, World!'),
      );
      expect(
        await _request(client, port, 'GET', '/validation/users/42'),
        _response(200, 'User 42'),
      );
    });
  });
}

Future<int> _unusedPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<_HttpResult> _request(
  HttpClient client,
  int port,
  String method,
  String path,
) async {
  final request = await client.openUrl(
    method,
    Uri.parse('http://127.0.0.1:$port$path'),
  );
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  return _HttpResult(
    response.statusCode,
    body,
    response.headers.value(HttpHeaders.allowHeader),
  );
}

_HttpResult _response(int status, String body) =>
    _HttpResult(status, body, null);

final class _HttpResult {
  const _HttpResult(this.status, this.body, this.allow);

  final int status;
  final String body;
  final String? allow;

  @override
  bool operator ==(Object other) =>
      other is _HttpResult &&
      status == other.status &&
      body == other.body &&
      allow == other.allow;

  @override
  int get hashCode => Object.hash(status, body, allow);

  @override
  String toString() => '_HttpResult($status, $body, allow: $allow)';
}
