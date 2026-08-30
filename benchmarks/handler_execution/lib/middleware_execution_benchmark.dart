/// Internal middleware execution contracts for the Oche Phase 1C experiment.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:handler_execution_benchmark/handler_execution_benchmark.dart';

const middlewareDepths = <int>[0, 1, 3, 5, 10];

enum MiddlewareCandidate { phase1b, generated, runtime }

enum MiddlewareProfile {
  syncContinue,
  asyncHandlerSyncMiddleware,
  asyncMiddleware,
  mixed,
  shortSync,
  shortAsync,
  order,
  errorBefore,
  errorHandler,
  errorAfter,
  errorAsync,
  stateNone,
  stateLazy,
  stateTyped,
  instance,
}

enum MiddlewareDecision { proceed, unauthorized }

int middlewareObservation = 0;
int middlewareHandlerInvocations = 0;
int middlewareBeforeInvocations = 0;
int middlewareAfterInvocations = 0;

void resetMiddlewareObservations() {
  middlewareObservation = 0;
  middlewareHandlerInvocations = 0;
  middlewareBeforeInvocations = 0;
  middlewareAfterInvocations = 0;
}

String middlewareSyncHandler(int id) {
  middlewareHandlerInvocations++;
  return '{"id":$id}';
}

Future<String> middlewareImmediateAsyncHandler(int id) async {
  middlewareHandlerInvocations++;
  return '{"id":$id}';
}

Future<String> middlewareBoundaryAsyncHandler(int id) async {
  await Future<void>.delayed(Duration.zero);
  middlewareHandlerInvocations++;
  return '{"id":$id}';
}

String middlewareTwoIntHandler(int userId, int orderId) {
  middlewareHandlerInvocations++;
  return '{"userId":$userId,"orderId":$orderId}';
}

String middlewareSyntheticHandler(int routeId, [int? first, int? second]) {
  middlewareHandlerInvocations++;
  return '{"route":$routeId,"first":${first ?? -1},'
      '"second":${second ?? -1}}';
}

String middlewareFailingHandler(int id) {
  middlewareHandlerInvocations++;
  if (id == -1) {
    throw const ExpectedHandlerException('sensitive expected middleware');
  }
  throw StateError('sensitive handler middleware detail');
}

final middlewareBenchmarkInstance = MiddlewareBenchmarkInstance();

final class MiddlewareBenchmarkInstance {
  MiddlewareDecision before(
    HttpRequest request,
    int index,
    MiddlewareProfile profile, [
    List<String>? trace,
  ]) => middlewareBefore(request, index, profile, trace);

  void after(
    HttpRequest request,
    int index,
    MiddlewareProfile profile, [
    List<String>? trace,
  ]) => middlewareAfter(request, index, profile, trace);
}

MiddlewareDecision middlewareBefore(
  HttpRequest request,
  int index,
  MiddlewareProfile profile, [
  List<String>? trace,
]) {
  middlewareBeforeInvocations++;
  middlewareObservation =
      (middlewareObservation +
          request.method.length +
          request.uri.path.length +
          index +
          1) &
      0x7fffffff;
  trace?.add('M$index.before');
  if (profile == MiddlewareProfile.errorBefore && index == 0) {
    throw StateError('sensitive before middleware detail');
  }
  if (profile == MiddlewareProfile.shortSync && index == _shortIndex()) {
    return MiddlewareDecision.unauthorized;
  }
  return MiddlewareDecision.proceed;
}

void middlewareAfter(
  HttpRequest request,
  int index,
  MiddlewareProfile profile, [
  List<String>? trace,
]) {
  middlewareAfterInvocations++;
  middlewareObservation =
      (middlewareObservation + request.uri.path.length + index + 17) &
      0x7fffffff;
  trace?.add('M$index.after');
  if (profile == MiddlewareProfile.errorAfter && index == 0) {
    throw StateError('sensitive after middleware detail');
  }
}

MiddlewareDecision generatedMiddlewareBefore(
  HttpRequest request,
  int index,
  MiddlewareProfile profile, [
  List<String>? trace,
]) => profile == MiddlewareProfile.instance && index == 0
    ? middlewareBenchmarkInstance.before(request, index, profile, trace)
    : middlewareBefore(request, index, profile, trace);

void generatedMiddlewareAfter(
  HttpRequest request,
  int index,
  MiddlewareProfile profile, [
  List<String>? trace,
]) {
  if (profile == MiddlewareProfile.instance && index == 0) {
    middlewareBenchmarkInstance.after(request, index, profile, trace);
  } else {
    middlewareAfter(request, index, profile, trace);
  }
}

