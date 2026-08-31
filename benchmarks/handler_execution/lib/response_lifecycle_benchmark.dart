/// Internal response-ownership and server-lifecycle contracts for Phase 1E.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:handler_execution_benchmark/handler_execution_benchmark.dart';
import 'package:handler_execution_benchmark/middleware_execution_benchmark.dart';

enum InternalResponseState { uncommitted, committed, completed }

enum InternalResponseOwnership { framework, stream, detachedSocket }

enum InternalServerState { created, starting, running, stopping, stopped }

/// Optional allocation-free event boundary for future observability adapters.
///
/// The hot path creates no event object. Production logging, tracing, and
/// metrics APIs remain explicitly out of scope.
abstract interface class InternalLifecycleHooks {
  void requestStarted(HttpRequest request);

  void responseCommitted(HttpRequest request);

  void requestCompleted(HttpRequest request);

  void requestFailed(HttpRequest request, Object error, StackTrace stackTrace);

  void clientDisconnected(HttpRequest request, Object error);

  void shutdownStarted();

  void shutdownCompleted();

  void forcedShutdown();
}

final class ResponseLifecycleViolation implements Exception {
  const ResponseLifecycleViolation(this.message);

  final String message;

  @override
  String toString() => 'ResponseLifecycleViolation: $message';
}

final Expando<InternalResponseLifecycle> _responseLifecycles =
    Expando<InternalResponseLifecycle>('oche-response-lifecycle');

/// Returns the Phase 1E controller attached by [ExperimentalServerRuntime].
InternalResponseLifecycle responseLifecycleFor(HttpRequest request) {
  final lifecycle = _responseLifecycles[request.response];
  if (lifecycle == null) {
    throw const ResponseLifecycleViolation(
      'The response is not owned by the Phase 1E runtime.',
    );
  }
  return lifecycle;
}

/// Cheap per-request ownership metadata used only by the Phase 1E candidate.
final class InternalResponseLifecycle {
  InternalResponseLifecycle._(this.request, this._hooks);

  final HttpRequest request;
  final InternalLifecycleHooks? _hooks;

  InternalResponseState _state = InternalResponseState.uncommitted;
  InternalResponseOwnership _ownership = InternalResponseOwnership.framework;
  Object? _failureAfterCommit;
  StackTrace? _failureAfterCommitStackTrace;
  int _completionAttempts = 0;
  bool _closeStarted = false;
  bool _failureObserved = false;

  HttpResponse get response => request.response;
  InternalResponseState get state => _state;
  InternalResponseOwnership get ownership => _ownership;
  Object? get failureAfterCommit => _failureAfterCommit;
  StackTrace? get failureAfterCommitStackTrace => _failureAfterCommitStackTrace;
  int get completionAttempts => _completionAttempts;

  bool get canReplace =>
      _state == InternalResponseState.uncommitted &&
      _ownership != InternalResponseOwnership.detachedSocket;

  bool get headersMutable => _state == InternalResponseState.uncommitted;

  void complete(
    int statusCode,
    ContentType? contentType,
    List<int> body, {
    List<String> allow = const [],
  }) {
    _completionAttempts++;
    _requireFrameworkOwnership();
    _requireUncommitted('complete');
    final response = this.response;
    response.statusCode = statusCode;
    if (contentType != null) response.headers.contentType = contentType;
    if (allow.isNotEmpty) {
      response.headers.set(HttpHeaders.allowHeader, allow.join(', '));
    }
    response.contentLength = body.length;
    _markCommitted();
    _closeStarted = true;
    try {
      if (body.isNotEmpty) response.add(body);
      response.close().ignore();
    } on Object catch (error, stackTrace) {
      recordFailureAfterCommit(error, stackTrace);
      rethrow;
    }
  }

  InternalStreamingResponse transferToStream({
    int statusCode = HttpStatus.ok,
    ContentType? contentType,
  }) {
    _requireFrameworkOwnership();
    _requireUncommitted('transfer streaming ownership');
    final response = this.response;
    response.statusCode = statusCode;
    if (contentType != null) response.headers.contentType = contentType;
    response.contentLength = -1;
    _ownership = InternalResponseOwnership.stream;
    return InternalStreamingResponse._(this);
  }

