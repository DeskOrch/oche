/// Internal execution contracts used only by the Oche Phase 1B experiments.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef HandlerDispatch = void Function(HttpRequest request);

/// The candidates are benchmark implementation details, not public Oche API.
enum HandlerCandidate { phase1aDirect, specialized, uniform }

/// The result categories understood by the uniform experimental adapter.
enum ExperimentalResultKind { text, jsonString, bytes, noContent, user }

/// A small structured application value used in lieu of a serialization API.
final class UserResult {
  const UserResult(this.id, this.name);

  final int id;
  final String name;
}

/// An expected application failure with deliberately minimal semantics.
final class ExpectedHandlerException implements Exception {
  const ExpectedHandlerException(this.internalMessage);

  final String internalMessage;
}

/// A lazy, non-copying request view used only to measure the wrapper trade-off.
final class ExperimentalRequestView {
  const ExperimentalRequestView(this._request);

  final HttpRequest _request;

  String get method => _request.method;
  Uri get uri => _request.uri;
  HttpHeaders get headers => _request.headers;
  List<Cookie> get cookies => _request.cookies;
}

/// Phase 1A-style intermediate response retained as a comparison baseline.
final class ExperimentalHandlerResponse {
  const ExperimentalHandlerResponse({
    required this.statusCode,
    required this.contentType,
    required this.body,
    this.allow = const [],
  });

  final int statusCode;
  final ContentType? contentType;
  final List<int> body;
  final List<String> allow;
}

const _emptyBytes = <int>[];
const _binaryPayload = <int>[79, 99, 104, 101];
const _notFoundBytes = <int>[78, 111, 116, 32, 70, 111, 117, 110, 100];
const _methodNotAllowedBytes = <int>[
  77,
  101,
  116,
  104,
  111,
  100,
  32,
  78,
  111,
  116,
  32,
  65,
  108,
  108,
  111,
  119,
  101,
  100,
];

String statusHandler() => '{"status":"ok"}';

String healthHandler() => 'OK';

int microValueHandler(int value) => value + 1;

String stringIdHandler(int id) {
  if (id == -1) {
    throw const ExpectedHandlerException('sensitive expected detail');
  }
  if (id == -2) throw StateError('sensitive unexpected detail');
  return '{"id":$id}';
}

Future<String> immediateAsyncHandler(int id) async => '{"id":$id}';

Future<String> boundaryAsyncHandler(int id) async {
  await Future<void>.delayed(Duration.zero);
  return '{"id":$id}';
}

void voidHandler() {}

Future<void> asyncVoidHandler() async {}

List<int> bytesHandler() => _binaryPayload;

UserResult userResultHandler(int id) => UserResult(id, 'user-$id');

Future<UserResult> asyncUserResultHandler(int id) async =>
    UserResult(id, 'user-$id');

String twoIntHandler(int userId, int orderId) =>
    '{"userId":$userId,"orderId":$orderId}';

String stringAndIntHandler(String sku, int id) =>
    '{"sku":${jsonEncode(sku)},"id":$id}';

String rawRequestHandler(HttpRequest request) {
  if (request.method.isEmpty || request.uri.path.isEmpty) {
    throw StateError('unreachable invalid request');
  }
  return '{"request":true}';
}

String requestViewHandler(ExperimentalRequestView request) {
  if (request.method.isEmpty || request.uri.path.isEmpty) {
    throw StateError('unreachable invalid request view');
  }
  return '{"request":true}';
}

String errorHandler(String kind) {
  if (kind == 'expected') {
    throw const ExpectedHandlerException('sensitive expected detail');
  }
  if (kind == 'unexpected') {
    throw StateError('sensitive unexpected detail');
  }
  return '{"error":false}';
}

String syntheticHandler(int routeId, [int? first, int? second]) =>
    '{"route":$routeId,"first":${first ?? -1},'
    '"second":${second ?? -1}}';

final handlerBenchmarkController = HandlerBenchmarkController();

final class HandlerBenchmarkController {
  UserResult findById(int id) => UserResult(id, 'instance-$id');

  Future<UserResult> findByIdAsync(int id) async =>
      UserResult(id, 'instance-$id');