Future<MiddlewareDecision> middlewareBeforeAsync(
  HttpRequest request,
  int index,
  MiddlewareProfile profile, [
  List<String>? trace,
]) async {
  if (profile == MiddlewareProfile.mixed ||
      profile == MiddlewareProfile.errorAsync) {
    await Future<void>.delayed(Duration.zero);
  }
  middlewareBeforeInvocations++;
  middlewareObservation =
      (middlewareObservation +
          request.method.length +
          request.uri.path.length +
          index +
          31) &
      0x7fffffff;
  trace?.add('M$index.before');
  if (profile == MiddlewareProfile.errorAsync && index == 0) {
    throw StateError('sensitive async middleware detail');
  }
  if (profile == MiddlewareProfile.shortAsync && index == _shortIndex()) {
    return MiddlewareDecision.unauthorized;
  }
  return MiddlewareDecision.proceed;
}

Future<void> middlewareAfterAsync(
  HttpRequest request,
  int index,
  MiddlewareProfile profile, [
  List<String>? trace,
]) async {
  if (profile == MiddlewareProfile.mixed) {
    await Future<void>.delayed(Duration.zero);
  }
  middlewareAfterInvocations++;
  middlewareObservation =
      (middlewareObservation + request.uri.path.length + index + 47) &
      0x7fffffff;
  trace?.add('M$index.after');
}

int _shortIndex() => 0;

final class ExperimentalMiddlewareStep {
  const ExperimentalMiddlewareStep(this.index);

  final int index;
}

List<ExperimentalMiddlewareStep> buildRuntimeMiddlewareSteps(int depth) {
  if (!middlewareDepths.contains(depth)) {
    throw ArgumentError.value(depth, 'depth');
  }
  return List<ExperimentalMiddlewareStep>.unmodifiable([
    for (var index = 0; index < depth; index++)
      ExperimentalMiddlewareStep(index),
  ]);
}

typedef SyncMiddlewareHandler = String Function();
typedef AsyncMiddlewareHandler = Future<String> Function();

String? executeRuntimeSyncPipeline(
  HttpRequest request,
  List<ExperimentalMiddlewareStep> steps,
  MiddlewareProfile profile,
  SyncMiddlewareHandler handler, {
  List<String>? trace,
}) {
  var entered = 0;
  for (final step in steps) {
    final decision = profile == MiddlewareProfile.instance && step.index == 0
        ? middlewareBenchmarkInstance.before(
            request,
            step.index,
            profile,
            trace,
          )
        : middlewareBefore(request, step.index, profile, trace);
    if (decision == MiddlewareDecision.unauthorized) {
      _unwindRuntimeSync(request, steps, entered, profile, trace);
      return null;
    }
    entered++;
  }
  trace?.add('handler');
  final result = handler();
  _unwindRuntimeSync(request, steps, entered, profile, trace);
  return result;
}

void _unwindRuntimeSync(
  HttpRequest request,
  List<ExperimentalMiddlewareStep> steps,
  int entered,
  MiddlewareProfile profile,
  List<String>? trace,
) {
  for (var index = entered - 1; index >= 0; index--) {
    final step = steps[index];
    if (profile == MiddlewareProfile.instance && step.index == 0) {
      middlewareBenchmarkInstance.after(request, step.index, profile, trace);
    } else {
      middlewareAfter(request, step.index, profile, trace);
    }
  }
}

Future<String?> executeRuntimeAsyncPipeline(
  HttpRequest request,
  List<ExperimentalMiddlewareStep> steps,
  MiddlewareProfile profile,
  AsyncMiddlewareHandler handler, {
  List<String>? trace,
}) async {
  var entered = 0;
  for (final step in steps) {
    final decision = _isAsyncStep(profile, step.index)
        ? await middlewareBeforeAsync(request, step.index, profile, trace)
        : profile == MiddlewareProfile.instance && step.index == 0
        ? middlewareBenchmarkInstance.before(
            request,
            step.index,
            profile,
            trace,
          )
        : middlewareBefore(request, step.index, profile, trace);
    if (decision == MiddlewareDecision.unauthorized) {
      await _unwindRuntimeAsync(request, steps, entered, profile, trace);
      return null;
    }
    entered++;
  }
  trace?.add('handler');
  final result = await handler();
  await _unwindRuntimeAsync(request, steps, entered, profile, trace);
  return result;
}

Future<void> _unwindRuntimeAsync(
  HttpRequest request,
  List<ExperimentalMiddlewareStep> steps,
  int entered,
  MiddlewareProfile profile,
  List<String>? trace,
) async {
  for (var index = entered - 1; index >= 0; index--) {
    final step = steps[index];
    if (_isAsyncStep(profile, step.index)) {
      await middlewareAfterAsync(request, step.index, profile, trace);
    } else if (profile == MiddlewareProfile.instance && step.index == 0) {
      middlewareBenchmarkInstance.after(request, step.index, profile, trace);
    } else {
      middlewareAfter(request, step.index, profile, trace);
    }
  }
}

bool _isAsyncStep(MiddlewareProfile profile, int index) => switch (profile) {
  MiddlewareProfile.asyncMiddleware || MiddlewareProfile.shortAsync => true,
  MiddlewareProfile.mixed => index.isOdd,
  MiddlewareProfile.errorAsync => index == 0,
  _ => false,
};

final class ExperimentalLazyRequestState {
  Map<Object, Object?>? _values;

  void set(Object key, Object? value) => (_values ??= {})[key] = value;

