/// Raw `dart:io` HTTP baseline used by the Oche performance laboratory.
library;

import 'dart:async';
import 'dart:io';

const String _plaintextBody = 'Hello, World!';
const String _jsonBody = '{"message":"Hello, World!"}';
const String _invalidIdBody = '{"error":"id must be an integer"}';
const String _notFoundBody = 'Not Found';

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

/// A running raw HTTP benchmark server.
final class RawDartIoBenchmarkServer {
  RawDartIoBenchmarkServer._(this._server);

  final HttpServer _server;

  /// The operating-system-assigned listening port.
  int get port => _server.port;

  /// Stops accepting requests and waits for active connections to finish.
  Future<void> close({bool force = false}) => _server.close(force: force);
}

/// Starts the raw HTTP benchmark server.
Future<RawDartIoBenchmarkServer> startRawDartIoBenchmarkServer({
  InternetAddress? address,
  int port = 8080,
}) async {
  final server = await HttpServer.bind(
    address ?? InternetAddress.loopbackIPv4,
    port,
  );
  server.autoCompress = false;
  server.listen(_handleRequest);
  return RawDartIoBenchmarkServer._(server);
}

void _handleRequest(HttpRequest request) {
  if (request.method != 'GET') {
    if (_isKnownPath(request.uri)) {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..headers.set(HttpHeaders.allowHeader, 'GET')
        ..contentLength = 0;
      unawaited(request.response.close());
    } else {
      _writeResponse(
        request.response,
        statusCode: HttpStatus.notFound,
        contentType: _plainTextType,
        body: _notFoundBody,
      );
    }
    return;
  }

  switch (request.uri.path) {
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

  final segments = request.uri.pathSegments;
  if (segments.length == 2 && segments.first == 'users') {
    final id = int.tryParse(segments.last);
    if (id == null) {
      _writeResponse(
        request.response,
        statusCode: HttpStatus.badRequest,
        contentType: _jsonType,
        body: _invalidIdBody,
      );
      return;
    }
    final body = '{"id":$id}';
    _writeResponse(
      request.response,
      statusCode: HttpStatus.ok,
      contentType: _jsonType,
      body: body,
    );
    return;
  }

  _writeResponse(
    request.response,
    statusCode: HttpStatus.notFound,
    contentType: _plainTextType,
    body: _notFoundBody,
  );
}

bool _isKnownPath(Uri uri) {
  if (uri.path == '/plaintext' || uri.path == '/json') return true;
  final segments = uri.pathSegments;
  return segments.length == 2 && segments.first == 'users';
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
