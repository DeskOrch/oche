import 'dart:convert';
import 'dart:io';

import 'package:routing_kernel_benchmark/kernel_source_generator.dart';
import 'package:routing_kernel_benchmark/routing_kernel_benchmark.dart';
import 'package:test/test.dart';

typedef _Response = ({
  int statusCode,
  String? mimeType,
  List<String> allow,
  String body,
});

void main() {
  group('source generation', () {
    test('is deterministic for every required route count', () {
      for (final candidate in KernelCandidate.values) {
        var previousLength = 0;
        for (final count in const [10, 100, 1000]) {
          final first = generateKernelSource(candidate, count);
          final second = generateKernelSource(candidate, count);
          expect(first, second);
          expect(first.length, greaterThan(previousLength));
          expect(first, isNot(contains('Map<String, String>')));
          expect(first, isNot(contains('RegExp')));
          previousLength = first.length;
        }
      }
    });

    test('security path checks reject ambiguous decoded paths', () {
      expect(kernelPathSegments(Uri.parse('/users/')), isNull);
      expect(kernelPathSegments(Uri.parse('/users//42')), isNull);
      expect(kernelPathSegments(Uri.parse('/users/%2F')), isNull);
      expect(kernelPathSegments(Uri.parse('/users/%5C')), isNull);
      // Dart normalizes this encoded dot segment to the root before dispatch.
      expect(kernelPathSegments(Uri.parse('/users/%2E%2E')), isEmpty);
      expect(kernelPathSegments(Uri.parse('/users/42?expand=orders')), [
        'users',
        '42',
      ]);
    });
  });

  for (final candidate in KernelCandidate.values) {
    group('${candidate.name} generated dispatcher', () {
      late Directory directory;
      late _GeneratedServer server;
      late HttpClient client;
      var started = false;

      setUpAll(() async {
        final buildDirectory = Directory('build');
        await buildDirectory.create(recursive: true);
        directory = await buildDirectory.createTemp(
          'oche-routing-${candidate.name}-',
        );
        final source = File('${directory.path}/${candidate.name}_100.dart');
        await source.writeAsString(generateKernelSource(candidate, 100));
        server = await _GeneratedServer.start(source.path);
        client = HttpClient();
        started = true;
      });

      tearDownAll(() async {
        if (started) {
          client.close(force: true);
          await server.close();
        }
        await directory.delete(recursive: true);
      });

      test('literal route wins over the parameter route', () async {
        final response = await _request(client, server.port, '/users/search');
        expect(response.statusCode, HttpStatus.ok);
        expect(jsonDecode(response.body), {
          'users': <Object>[],
          'query': 'search',
        });
      });

      test('binds one and multiple typed parameters directly', () async {
        final user = await _request(client, server.port, '/users/42');
        final order = await _request(
          client,
          server.port,
          '/users/42/orders/91',
        );
        expect(jsonDecode(user.body), {'id': 42});
        expect(jsonDecode(order.body), {'userId': 42, 'orderId': 91});
      });

      test('rejects an invalid integer without leaking internals', () async {
        final response = await _request(client, server.port, '/users/abc');
        expect(response.statusCode, HttpStatus.badRequest);
        expect(jsonDecode(response.body), {'error': 'id must be an integer'});
      });

      test('distinguishes missing, extra, and unknown paths', () async {
        for (final path in [
          '/users/',
          '/users/42/extra',
          '/does-not-exist',
          '/user',
          '/users2',
        ]) {
          final response = await _request(client, server.port, path);
          expect(response.statusCode, HttpStatus.notFound, reason: path);
        }
      });

      test('does not normalize duplicate or trailing slashes', () async {
        for (final path in [
          '/users//42',
          '/api/v1/status/',
          '/users/%2F',
          '/users/%5C',
        ]) {
          final response = await _request(client, server.port, path);
          expect(response.statusCode, HttpStatus.notFound, reason: path);
        }
      });

      test('keeps the query string outside route matching', () async {
        final response = await _request(
          client,
          server.port,
          '/users/42?expand=orders',
        );
        expect(response.statusCode, HttpStatus.ok);
        expect(jsonDecode(response.body), {'id': 42});
      });

      test('returns stable 405 and Allow semantics', () async {
        final users = await _request(
          client,
          server.port,
          '/users',
          method: 'DELETE',
        );
        final product = await _request(
          client,
          server.port,
          '/products/sku-42',
          method: 'DELETE',
        );
        expect(users.statusCode, HttpStatus.methodNotAllowed);
        expect(users.allow, ['GET, POST']);
        expect(product.allow, ['GET, PUT, PATCH']);
      });

      test('dispatches POST, PUT, PATCH, and DELETE handlers', () async {
        final created = await _request(
          client,
          server.port,
          '/users',
          method: 'POST',
        );
        final updated = await _request(
          client,
          server.port,
          '/products/sku-42',
          method: 'PUT',
        );
        final patched = await _request(
          client,
          server.port,
          '/products/sku-42',
          method: 'PATCH',
        );
        final deleted = await _request(
          client,
          server.port,
          '/users/42',
          method: 'DELETE',
        );
        expect(created.statusCode, HttpStatus.created);
        expect(jsonDecode(updated.body), {'sku': 'sku-42', 'updated': true});
        expect(jsonDecode(patched.body), {'sku': 'sku-42', 'patched': true});
        expect(deleted.statusCode, HttpStatus.noContent);
      });

      test(
        'maps expected and unexpected handler failures generically',
        () async {
          final expected = await _request(
            client,
            server.port,
            '/errors/expected',
          );
          final unexpected = await _request(
            client,
            server.port,
            '/errors/unexpected',
          );
          expect(expected.statusCode, HttpStatus.conflict);
          expect(expected.body, '{"error":"expected failure"}');
          expect(expected.body, isNot(contains('sensitive')));
          expect(unexpected.statusCode, HttpStatus.internalServerError);
          expect(unexpected.body, '{"error":"internal server error"}');
          expect(unexpected.body, isNot(contains('sensitive')));
        },
      );

      test('resolves generated literal and nested-parameter shapes', () async {
        final literal = await _request(
          client,
          server.port,
          '/generated/r0/literal',
        );
        final nested = await _request(
          client,
          server.port,
          '/generated/r2/items/42/children/91',
        );
        expect(jsonDecode(literal.body), {
          'route': 10,
          'first': -1,
          'second': -1,
        });
        expect(jsonDecode(nested.body), {
          'route': 12,
          'first': 42,
          'second': 91,
        });
      });
    });
  }
}