  T? get<T>(Object key) => _values?[key] as T?;
}

final class GeneratedTypedMiddlewareState {
  const GeneratedTypedMiddlewareState({required this.authenticatedUserId});

  final int authenticatedUserId;
}

String executeStateExperiment(int id, MiddlewareProfile profile) {
  switch (profile) {
    case MiddlewareProfile.stateNone:
      return middlewareSyncHandler(id);
    case MiddlewareProfile.stateLazy:
      final state = ExperimentalLazyRequestState()..set(#userId, id);
      return middlewareSyncHandler(state.get<int>(#userId)!);
    case MiddlewareProfile.stateTyped:
      final state = GeneratedTypedMiddlewareState(authenticatedUserId: id);
      return middlewareSyncHandler(state.authenticatedUserId);
    default:
      throw ArgumentError.value(profile, 'profile');
  }
}

void writeMiddlewareUnauthorized(HttpRequest request) {
  final body = utf8.encode('{"error":"unauthorized"}');
  request.response
    ..statusCode = HttpStatus.unauthorized
    ..headers.contentType = ContentType.json
    ..headers.set('x-handler-invocations', '$middlewareHandlerInvocations')
    ..contentLength = body.length
    ..add(body);
  unawaited(request.response.close());
}

void writeMiddlewareOrder(
  HttpRequest request,
  String value,
  List<String> trace,
) {
  request.response.headers.set('x-middleware-order', trace.join(','));
  writeJsonStringResult(request, value);
}

void executeMiddlewareAsyncResponse(
  HttpRequest request,
  Future<String?> result, {
  List<String>? trace,
}) {
  unawaited(_executeMiddlewareAsyncResponse(request, result, trace: trace));
}

Future<void> _executeMiddlewareAsyncResponse(
  HttpRequest request,
  Future<String?> result, {
  List<String>? trace,
}) async {
  try {
    final value = await result;
    if (value == null) {
      writeMiddlewareUnauthorized(request);
    } else if (trace != null) {
      writeMiddlewareOrder(request, value, trace);
    } else {
      writeJsonStringResult(request, value);
    }
  } on ExpectedHandlerException {
    writeExpectedHandlerError(request);
  } on Object {
    writeUnexpectedHandlerError(request);
  }
}

/// Raw direct lower-bound dispatcher for Phase 1C semantic endpoints.
void rawMiddlewareDispatch(HttpRequest request) {
  final segments = handlerPathSegments(request.uri);
  if (segments == null) {
    writeNotFound(request);
    return;
  }
  if (segments.length == 1 && segments[0] == 'health') {
    if (request.method == 'GET') {
      writeTextResult(request, healthHandler());
    } else {
      writeMethodNotAllowed(request, const ['GET']);
    }
    return;
  }
  if (segments.length == 1 && segments[0] == 'status') {
    if (request.method == 'GET') {
      writeJsonStringResult(request, statusHandler());
    } else {
      writeMethodNotAllowed(request, const ['GET']);
    }
    return;
  }
  if (segments.length == 2 && segments[0] == 'users') {
    final id = int.tryParse(segments[1]);
    if (id == null) {
      writeInvalidParameter(request, 'id');
    } else if (request.method != 'GET') {
      writeMethodNotAllowed(request, const ['GET']);
    } else {
      writeJsonStringResult(request, middlewareSyncHandler(id));
    }
    return;
  }
  if (segments.length == 3 && segments[0] == 'async') {
    final id = int.tryParse(segments[2]);
    if (id == null) {
      writeInvalidParameter(request, 'id');
    } else if (request.method != 'GET') {
      writeMethodNotAllowed(request, const ['GET']);
    } else {
      final future = segments[1] == 'mixed'
          ? middlewareBoundaryAsyncHandler(id)
          : middlewareImmediateAsyncHandler(id);
      executeSpecializedStringFuture(request, future);
    }
    return;
  }
  if (segments.length == 4 &&
      segments[0] == 'orders' &&
      segments[2] == 'items') {
    final userId = int.tryParse(segments[1]);
    final orderId = int.tryParse(segments[3]);
    if (userId == null || orderId == null) {
      writeInvalidParameter(request, 'id');
    } else if (request.method != 'GET') {
      writeMethodNotAllowed(request, const ['GET']);
    } else {
      writeJsonStringResult(request, middlewareTwoIntHandler(userId, orderId));
    }
    return;
  }
  writeNotFound(request);
}

String middlewareImplementationName(MiddlewareCandidate candidate) =>
    switch (candidate) {
      MiddlewareCandidate.phase1b => 'middleware_phase1b',
      MiddlewareCandidate.generated => 'middleware_generated',
      MiddlewareCandidate.runtime => 'middleware_runtime',
    };

String middlewareSourceStem(MiddlewareCandidate candidate) =>
    switch (candidate) {
      MiddlewareCandidate.phase1b => 'phase1b',
      MiddlewareCandidate.generated => 'generated',
      MiddlewareCandidate.runtime => 'runtime',
    };