  Future<Socket> detachSocket({bool writeHeaders = true}) async {
    _requireFrameworkOwnership();
    _requireUncommitted('detach the socket');
    _ownership = InternalResponseOwnership.detachedSocket;
    _markCommitted();
    try {
      return await response.detachSocket(writeHeaders: writeHeaders);
    } on Object catch (error, stackTrace) {
      recordFailureAfterCommit(error, stackTrace);
      rethrow;
    }
  }

  void recordFailureAfterCommit(Object error, StackTrace stackTrace) {
    if (_failureObserved) return;
    _failureObserved = true;
    _failureAfterCommit = error;
    _failureAfterCommitStackTrace = stackTrace;
    _hooks?.requestFailed(request, error, stackTrace);
  }

  void _recordFailureBeforeCommit(Object error, StackTrace stackTrace) {
    if (_failureObserved) return;
    _failureObserved = true;
    _hooks?.requestFailed(request, error, stackTrace);
  }

  void _markCommitted() {
    if (_state != InternalResponseState.uncommitted) return;
    _state = InternalResponseState.committed;
    _hooks?.responseCommitted(request);
  }

  void _transportCompleted() {
    _state = InternalResponseState.completed;
  }

  void _transportFailed(Object error, StackTrace stackTrace) {
    if (_state == InternalResponseState.committed) {
      recordFailureAfterCommit(error, stackTrace);
    } else {
      _recordFailureBeforeCommit(error, stackTrace);
    }
    _state = InternalResponseState.completed;
    _hooks?.clientDisconnected(request, error);
  }

  void _requireFrameworkOwnership() {
    if (_ownership != InternalResponseOwnership.framework) {
      throw ResponseLifecycleViolation(
        'The response is owned by ${_ownership.name}, not the framework.',
      );
    }
  }

  void _requireUncommitted(String operation) {
    if (_state != InternalResponseState.uncommitted) {
      throw ResponseLifecycleViolation(
        'Cannot $operation after response state became ${_state.name}.',
      );
    }
  }
}

/// Advanced streaming owner. Normal handlers never receive this object.
final class InternalStreamingResponse {
  const InternalStreamingResponse._(this._lifecycle);

  final InternalResponseLifecycle _lifecycle;

  InternalResponseState get state => _lifecycle.state;
  HttpResponse get _response => _lifecycle.response;

  void add(List<int> chunk) {
    _requireStreamingOwnership();
    if (_lifecycle.state == InternalResponseState.completed) {
      throw const ResponseLifecycleViolation(
        'Cannot add a chunk after streaming completed.',
      );
    }
    if (chunk.isEmpty) return;
    _lifecycle._markCommitted();
    try {
      _response.add(chunk);
    } on Object catch (error, stackTrace) {
      _lifecycle.recordFailureAfterCommit(error, stackTrace);
      rethrow;
    }
  }

  void write(String chunk) => add(utf8.encode(chunk));

  Future<void> flush() async {
    _requireStreamingOwnership();
    if (_lifecycle.state == InternalResponseState.completed) {
      throw const ResponseLifecycleViolation(
        'Cannot flush after streaming completed.',
      );
    }
    try {
      await _response.flush();
    } on Object catch (error, stackTrace) {
      if (_lifecycle.state == InternalResponseState.committed) {
        _lifecycle.recordFailureAfterCommit(error, stackTrace);
      } else {
        _lifecycle._recordFailureBeforeCommit(error, stackTrace);
      }
      rethrow;
    }
  }

  void close() {
    _requireStreamingOwnership();
    if (_lifecycle._closeStarted ||
        _lifecycle.state == InternalResponseState.completed) {
      return;
    }
    _lifecycle._markCommitted();
    _lifecycle._closeStarted = true;
    _response.close().ignore();
  }

  void fail(Object error, StackTrace stackTrace) {
    _requireStreamingOwnership();
    if (_lifecycle.state == InternalResponseState.uncommitted) {
      _lifecycle._ownership = InternalResponseOwnership.framework;
      _lifecycle._recordFailureBeforeCommit(error, stackTrace);
      _lifecycle.complete(
        HttpStatus.internalServerError,
        ContentType.json,
        _unexpectedErrorBytes,
      );
      return;
    }
    _lifecycle.recordFailureAfterCommit(error, stackTrace);
    close();
  }