Future<_Response> _request(
  HttpClient client,
  int port,
  String path, {
  String method = 'GET',
}) async {
  final request = await client.openUrl(
    method,
    Uri.parse('http://127.0.0.1:$port$path'),
  );
  final response = await request.close();
  return (
    statusCode: response.statusCode,
    mimeType: response.headers.contentType?.mimeType,
    allow: response.headers[HttpHeaders.allowHeader] ?? const [],
    body: await utf8.decoder.bind(response).join(),
  );
}

final class _GeneratedServer {
  const _GeneratedServer(this.process, this.port);

  final Process process;
  final int port;

  static Future<_GeneratedServer> start(String sourcePath) async {
    final process = await Process.start(Platform.resolvedExecutable, [
      'run',
      sourcePath,
      '--host=127.0.0.1',
      '--port=0',
    ]);
    final stderrText = StringBuffer();
    process.stderr.transform(systemEncoding.decoder).listen(stderrText.write);
    try {
      final line = await process.stdout
          .transform(systemEncoding.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 30));
      final port = int.tryParse(line.split(':').last);
      if (port == null) throw FormatException('Invalid readiness line: $line');
      return _GeneratedServer(process, port);
    } on Object {
      process.kill();
      await process.exitCode;
      throw StateError('Generated server failed to start: $stderrText');
    }
  }

  Future<void> close() async {
    process.kill();
    await process.exitCode.timeout(const Duration(seconds: 5));
  }
}