  int microValue(int value) => value + 1;
}

List<int> serializeUserResult(UserResult value) =>
    utf8.encode('{"id":${value.id},"name":${jsonEncode(value.name)}}');

List<String>? handlerPathSegments(Uri uri) {
  final path = uri.path;
  if (path != '/' && path.endsWith('/')) return null;
  if (path.contains('//')) return null;
  final segments = uri.pathSegments;
  for (final segment in segments) {
    if (segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.contains('/') ||
        segment.contains(r'\') ||
        segment.contains('\u0000')) {
      return null;
    }
  }
  return segments;
}

/// Hand-written direct `dart:io` lower bound for the ten semantic templates.
void rawHandlerDispatch(HttpRequest request) {
  final segments = handlerPathSegments(request.uri);
  if (segments == null) {
    writeNotFound(request);
    return;
  }
  if (segments.length == 1) {
    if (segments[0] == 'health') {
      if (request.method == 'GET') {
        writeTextResult(request, healthHandler());
      } else {
        writeMethodNotAllowed(request, const ['GET']);
      }
      return;
    }
    if (segments[0] == 'status') {
      if (request.method == 'GET') {
        writeJsonStringResult(request, statusHandler());
      } else {
        writeMethodNotAllowed(request, const ['GET']);
      }
      return;
    }
    if (segments[0] == 'payload') {
      if (request.method == 'GET') {
        writeBytesResult(request, bytesHandler());
      } else if (request.method == 'DELETE') {
        voidHandler();
        writeNoContentResult(request);
      } else if (request.method == 'POST') {
        executeSpecializedVoidFuture(request, asyncVoidHandler());
      } else {
        writeMethodNotAllowed(request, const ['GET', 'POST', 'DELETE']);
      }
      return;
    }
  }
  if (segments.length == 2) {
    if (segments[0] == 'users') {
      final id = int.tryParse(segments[1]);
      if (id == null) {
        writeInvalidParameter(request, 'id');
        return;
      }
      if (request.method == 'GET') {
        writeJsonStringResult(request, stringIdHandler(id));
      } else if (request.method == 'POST') {
        writeUserResult(request, userResultHandler(id));
      } else if (request.method == 'PUT') {
        executeSpecializedUserFuture(request, asyncUserResultHandler(id));
      } else {
        writeMethodNotAllowed(request, const ['GET', 'POST', 'PUT']);
      }
      return;
    }
    if (segments[0] == 'instance') {
      final id = int.tryParse(segments[1]);
      if (id == null) {
        writeInvalidParameter(request, 'id');
        return;
      }
      if (request.method == 'GET') {
        writeUserResult(request, handlerBenchmarkController.findById(id));
      } else if (request.method == 'POST') {
        executeSpecializedUserFuture(
          request,
          handlerBenchmarkController.findByIdAsync(id),
        );
      } else {
        writeMethodNotAllowed(request, const ['GET', 'POST']);
      }
      return;
    }
    if (segments[0] == 'request') {
      if (request.method != 'GET') {
        writeMethodNotAllowed(request, const ['GET']);
      } else if (segments[1] == 'raw') {
        writeJsonStringResult(request, rawRequestHandler(request));
      } else if (segments[1] == 'view') {
        writeJsonStringResult(
          request,
          requestViewHandler(ExperimentalRequestView(request)),
        );
      } else {
        writeNotFound(request);
      }
      return;
    }
    if (segments[0] == 'errors') {
      if (request.method == 'GET') {
        writeJsonStringResult(request, errorHandler(segments[1]));
      } else {
        writeMethodNotAllowed(request, const ['GET']);
      }
      return;
    }
  }
  if (segments.length == 3 && segments[0] == 'async') {
    if (request.method != 'GET') {
      writeMethodNotAllowed(request, const ['GET']);
      return;
    }
    final id = int.tryParse(segments[2]);
    if (id == null) {
      writeInvalidParameter(request, 'id');
      return;
    }
    if (segments[1] == 'immediate') {
      executeSpecializedStringFuture(request, immediateAsyncHandler(id));
    } else if (segments[1] == 'boundary') {
      executeSpecializedStringFuture(request, boundaryAsyncHandler(id));
    } else {
      writeNotFound(request);
    }
    return;
  }
  if (segments.length == 4 &&
      segments[0] == 'orders' &&
      segments[2] == 'items') {
    if (request.method != 'GET') {
      writeMethodNotAllowed(request, const ['GET']);
      return;
    }
    final userId = int.tryParse(segments[1]);
    if (userId == null) {
      writeInvalidParameter(request, 'userId');
      return;
    }
    final orderId = int.tryParse(segments[3]);
    if (orderId == null) {
      writeInvalidParameter(request, 'orderId');
      return;
    }
    writeJsonStringResult(request, twoIntHandler(userId, orderId));
    return;
  }
  if (segments.length == 4 &&
      segments[0] == 'catalog' &&
      segments[2] == 'items') {
    if (request.method != 'GET') {
      writeMethodNotAllowed(request, const ['GET']);
      return;
    }
    final id = int.tryParse(segments[3]);
    if (id == null) {
      writeInvalidParameter(request, 'id');
      return;
    }
    writeJsonStringResult(request, stringAndIntHandler(segments[1], id));
    return;
  }
  writeNotFound(request);
}

void writeTextResult(HttpRequest request, String value) => _writeResponse(
  request.response,
  HttpStatus.ok,
  ContentType.text,
  utf8.encode(value),
);

void writeJsonStringResult(HttpRequest request, String value) => _writeResponse(
  request.response,
  HttpStatus.ok,
  ContentType.json,
  utf8.encode(value),
);

void writeBytesResult(HttpRequest request, List<int> value) =>
    _writeResponse(request.response, HttpStatus.ok, ContentType.binary, value);

void writeUserResult(HttpRequest request, UserResult value) => _writeResponse(
  request.response,
  HttpStatus.ok,
  ContentType.json,
  serializeUserResult(value),
);

void writeNoContentResult(HttpRequest request) =>
    _writeResponse(request.response, HttpStatus.noContent, null, _emptyBytes);

void writeNotFound(HttpRequest request) => _writeResponse(
  request.response,
  HttpStatus.notFound,
  ContentType.text,
  _notFoundBytes,
);

void writeInvalidParameter(HttpRequest request, String name) => _writeResponse(
  request.response,
  HttpStatus.badRequest,
  ContentType.json,
  utf8.encode('{"error":"$name must be an integer"}'),
);

void writeMethodNotAllowed(HttpRequest request, List<String> methods) {
  request.response.headers.set(HttpHeaders.allowHeader, methods.join(', '));
  _writeResponse(
    request.response,
    HttpStatus.methodNotAllowed,
    ContentType.text,
    _methodNotAllowedBytes,
  );
}

void _writeExpectedError(HttpRequest request) => _writeResponse(
  request.response,
  HttpStatus.conflict,
  ContentType.json,
  utf8.encode('{"error":"expected failure"}'),
);

/// Exposes the accepted error mapping only inside the benchmark package.
void writeExpectedHandlerError(HttpRequest request) =>
    _writeExpectedError(request);

void _writeUnexpectedError(HttpRequest request) => _writeResponse(
  request.response,
  HttpStatus.internalServerError,
  ContentType.json,
  utf8.encode('{"error":"internal server error"}'),
);

/// Exposes the accepted error mapping only inside the benchmark package.
void writeUnexpectedHandlerError(HttpRequest request) =>
    _writeUnexpectedError(request);

void _writeResponse(
  HttpResponse response,
  int statusCode,
  ContentType? contentType,
  List<int> body,
) {
  response.statusCode = statusCode;
  if (contentType != null) response.headers.contentType = contentType;
  response.contentLength = body.length;
  if (body.isNotEmpty) response.add(body);
  unawaited(response.close());
}

ExperimentalHandlerResponse phase1aTextResponse(String value) =>
    ExperimentalHandlerResponse(
      statusCode: HttpStatus.ok,
      contentType: ContentType.text,
      body: utf8.encode(value),
    );

ExperimentalHandlerResponse phase1aJsonResponse(String value) =>
    ExperimentalHandlerResponse(
      statusCode: HttpStatus.ok,
      contentType: ContentType.json,
      body: utf8.encode(value),
    );

ExperimentalHandlerResponse phase1aBytesResponse(List<int> value) =>
    ExperimentalHandlerResponse(
      statusCode: HttpStatus.ok,
      contentType: ContentType.binary,
      body: value,
    );

ExperimentalHandlerResponse phase1aUserResponse(UserResult value) =>
    ExperimentalHandlerResponse(
      statusCode: HttpStatus.ok,
      contentType: ContentType.json,
      body: serializeUserResult(value),
    );

const phase1aNoContentResponse = ExperimentalHandlerResponse(
  statusCode: HttpStatus.noContent,
  contentType: null,
  body: _emptyBytes,
);

void writePhase1aResponse(
  HttpRequest request,
  ExperimentalHandlerResponse result,
) {
  if (result.allow.isNotEmpty) {
    request.response.headers.set(
      HttpHeaders.allowHeader,
      result.allow.join(', '),
    );
  }
  _writeResponse(
    request.response,
    result.statusCode,
    result.contentType,
    result.body,
  );
}

void executeSpecializedStringFuture(
  HttpRequest request,
  Future<String> result, {
  bool json = true,
}) {
  unawaited(_executeSpecializedStringFuture(request, result, json: json));
}

Future<void> _executeSpecializedStringFuture(
  HttpRequest request,
  Future<String> result, {
  required bool json,
}) async {
  try {
    final value = await result;
    if (json) {
      writeJsonStringResult(request, value);
    } else {
      writeTextResult(request, value);
    }
  } on ExpectedHandlerException {
    _writeExpectedError(request);
  } on Object {
    _writeUnexpectedError(request);
  }
}

void executeSpecializedUserFuture(
  HttpRequest request,
  Future<UserResult> result,
) {
  unawaited(_executeSpecializedUserFuture(request, result));
}

Future<void> _executeSpecializedUserFuture(
  HttpRequest request,
  Future<UserResult> result,
) async {
  try {
    writeUserResult(request, await result);
  } on ExpectedHandlerException {
    _writeExpectedError(request);
  } on Object {
    _writeUnexpectedError(request);
  }
}

void executeSpecializedVoidFuture(HttpRequest request, Future<void> result) {
  unawaited(_executeSpecializedVoidFuture(request, result));
}

Future<void> _executeSpecializedVoidFuture(
  HttpRequest request,
  Future<void> result,
) async {
  try {
    await result;
    writeNoContentResult(request);
  } on ExpectedHandlerException {
    _writeExpectedError(request);
  } on Object {
    _writeUnexpectedError(request);
  }
}

void executePhase1aStringFuture(HttpRequest request, Future<String> result) {
  unawaited(_executePhase1aStringFuture(request, result));
}

Future<void> _executePhase1aStringFuture(
  HttpRequest request,
  Future<String> result,
) async {
  try {
    writePhase1aResponse(request, phase1aJsonResponse(await result));
  } on ExpectedHandlerException {
    _writeExpectedError(request);
  } on Object {
    _writeUnexpectedError(request);
  }
}

void executePhase1aUserFuture(HttpRequest request, Future<UserResult> result) {
  unawaited(_executePhase1aUserFuture(request, result));
}

Future<void> _executePhase1aUserFuture(
  HttpRequest request,
  Future<UserResult> result,
) async {
  try {
    writePhase1aResponse(request, phase1aUserResponse(await result));
  } on ExpectedHandlerException {
    _writeExpectedError(request);
  } on Object {
    _writeUnexpectedError(request);
  }
}

void executePhase1aVoidFuture(HttpRequest request, Future<void> result) {
  unawaited(_executePhase1aVoidFuture(request, result));
}

Future<void> _executePhase1aVoidFuture(
  HttpRequest request,
  Future<void> result,
) async {
  try {
    await result;
    writePhase1aResponse(request, phase1aNoContentResponse);
  } on ExpectedHandlerException {
    _writeExpectedError(request);
  } on Object {
    _writeUnexpectedError(request);
  }
}

void executeUniformResult(
  HttpRequest request,
  FutureOr<Object?> result,
  ExperimentalResultKind kind,
) {
  if (result is Future<Object?>) {
    unawaited(_executeUniformFuture(request, result, kind));
    return;
  }
  writePhase1aResponse(request, normalizeUniformResult(result, kind));
}

void executeUniformVoidFuture(HttpRequest request, Future<void> result) {
  unawaited(_executeUniformVoidFuture(request, result));
}

Future<void> _executeUniformVoidFuture(
  HttpRequest request,
  Future<void> result,
) async {
  try {
    await result;
    writePhase1aResponse(request, phase1aNoContentResponse);
  } on ExpectedHandlerException {
    _writeExpectedError(request);
  } on Object {
    _writeUnexpectedError(request);
  }
}

Future<void> _executeUniformFuture(
  HttpRequest request,
  Future<Object?> result,
  ExperimentalResultKind kind,
) async {
  try {
    writePhase1aResponse(request, normalizeUniformResult(await result, kind));
  } on ExpectedHandlerException {
    _writeExpectedError(request);
  } on Object {
    _writeUnexpectedError(request);
  }
}

ExperimentalHandlerResponse normalizeUniformResult(
  Object? result,
  ExperimentalResultKind kind,
) => switch (kind) {
  ExperimentalResultKind.text => phase1aTextResponse(result! as String),
  ExperimentalResultKind.jsonString => phase1aJsonResponse(result! as String),
  ExperimentalResultKind.bytes => phase1aBytesResponse(result! as List<int>),
  ExperimentalResultKind.noContent => phase1aNoContentResponse,
  ExperimentalResultKind.user => phase1aUserResponse(result! as UserResult),
};

/// One shared boundary handles synchronous binding/handler failures.
void executeHandlerDispatch(HandlerDispatch dispatch, HttpRequest request) {
  try {
    dispatch(request);
  } on ExpectedHandlerException {
    _writeExpectedError(request);
  } on Object {
    _writeUnexpectedError(request);
  }
}

Future<HttpServer> startHandlerBenchmarkServer(
  HandlerDispatch dispatch, {
  InternetAddress? address,
  int port = 8080,
}) async {
  final server = await HttpServer.bind(
    address ?? InternetAddress.loopbackIPv4,
    port,
  );
  server.autoCompress = false;
  server.listen((request) => executeHandlerDispatch(dispatch, request));
  return server;
}

Future<void> runHandlerBenchmarkServer(
  List<String> arguments, {
  required String name,
  required HandlerDispatch dispatch,
}) async {
  final options = _ServerOptions.parse(arguments);
  final addresses = await InternetAddress.lookup(options.host);
  if (addresses.isEmpty) throw StateError('Could not resolve ${options.host}.');
  final server = await startHandlerBenchmarkServer(
    dispatch,
    address: addresses.first,
    port: options.port,
  );
  stdout.writeln('$name ready on ${options.host}:${server.port}');

  final stopped = Completer<void>();
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  Future<void> stop(ProcessSignal signal) async {
    if (stopped.isCompleted) return;
    await server.close();
    stopped.complete();
  }

  subscriptions.add(ProcessSignal.sigint.watch().listen(stop));
  if (!Platform.isWindows) {
    subscriptions.add(ProcessSignal.sigterm.watch().listen(stop));
  }
  await stopped.future;
  for (final subscription in subscriptions) {
    await subscription.cancel();
  }
}

final class _ServerOptions {
  const _ServerOptions({required this.host, required this.port});

  final String host;
  final int port;

  static _ServerOptions parse(List<String> arguments) {
    var host = '127.0.0.1';
    var port = 8080;
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--host' && index + 1 < arguments.length) {
        host = arguments[++index];
      } else if (argument.startsWith('--host=')) {
        host = argument.substring('--host='.length);
      } else if (argument == '--port' && index + 1 < arguments.length) {
        port = int.parse(arguments[++index]);
      } else if (argument.startsWith('--port=')) {
        port = int.parse(argument.substring('--port='.length));
      } else {
        throw FormatException('Unknown or incomplete argument: $argument');
      }
    }
    if (port < 0 || port > 65535) {
      throw RangeError.range(port, 0, 65535, 'port');
    }
    return _ServerOptions(host: host, port: port);
  }
}