  void _requireStreamingOwnership() {
    if (_lifecycle.ownership != InternalResponseOwnership.stream) {
      throw const ResponseLifecycleViolation(
        'Streaming code no longer owns this response.',
      );
    }
  }
}

const _emptyBytes = <int>[];
final _notFoundBytes = utf8.encode('Not Found');
final _methodNotAllowedBytes = utf8.encode('Method Not Allowed');
final _expectedErrorBytes = utf8.encode('{"error":"expected failure"}');
final _unexpectedErrorBytes = utf8.encode('{"error":"internal server error"}');
final _unauthorizedBytes = utf8.encode('{"error":"unauthorized"}');

void writeLifecycleTextResult(HttpRequest request, String value) =>
    responseLifecycleFor(request)
        .complete(HttpStatus.ok, ContentType.text, utf8.encode(value));

void writeLifecycleJsonStringResult(HttpRequest request, String value) =>
    responseLifecycleFor(request)
        .complete(HttpStatus.ok, ContentType.json, utf8.encode(value));

void writeLifecycleBytesResult(HttpRequest request, List<int> value) =>
    responseLifecycleFor(request)
        .complete(HttpStatus.ok, ContentType.binary, value);

void writeLifecycleUserResult(HttpRequest request, UserResult value) =>
    responseLifecycleFor(request)
        .complete(HttpStatus.ok, ContentType.json, serializeUserResult(value));

void writeLifecycleNoContentResult(HttpRequest request) =>
    responseLifecycleFor(request)
        .complete(HttpStatus.noContent, null, _emptyBytes);

void writeLifecycleNotFound(HttpRequest request) =>
    responseLifecycleFor(request)
        .complete(HttpStatus.notFound, ContentType.text, _notFoundBytes);

void writeLifecycleInvalidParameter(HttpRequest request, String name) =>
    responseLifecycleFor(request).complete(
      HttpStatus.badRequest,
      ContentType.json,
      utf8.encode('{"error":"$name must be an integer"}'),
    );

void writeLifecycleMethodNotAllowed(
  HttpRequest request,
  List<String> methods,
) => responseLifecycleFor(request).complete(
  HttpStatus.methodNotAllowed,
  ContentType.text,
  _methodNotAllowedBytes,
  allow: methods,
);

void writeLifecycleExpectedError(HttpRequest request) =>
    responseLifecycleFor(request)
        .complete(HttpStatus.conflict, ContentType.json, _expectedErrorBytes);

void writeLifecycleUnexpectedError(HttpRequest request) =>
    responseLifecycleFor(request).complete(
      HttpStatus.internalServerError,
      ContentType.json,
      _unexpectedErrorBytes,
    );

void writeLifecycleMiddlewareUnauthorized(HttpRequest request) {
  final lifecycle = responseLifecycleFor(request);
  lifecycle.response.headers.set(
    'x-handler-invocations',
    '$middlewareHandlerInvocations',
  );
  lifecycle.complete(
    HttpStatus.unauthorized,
    ContentType.json,
    _unauthorizedBytes,
  );
}

void writeLifecycleMiddlewareOrder(
  HttpRequest request,
  String value,
  List<String> trace,
) {
  final lifecycle = responseLifecycleFor(request);
  lifecycle.response.headers.set('x-middleware-order', trace.join(','));
  lifecycle.complete(HttpStatus.ok, ContentType.json, utf8.encode(value));
}

void executeLifecycleStringFuture(
  HttpRequest request,
  Future<String> result, {
  bool json = true,
}) {
  unawaited(_executeLifecycleStringFuture(request, result, json: json));
}

Future<void> _executeLifecycleStringFuture(
  HttpRequest request,
  Future<String> result, {
  required bool json,
}) async {
  try {
    final value = await result;
    if (json) {
      writeLifecycleJsonStringResult(request, value);
    } else {
      writeLifecycleTextResult(request, value);
    }
  } on ExpectedHandlerException catch (error, stackTrace) {
    _mapLifecycleError(request, error, stackTrace, expected: true);
  } on Object catch (error, stackTrace) {
    _mapLifecycleError(request, error, stackTrace);
  }
}

void executeLifecycleVoidFuture(HttpRequest request, Future<void> result) {
  unawaited(_executeLifecycleVoidFuture(request, result));
}

void executeLifecycleUserFuture(
  HttpRequest request,
  Future<UserResult> result,
) {
  unawaited(_executeLifecycleUserFuture(request, result));
}

