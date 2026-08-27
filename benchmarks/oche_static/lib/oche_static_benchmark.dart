/// Direct static-dispatch HTTP spike used by the Oche performance laboratory.
library;

import 'dart:async';
import 'dart:io';

const String _plaintextBody = 'Hello, World!';
const String _jsonBody = '{"message":"Hello, World!"}';
const String _invalidIdBody = '{"error":"id must be an integer"}';
const String _notFoundBody = 'Not Found';
const String _usersPrefix = '/users/';

final ContentType _plainTextType = ContentType(
  'text',
  'plain',
  charset: 'utf-8',
);
final ContentType _jsonType = ContentType(
  'application',
  'json',
  charset: 'utf-8',
);

/// A running instance of the static-routing spike.
final class OcheStaticBenchmarkServer {
  OcheStaticBenchmarkServer._(this._server);

  final HttpServer _server;

  /// The operating-system-assigned listening port.
  int get port => _server.port;

  /// Stops accepting requests and waits for active connections to finish.
  Future<void> close({bool force = false}) => _server.close(force: force);
}

/// Starts the static-routing HTTP benchmark server.
Future<OcheStaticBenchmarkServer> startOcheStaticBenchmarkServer({
  InternetAddress? address,
  int port = 8080,
}) async {
  final server = await HttpServer.bind(
    address ?? InternetAddress.loopbackIPv4,
    port,
  );
  server.autoCompress = false;
  server.listen(_dispatch);
  return OcheStaticBenchmarkServer._(server);
}

// This control flow deliberately resembles code that a future compile-time
// route generator could emit. It is a benchmark spike, not a public router API.
void _dispatch(HttpRequest request) {
  final path = request.uri.path;

  if (request.method != 'GET') {
    if (_isKnownPath(path)) {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..headers.set(HttpHeaders.allowHeader, 'GET')
        ..contentLength = 0;
      unawaited(request.response.close());
    } else {
      _notFound(request.response);
    }
    return;
  }

  switch (path) {
    case '/plaintext':
      _writeResponse(
        request.response,
        statusCode: HttpStatus.ok,
        contentType: _plainTextType,
        body: _plaintextBody,
      );
      return;
    case '/json':
      _writeResponse(
        request.response,
        statusCode: HttpStatus.ok,
        contentType: _jsonType,
        body: _jsonBody,
      );
      return;
  }

  if (_isUserPath(path)) {
    _user(request.response, path.substring(_usersPrefix.length));
    return;
  }

  _notFound(request.response);
}

bool _isKnownPath(String path) =>
    path == '/plaintext' || path == '/json' || _isUserPath(path);

bool _isUserPath(String path) {
  if (!path.startsWith(_usersPrefix) || path.length == _usersPrefix.length) {
    return false;
  }
  return path.indexOf('/', _usersPrefix.length) == -1;
}

void _user(HttpResponse response, String rawId) {
  final id = int.tryParse(rawId);
  if (id == null) {
    _writeResponse(
      response,
      statusCode: HttpStatus.badRequest,
      contentType: _jsonType,
      body: _invalidIdBody,
    );
    return;
  }
  _writeResponse(
    response,
    statusCode: HttpStatus.ok,
    contentType: _jsonType,
    body: '{"id":$id}',
  );
}

void _notFound(HttpResponse response) {
  _writeResponse(
    response,
    statusCode: HttpStatus.notFound,
    contentType: _plainTextType,
    body: _notFoundBody,
  );
}

void _writeResponse(
  HttpResponse response, {
  required int statusCode,
  required ContentType contentType,
  required String body,
}) {
  response
    ..statusCode = statusCode
    ..headers.contentType = contentType
    ..contentLength = body.length
    ..write(body);
  unawaited(response.close());
}
