/// Relic HTTP baseline used by the Oche performance laboratory.
library;

import 'dart:io';

import 'package:relic/relic.dart';

const String _plaintextBody = 'Hello, World!';
const String _jsonBody = '{"message":"Hello, World!"}';
const String _invalidIdBody = '{"error":"id must be an integer"}';
const String _notFoundBody = 'Not Found';

/// A running Relic benchmark server.
final class RelicBenchmarkServer {
  RelicBenchmarkServer._(this._server);

  final RelicServer _server;

  /// The operating-system-assigned listening port.
  int get port => _server.port;

  /// Stops accepting requests and waits for active connections to finish.
  Future<void> close({bool force = false}) => _server.close(force: force);
}

/// Starts the Relic HTTP benchmark server.
Future<RelicBenchmarkServer> startRelicBenchmarkServer({
  InternetAddress? address,
  int port = 8080,
}) async {
  final app = RelicApp()
    ..get('/plaintext', _plaintext)
    ..get('/json', _json)
    ..get('/users/:id', _user)
    ..fallback = _notFound;

  final server = await app.serve(
    address: address ?? InternetAddress.loopbackIPv4,
    port: port,
  );
  return RelicBenchmarkServer._(server);
}

Response _plaintext(Request request) => Response.ok(
  body: Body.fromString(_plaintextBody, mimeType: MimeType.plainText),
);

Response _json(Request request) =>
    Response.ok(body: Body.fromString(_jsonBody, mimeType: MimeType.json));

Response _user(Request request) {
  final rawId = request.pathParameters.raw[#id];
  final id = rawId == null ? null : int.tryParse(rawId);
  if (id == null) {
    return Response.badRequest(
      body: Body.fromString(_invalidIdBody, mimeType: MimeType.json),
    );
  }
  return Response.ok(
    body: Body.fromString('{"id":$id}', mimeType: MimeType.json),
  );
}

Response _notFound(Request request) => Response.notFound(
  body: Body.fromString(_notFoundBody, mimeType: MimeType.plainText),
);