Future<void> _executeLifecycleUserFuture(
  HttpRequest request,
  Future<UserResult> result,
) async {
  try {
    writeLifecycleUserResult(request, await result);
  } on ExpectedHandlerException catch (error, stackTrace) {
    _mapLifecycleError(request, error, stackTrace, expected: true);
  } on Object catch (error, stackTrace) {
    _mapLifecycleError(request, error, stackTrace);
  }
}

Future<void> _executeLifecycleVoidFuture(
  HttpRequest request,
  Future<void> result,
) async {
  try {
    await result;
    writeLifecycleNoContentResult(request);
  } on ExpectedHandlerException catch (error, stackTrace) {
    _mapLifecycleError(request, error, stackTrace, expected: true);
  } on Object catch (error, stackTrace) {
    _mapLifecycleError(request, error, stackTrace);
  }
}

void executeLifecycleMiddlewareAsyncResponse(
  HttpRequest request,
  Future<String?> result, {
  List<String>? trace,
}) {
  unawaited(
    _executeLifecycleMiddlewareAsyncResponse(request, result, trace: trace),
  );
}

Future<void> _executeLifecycleMiddlewareAsyncResponse(
  HttpRequest request,
  Future<String?> result, {
  List<String>? trace,
}) async {
  try {
    final value = await result;
    if (value == null) {
      writeLifecycleMiddlewareUnauthorized(request);
    } else if (trace != null) {
      writeLifecycleMiddlewareOrder(request, value, trace);
    } else {
      writeLifecycleJsonStringResult(request, value);
    }
  } on ExpectedHandlerException catch (error, stackTrace) {
    _mapLifecycleError(request, error, stackTrace, expected: true);
  } on Object catch (error, stackTrace) {
    _mapLifecycleError(request, error, stackTrace);
  }
}

InternalStreamingResponse transferLifecycleResponseToStream(
  HttpRequest request, {
  int statusCode = HttpStatus.ok,
  ContentType? contentType,
}) =>
    responseLifecycleFor(request)
        .transferToStream(statusCode: statusCode, contentType: contentType);

void executeLifecycleStreaming(
  InternalStreamingResponse stream,
  Future<void> work,
) {
  unawaited(_executeLifecycleStreaming(stream, work));
}

Future<void> _executeLifecycleStreaming(
  InternalStreamingResponse stream,
  Future<void> work,
) async {
  try {
    await work;
    stream.close();
  } on Object catch (error, stackTrace) {
    stream.fail(error, stackTrace);
  }
}

void _executeLifecycleDispatch(HandlerDispatch dispatch, HttpRequest request) {
  try {
    dispatch(request);
  } on ExpectedHandlerException catch (error, stackTrace) {
    _mapLifecycleError(request, error, stackTrace, expected: true);
  } on Object catch (error, stackTrace) {
    _mapLifecycleError(request, error, stackTrace);
  }
}

void _mapLifecycleError(
  HttpRequest request,
  Object error,
  StackTrace stackTrace, {
  bool expected = false,
}) {
  final lifecycle = responseLifecycleFor(request);
  if (lifecycle.canReplace) {
    lifecycle._recordFailureBeforeCommit(error, stackTrace);
    if (expected) {
      writeLifecycleExpectedError(request);
    } else {
      writeLifecycleUnexpectedError(request);
    }
    return;
  }
  lifecycle.recordFailureAfterCommit(error, stackTrace);
  if (lifecycle.ownership == InternalResponseOwnership.stream) {
    InternalStreamingResponse._(lifecycle).close();
  }
}

/// Minimal internal server runtime with counter-based graceful draining.
final class ExperimentalServerRuntime {
  ExperimentalServerRuntime({
    required this.dispatch,
    this.address,
    this.port = 8080,
    this.hooks,
  });

  final HandlerDispatch dispatch;
  final InternetAddress? address;
  final int port;
  final InternalLifecycleHooks? hooks;

  InternalServerState _state = InternalServerState.created;
  HttpServer? _server;
  Future<void>? _startFuture;
  int _activeRequests = 0;
  Completer<void>? _idleWaiter;
  Future<void>? _stopFuture;
  bool _forcedShutdown = false;

