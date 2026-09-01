import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The dispatch signature emitted by the production generator.
typedef OcheDispatch = void Function(HttpRequest request);

enum OcheResponseState { uncommitted, committed, completed }

enum OcheServerState { created, starting, running, stopping, stopped }

/// Thrown when generated or internal code attempts to complete a response
/// more than once.
final class OcheResponseLifecycleViolation implements Exception {
  const OcheResponseLifecycleViolation(this.message);

  final String message;

  @override
  String toString() => 'OcheResponseLifecycleViolation: $message';
}

final Expando<OcheResponseLifecycle> _lifecycles =
    Expando<OcheResponseLifecycle>('oche-response-lifecycle');

final Uint8List _notFoundBytes = utf8.encode('Not Found');
final Uint8List _methodNotAllowedBytes = utf8.encode('Method Not Allowed');
final Uint8List _internalErrorBytes = utf8.encode(
  '{"error":"internal server error"}',
);
final Uint8List _emptyBytes = Uint8List(0);

/// Returns decoded, security-checked URI segments for generated dispatch.
///
/// Trailing and duplicate slashes are deliberately not normalized. A rejected
/// path returns `null` and therefore maps to 404.
List<String>? ochePathSegments(Uri uri) {
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

/// Internal ownership controller attached once to every accepted request.
final class OcheResponseLifecycle {
  OcheResponseLifecycle._(this.request);

  final HttpRequest request;
  OcheResponseState _state = OcheResponseState.uncommitted;
  var _completionAttempts = 0;

  OcheResponseState get state => _state;
  int get completionAttempts => _completionAttempts;
  bool get canReplace => _state == OcheResponseState.uncommitted;

  void complete(
    int statusCode,
    ContentType? contentType,
    List<int> body, {
    List<String> allow = const [],
  }) {
    _completionAttempts++;
    if (_state != OcheResponseState.uncommitted) {
      throw OcheResponseLifecycleViolation(
        'Cannot complete after response state became ${_state.name}.',
      );
    }
    final response = request.response;
    response.statusCode = statusCode;
    if (contentType != null) response.headers.contentType = contentType;
    if (allow.isNotEmpty) {
      response.headers.set(HttpHeaders.allowHeader, allow.join(', '));
    }
    response.contentLength = body.length;
    _state = OcheResponseState.committed;
    if (body.isNotEmpty) response.add(body);
    response.close().ignore();
  }

  void _completed() => _state = OcheResponseState.completed;
}

OcheResponseLifecycle lifecycleFor(HttpRequest request) {
  final lifecycle = _lifecycles[request.response];
  if (lifecycle == null) {
    throw const OcheResponseLifecycleViolation(
      'The response is not owned by an Oche runtime.',
    );
  }
  return lifecycle;
}

void writeString(HttpRequest request, String value) =>
    lifecycleFor(request)
        .complete(HttpStatus.ok, ContentType.text, utf8.encode(value));

void writeBytes(HttpRequest request, Uint8List value) =>
    lifecycleFor(request).complete(HttpStatus.ok, ContentType.binary, value);

void writeNoContent(HttpRequest request) =>
    lifecycleFor(request).complete(HttpStatus.noContent, null, _emptyBytes);

void writeNotFound(HttpRequest request) =>
    lifecycleFor(request)
        .complete(HttpStatus.notFound, ContentType.text, _notFoundBytes);

void writeMethodNotAllowed(HttpRequest request, List<String> methods) =>
    lifecycleFor(request).complete(
      HttpStatus.methodNotAllowed,
      ContentType.text,
      _methodNotAllowedBytes,
      allow: methods,
    );

void writeInvalidParameter(HttpRequest request, String name) =>
    lifecycleFor(request).complete(
      HttpStatus.badRequest,
      ContentType.json,
      utf8.encode('{"error":"$name must be an integer"}'),
    );

void writeInternalError(HttpRequest request) => lifecycleFor(request).complete(
  HttpStatus.internalServerError,
  ContentType.json,
  _internalErrorBytes,
);

void executeStringFuture(HttpRequest request, Future<String> result) {
  unawaited(_executeStringFuture(request, result));
}

Future<void> _executeStringFuture(
  HttpRequest request,
  Future<String> result,
) async {
  try {
    writeString(request, await result);
  } on Object {
    _writeAsyncFailure(request);
  }
}

void executeBytesFuture(HttpRequest request, Future<Uint8List> result) {
  unawaited(_executeBytesFuture(request, result));
}

Future<void> _executeBytesFuture(
  HttpRequest request,
  Future<Uint8List> result,
) async {
  try {
    writeBytes(request, await result);
  } on Object {
    _writeAsyncFailure(request);
  }
}

void executeVoidFuture(HttpRequest request, Future<void> result) {
  unawaited(_executeVoidFuture(request, result));
}

Future<void> _executeVoidFuture(
  HttpRequest request,
  Future<void> result,
) async {
  try {
    await result;
    writeNoContent(request);
  } on Object {
    _writeAsyncFailure(request);
  }
}

void _writeAsyncFailure(HttpRequest request) {
  final lifecycle = lifecycleFor(request);
  if (lifecycle.canReplace) writeInternalError(request);
}

/// Thin `dart:io` runtime used by an application-specific generated bootstrap.
final class OcheServerRuntime {
  OcheServerRuntime({
    required this.dispatch,
    required this.address,
    required this.port,
  });

  final OcheDispatch dispatch;
  final InternetAddress address;
  final int port;

  OcheServerState _state = OcheServerState.created;
  HttpServer? _server;
  Future<void>? _startFuture;
  var _activeRequests = 0;
  Completer<void>? _idleWaiter;
  Future<void>? _stopFuture;

  OcheServerState get state => _state;
  int? get boundPort => _server?.port;

  Future<void> start() {
    if (_state != OcheServerState.created) {
      return Future<void>.error(
        StateError('The Oche runtime can only be started once.'),
      );
    }
    _state = OcheServerState.starting;
    final future = _start();
    _startFuture = future;
    return future;
  }

  Future<void> _start() async {
    try {
      final server = await HttpServer.bind(address, port);
      server.autoCompress = false;
      _server = server;
      _state = OcheServerState.running;
      server.listen(_handleRequest);
    } on Object {
      _state = OcheServerState.stopped;
      rethrow;
    }
  }

  Future<void> stop({Duration timeout = const Duration(seconds: 30)}) {
    if (timeout.isNegative) {
      return Future<void>.error(
        ArgumentError.value(timeout, 'timeout', 'Must not be negative.'),
      );
    }
    return _stopFuture ??= _stop(timeout);
  }

  Future<void> _stop(Duration timeout) async {
    if (_state == OcheServerState.created) {
      _state = OcheServerState.stopped;
      return;
    }
    if (_state == OcheServerState.starting) {
      try {
        await _startFuture;
      } on Object {
        return;
      }
    }
    if (_state == OcheServerState.stopped) return;
    _state = OcheServerState.stopping;
    final server = _server!;
    await server.close(force: false);
    if (_activeRequests > 0) {
      try {
        await (_idleWaiter ??= Completer<void>()).future.timeout(timeout);
      } on TimeoutException {
        await server.close(force: true);
      }
    }
    _state = OcheServerState.stopped;
  }

  void _handleRequest(HttpRequest request) {
    _activeRequests++;
    final lifecycle = OcheResponseLifecycle._(request);
    _lifecycles[request.response] = lifecycle;
    try {
      dispatch(request);
    } on Object {
      if (lifecycle.canReplace) writeInternalError(request);
    }
    unawaited(_observeCompletion(lifecycle));
  }

  Future<void> _observeCompletion(OcheResponseLifecycle lifecycle) async {
    try {
      await lifecycle.request.response.done;
    } on Object {
      // A disconnected transport cannot be replaced with another response.
    } finally {
      lifecycle._completed();
      _lifecycles[lifecycle.request.response] = null;
      _activeRequests--;
      if (_activeRequests == 0) {
        final waiter = _idleWaiter;
        _idleWaiter = null;
        if (waiter != null && !waiter.isCompleted) waiter.complete();
      }
    }
  }
}

/// Runs a generated application until SIGINT (and SIGTERM off Windows).
Future<void> runGeneratedApplication({
  required String name,
  required OcheDispatch dispatch,
  String host = '127.0.0.1',
  int port = 8080,
}) async {
  final addresses = await InternetAddress.lookup(host);
  if (addresses.isEmpty) throw StateError('Could not resolve $host.');
  final runtime = OcheServerRuntime(
    dispatch: dispatch,
    address: addresses.first,
    port: port,
  );
  await runtime.start();
  stdout.writeln('$name ready on $host:${runtime.boundPort}');

  final stopped = Completer<void>();
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  Future<void> stop(ProcessSignal signal) async {
    if (stopped.isCompleted) return;
    await runtime.stop();
    if (!stopped.isCompleted) stopped.complete();
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