  InternalServerState get state => _state;
  int get activeRequests => _activeRequests;
  int? get boundPort => _server?.port;
  bool get forcedShutdown => _forcedShutdown;

  Future<void> start() {
    if (_state != InternalServerState.created) {
      return Future<void>.error(
        StateError('The server runtime can only be started once.'),
      );
    }
    if (port < 0 || port > 65535) {
      _state = InternalServerState.stopped;
      return Future<void>.error(RangeError.range(port, 0, 65535, 'port'));
    }
    _state = InternalServerState.starting;
    final future = _start();
    _startFuture = future;
    return future;
  }

  Future<void> _start() async {
    try {
      final server = await HttpServer.bind(
        address ?? InternetAddress.loopbackIPv4,
        port,
      );
      server.autoCompress = false;
      _server = server;
      _state = InternalServerState.running;
      server.listen(_handleRequest);
    } on Object {
      _state = InternalServerState.stopped;
      rethrow;
    }
  }

  Future<void> stop({Duration timeout = const Duration(seconds: 30)}) {
    if (timeout.isNegative) {
      return Future<void>.error(
        ArgumentError.value(timeout, 'timeout', 'Must not be negative.'),
      );
    }
    final existing = _stopFuture;
    if (existing != null) return existing;
    final future = _stop(timeout);
    _stopFuture = future;
    return future;
  }

  Future<void> _stop(Duration timeout) async {
    if (_state == InternalServerState.created) {
      _state = InternalServerState.stopped;
      return;
    }
    if (_state == InternalServerState.starting) {
      try {
        await _startFuture;
      } on Object {
        return;
      }
    }
    if (_state == InternalServerState.stopped) return;
    _state = InternalServerState.stopping;
    hooks?.shutdownStarted();
    final server = _server!;
    await server.close(force: false);
    if (_activeRequests > 0 && !await _waitForIdle(timeout)) {
      _forcedShutdown = true;
      hooks?.forcedShutdown();
      await server.close(force: true);
      if (_activeRequests != 0) {
        _activeRequests = 0;
        final waiter = _idleWaiter;
        _idleWaiter = null;
        if (waiter != null && !waiter.isCompleted) waiter.complete();
      }
    }
    _state = InternalServerState.stopped;
    hooks?.shutdownCompleted();
  }

  Future<bool> _waitForIdle(Duration timeout) async {
    if (_activeRequests == 0) return true;
    final waiter = _idleWaiter ??= Completer<void>();
    try {
      await waiter.future.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  void _handleRequest(HttpRequest request) {
    _activeRequests++;
    final lifecycle = InternalResponseLifecycle._(request, hooks);
    _responseLifecycles[request.response] = lifecycle;
    hooks?.requestStarted(request);
    _executeLifecycleDispatch(dispatch, request);
    unawaited(_observeCompletion(lifecycle));
  }

  Future<void> _observeCompletion(InternalResponseLifecycle lifecycle) async {
    try {
      await lifecycle.response.done;
      lifecycle._transportCompleted();
    } on Object catch (error, stackTrace) {
      lifecycle._transportFailed(error, stackTrace);
    } finally {
      hooks?.requestCompleted(lifecycle.request);
      _responseLifecycles[lifecycle.response] = null;
      if (_activeRequests > 0) _activeRequests--;
      if (_activeRequests == 0) {
        final waiter = _idleWaiter;
        _idleWaiter = null;
        if (waiter != null && !waiter.isCompleted) waiter.complete();
      }
    }
  }
}

Future<void> runResponseLifecycleBenchmarkServer(
  List<String> arguments, {
  required String name,
  required HandlerDispatch dispatch,
}) async {
  final options = _ResponseServerOptions.parse(arguments);
  final addresses = await InternetAddress.lookup(options.host);
  if (addresses.isEmpty) throw StateError('Could not resolve ${options.host}.');
  final runtime = ExperimentalServerRuntime(
    dispatch: dispatch,
    address: addresses.first,
    port: options.port,
  );
  await runtime.start();
  stdout.writeln('$name ready on ${options.host}:${runtime.boundPort}');

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

final class _ResponseServerOptions {
  const _ResponseServerOptions({required this.host, required this.port});

  final String host;
  final int port;

  static _ResponseServerOptions parse(List<String> arguments) {
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
    return _ResponseServerOptions(host: host, port: port);
  }
}
