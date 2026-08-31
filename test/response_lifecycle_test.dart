import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:handler_execution_benchmark/handler_execution_benchmark.dart';
import 'package:handler_execution_benchmark/response_lifecycle_benchmark.dart';
import 'package:test/test.dart';

void main() {
  group('response ownership', () {
    test(
      'normal sync, async, void, bytes, and structured results complete once',
      () async {
        final hooks = _RecordingHooks();
        final running = await _RunningRuntime.start((request) {
          switch (request.uri.path) {
            case '/sync':
              writeLifecycleTextResult(request, 'hello');
            case '/async':
              executeLifecycleStringFuture(
                request,
                Future<String>.value('async'),
                json: false,
              );
            case '/void':
              executeLifecycleVoidFuture(request, Future<void>.value());
            case '/bytes':
              writeLifecycleBytesResult(request, const [79, 99, 104, 101]);
            case '/user':
              writeLifecycleUserResult(request, const UserResult(42, 'sync'));
            case '/async-user':
              executeLifecycleUserFuture(
                request,
                Future<UserResult>.value(const UserResult(42, 'async')),
              );
            default:
              writeLifecycleNotFound(request);
          }
        }, hooks: hooks);
        addTearDown(running.close);

        expect((await running.get('/sync')).body, 'hello');
        expect((await running.get('/async')).body, 'async');
        final noContent = await running.get('/void');
        expect(noContent.statusCode, HttpStatus.noContent);
        expect(noContent.body, isEmpty);
        expect((await running.get('/bytes')).bodyBytes, [79, 99, 104, 101]);
        expect(jsonDecode((await running.get('/user')).body), {
          'id': 42,
          'name': 'sync',
        });
        expect(jsonDecode((await running.get('/async-user')).body), {
          'id': 42,
          'name': 'async',
        });

        await _waitUntil(() => hooks.completed == 6);
        expect(hooks.started, 6);
        expect(hooks.committed, 6);
        expect(hooks.completed, 6);
        expect(hooks.failures, isEmpty);
        expect(hooks.completionAttempts, everyElement(1));
        expect(
          hooks.completedStates,
          everyElement(InternalResponseState.completed),
        );
      },
    );

    test(
      'headers and an empty flush remain replaceable before body or close',
      () async {
        InternalResponseState? afterHeaders;
        InternalResponseState? afterEmptyFlush;
        final running = await _RunningRuntime.start((request) {
          if (request.uri.path == '/headers') {
            final lifecycle = responseLifecycleFor(request);
            lifecycle.response.headers.set('x-test', 'value');
            afterHeaders = lifecycle.state;
            writeLifecycleTextResult(request, 'headers');
            return;
          }
          final stream = transferLifecycleResponseToStream(
            request,
            contentType: ContentType.text,
          );
          executeLifecycleStreaming(stream, () async {
            await stream.flush();
            afterEmptyFlush = stream.state;
            stream.write('body');
          }());
        });
        addTearDown(running.close);

        final headers = await running.get('/headers');
        expect(headers.header('x-test'), 'value');
        expect(afterHeaders, InternalResponseState.uncommitted);
        expect((await running.get('/flush')).body, 'body');
        expect(afterEmptyFlush, InternalResponseState.uncommitted);
      },
    );

    test(
      'body write and close establish the conservative commit boundary',
      () async {
        final states = <InternalResponseState>[];
        final hooks = _RecordingHooks(
          onCommitted: (lifecycle) {
            states.add(lifecycle.state);
          },
        );
        final running = await _RunningRuntime.start((request) {
          final stream = transferLifecycleResponseToStream(request);
          if (request.uri.path == '/body') {
            stream.write('body');
          }
          stream.close();
          stream.close();
        }, hooks: hooks);
        addTearDown(running.close);

        expect((await running.get('/body')).body, 'body');
        expect((await running.get('/close')).body, isEmpty);
        await _waitUntil(() => hooks.completed == 2);
        expect(states, [
          InternalResponseState.committed,
          InternalResponseState.committed,
        ]);
        expect(hooks.committed, 2);
        expect(hooks.completed, 2);
      },
    );

    test(
      'short circuit owns completion and does not invoke the handler',
      () async {
        var handlerInvocations = 0;
        final hooks = _RecordingHooks();
        final running = await _RunningRuntime.start((request) {
          writeLifecycleMiddlewareUnauthorized(request);
          return;
          // ignore: dead_code
          handlerInvocations++;
        }, hooks: hooks);
        addTearDown(running.close);

        final response = await running.get('/short');
        expect(response.statusCode, HttpStatus.unauthorized);
        expect(jsonDecode(response.body), {'error': 'unauthorized'});
        expect(handlerInvocations, 0);
        await _waitUntil(() => hooks.completed == 1);
        expect(hooks.completionAttempts, [1]);
      },
    );

    test('a second response is rejected without replacing the first', () async {
      final hooks = _RecordingHooks();
      final running = await _RunningRuntime.start((request) {
        writeLifecycleTextResult(request, 'first');
        writeLifecycleTextResult(request, 'second');
      }, hooks: hooks);
      addTearDown(running.close);

      final response = await running.get('/double');
      expect(response.statusCode, HttpStatus.ok);
      expect(response.body, 'first');
      await _waitUntil(() => hooks.failures.isNotEmpty && hooks.completed == 1);
      expect(hooks.failures.single, isA<ResponseLifecycleViolation>());
      expect(hooks.completionAttempts, [2]);
      expect(hooks.committed, 1);
      expect(hooks.completed, 1);
    });

    test(
      'expected and unexpected failures are mapped only before commit',
      () async {
        final hooks = _RecordingHooks();
        final running = await _RunningRuntime.start((request) {
          if (request.uri.path == '/expected') {
            throw const ExpectedHandlerException('sensitive expected detail');
          }
          throw StateError('sensitive unexpected detail');
        }, hooks: hooks);
        addTearDown(running.close);

        final expected = await running.get('/expected');
        expect(expected.statusCode, HttpStatus.conflict);
        expect(expected.body, '{"error":"expected failure"}');
        final unexpected = await running.get('/unexpected');
        expect(unexpected.statusCode, HttpStatus.internalServerError);
        expect(unexpected.body, '{"error":"internal server error"}');
        expect(expected.body, isNot(contains('sensitive')));
        expect(unexpected.body, isNot(contains('sensitive')));
        await _waitUntil(() => hooks.completed == 2);
        expect(hooks.failures, hasLength(2));
        expect(hooks.committed, 2);
        expect(hooks.completed, 2);
      },
    );

    test(
      'failure after commit closes the owned stream without a second response',
      () async {
        final hooks = _RecordingHooks();
        final running = await _RunningRuntime.start((request) {
          final stream = transferLifecycleResponseToStream(
            request,
            contentType: ContentType.text,
          );
          stream.write('prefix');
          throw StateError('sensitive post-commit detail');
        }, hooks: hooks);
        addTearDown(running.close);

        final response = await running.get('/failure');
        expect(response.statusCode, HttpStatus.ok);
        expect(response.body, 'prefix');
        expect(response.body, isNot(contains('sensitive')));
        await _waitUntil(() => hooks.completed == 1);
        expect(hooks.failures.single, isA<StateError>());
        expect(hooks.committed, 1);
        expect(hooks.completed, 1);
      },
    );
  });

  group('streaming and protocol ownership', () {
    test('multiple chunks complete after the streaming after-hook', () async {
      final trace = <String>[];
      final hooks = _RecordingHooks();
      final running = await _RunningRuntime.start((request) {
        final stream = transferLifecycleResponseToStream(
          request,
          contentType: ContentType.text,
        );
        executeLifecycleStreaming(stream, () async {
          stream.write('chunk 1\n');
          await Future<void>.delayed(const Duration(milliseconds: 1));
          stream.write('chunk 2\n');
          await Future<void>.delayed(const Duration(milliseconds: 1));
          stream.write('chunk 3\n');
          trace.add('after');
        }());
      }, hooks: hooks);
      addTearDown(running.close);

      final response = await running.get('/stream');
      expect(response.body, 'chunk 1\nchunk 2\nchunk 3\n');
      expect(trace, ['after']);
      await _waitUntil(() => hooks.completed == 1);
      expect(hooks.committed, 1);
      expect(hooks.completed, 1);
    });

    test(
      'stream failure after the first chunk is internally observable',
      () async {
        final hooks = _RecordingHooks();
        final running = await _RunningRuntime.start((request) {
          final stream = transferLifecycleResponseToStream(request);
          executeLifecycleStreaming(stream, () async {
            stream.write('chunk');
            await Future<void>.delayed(Duration.zero);
            throw StateError('stream failed');
          }());
        }, hooks: hooks);
        addTearDown(running.close);

        expect((await running.get('/stream-error')).body, 'chunk');
        await _waitUntil(() => hooks.completed == 1);
        expect(hooks.failures.single, isA<StateError>());
        expect(hooks.committed, 1);
      },
    );

    test(
      'the stream owner can express an SSE response with periodic flushes',
      () async {
        final running = await _RunningRuntime.start((request) {
          final stream = transferLifecycleResponseToStream(
            request,
            contentType: ContentType('text', 'event-stream', charset: 'utf-8'),
          );
          executeLifecycleStreaming(stream, () async {
            stream.write('data: one\n\n');
            await stream.flush();
            await Future<void>.delayed(const Duration(milliseconds: 1));
            stream.write('data: two\n\n');
            await stream.flush();
          }());
        });
        addTearDown(running.close);

        final response = await running.get('/events');
        expect(
          response.header(HttpHeaders.contentTypeHeader),
          startsWith('text/event-stream'),
        );
        expect(response.body, 'data: one\n\ndata: two\n\n');
      },
    );

    test('detach transfers upgraded socket ownership away from HTTP', () async {
      InternalResponseOwnership? ownership;
      final running = await _RunningRuntime.start((request) {
        final lifecycle = responseLifecycleFor(request);
        lifecycle.response
          ..statusCode = HttpStatus.switchingProtocols
          ..headers.set(HttpHeaders.connectionHeader, 'upgrade')
          ..headers.set(HttpHeaders.upgradeHeader, 'oche-test');
        unawaited(
          lifecycle.detachSocket().then((socket) async {
            ownership = lifecycle.ownership;
            socket.add(utf8.encode('detached'));
            await socket.close();
          }),
        );
      });
      addTearDown(running.close);

      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        running.port,
      );
      socket.write(
        'GET /upgrade HTTP/1.1\r\n'
        'Host: 127.0.0.1:${running.port}\r\n'
        'Connection: Upgrade\r\n'
        'Upgrade: oche-test\r\n\r\n',
      );
      await socket.flush();
      final response = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();
      expect(response, contains('101 Switching Protocols'));
      expect(response, endsWith('detached'));
      expect(ownership, InternalResponseOwnership.detachedSocket);
    });

    test(
      'client disconnect during a write is contained and server stays usable',
      () async {
        final committed = Completer<void>();
        final continueWriting = Completer<void>();
        final hooks = _RecordingHooks(
          onCommitted: (_) {
            if (!committed.isCompleted) committed.complete();
          },
        );
        final chunk = List<int>.filled(64 * 1024, 120, growable: false);
        final running = await _RunningRuntime.start((request) {
          if (request.uri.path == '/ok') {
            writeLifecycleTextResult(request, 'OK');
            return;
          }
          final stream = transferLifecycleResponseToStream(request);
          executeLifecycleStreaming(stream, () async {
            stream.add(chunk);
            await stream.flush();
            await continueWriting.future;
            for (var index = 0; index < 64; index++) {
              stream.add(chunk);
              await stream.flush();
            }
          }());
        }, hooks: hooks);
        addTearDown(running.close);

        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          running.port,
        );
        socket.write(
          'GET /disconnect HTTP/1.1\r\n'
          'Host: 127.0.0.1:${running.port}\r\n'
          'Connection: close\r\n\r\n',
        );
        await socket.flush();
        await committed.future.timeout(const Duration(seconds: 2));
        socket.destroy();
        continueWriting.complete();
        await _waitUntil(() => running.runtime.activeRequests == 0);
        expect(hooks.disconnected, anyOf(0, 1));
        expect((await running.get('/ok')).body, 'OK');
        expect(running.runtime.state, InternalServerState.running);
      },
    );
  });

  group('server lifecycle', () {
    test(
      'successful startup and zero-active graceful shutdown are deterministic',
      () async {
        final hooks = _RecordingHooks();
        final runtime = ExperimentalServerRuntime(
          dispatch: (request) => writeLifecycleTextResult(request, 'OK'),
          port: 0,
          hooks: hooks,
        );
        expect(runtime.state, InternalServerState.created);
        await runtime.start();
        expect(runtime.state, InternalServerState.running);
        expect(runtime.boundPort, greaterThan(0));
        final first = runtime.stop();
        final second = runtime.stop();
        expect(identical(first, second), isTrue);
        await first;
        expect(runtime.state, InternalServerState.stopped);
        expect(runtime.activeRequests, 0);
        expect(hooks.shutdownStartedCount, 1);
        expect(hooks.shutdownCompletedCount, 1);
        expect(hooks.forcedShutdownCount, 0);
      },
    );

    test(
      'stop during startup waits for bind and closes deterministically',
      () async {
        final runtime = ExperimentalServerRuntime(dispatch: (_) {}, port: 0);
        final starting = runtime.start();
        final stopping = runtime.stop();
        await starting;
        await stopping;
        expect(runtime.state, InternalServerState.stopped);
        expect(runtime.activeRequests, 0);
      },
    );

    test('invalid port and bind failure leave the runtime stopped', () async {
      final invalid = ExperimentalServerRuntime(dispatch: (_) {}, port: 65536);
      await expectLater(invalid.start(), throwsRangeError);
      expect(invalid.state, InternalServerState.stopped);
      expect(invalid.boundPort, isNull);

      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: false,
      );
      addTearDown(reservation.close);
      final occupied = ExperimentalServerRuntime(
        dispatch: (_) {},
        port: reservation.port,
      );
      await expectLater(occupied.start(), throwsA(isA<SocketException>()));
      expect(occupied.state, InternalServerState.stopped);
      expect(occupied.boundPort, isNull);
    });

    test('shutdown waits for an accepted synchronous response', () async {
      final hooks = _StopOnRequestHooks();
      final running = await _RunningRuntime.start(
        (request) => writeLifecycleTextResult(request, 'sync'),
        hooks: hooks,
      );
      hooks.runtime = running.runtime;
      addTearDown(running.close);

      expect((await running.get('/sync')).body, 'sync');
      await hooks.stopFuture!;
      expect(hooks.activeAtStop, 1);
      expect(running.runtime.state, InternalServerState.stopped);
      expect(running.runtime.activeRequests, 0);
    });

    test('shutdown waits for an active async handler', () async {
      final gate = Completer<String>();
      final hooks = _StopOnRequestHooks();
      final running = await _RunningRuntime.start((request) {
        executeLifecycleStringFuture(request, gate.future, json: false);
      }, hooks: hooks);
      hooks.runtime = running.runtime;
      addTearDown(running.close);

      final response = running.get('/async');
      await _waitUntil(() => hooks.stopFuture != null);
      var stopped = false;
      unawaited(hooks.stopFuture!.then((_) => stopped = true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(stopped, isFalse);
      expect(running.runtime.state, InternalServerState.stopping);
      gate.complete('async');
      expect((await response).body, 'async');
      await hooks.stopFuture;
      expect(running.runtime.state, InternalServerState.stopped);
    });

    test('shutdown waits for an active streaming response', () async {
      final gate = Completer<void>();
      final hooks = _StopOnRequestHooks();
      final running = await _RunningRuntime.start((request) {
        final stream = transferLifecycleResponseToStream(request);
        executeLifecycleStreaming(stream, () async {
          stream.write('first');
          await gate.future;
          stream.write('second');
        }());
      }, hooks: hooks);
      hooks.runtime = running.runtime;
      addTearDown(running.close);

      final response = running.get('/stream');
      await _waitUntil(() => hooks.stopFuture != null);
      var stopped = false;
      unawaited(hooks.stopFuture!.then((_) => stopped = true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(stopped, isFalse);
      gate.complete();
      expect((await response).body, 'firstsecond');
      await hooks.stopFuture;
      expect(running.runtime.state, InternalServerState.stopped);
    });

    test('shutdown timeout force-closes active connections', () async {
      final gate = Completer<String>();
      final hooks = _StopOnRequestHooks(
        timeout: const Duration(milliseconds: 30),
      );
      final running = await _RunningRuntime.start((request) {
        executeLifecycleStringFuture(request, gate.future, json: false);
      }, hooks: hooks);
      hooks.runtime = running.runtime;
      addTearDown(running.close);

      final response = running
          .get('/forced')
          .then<Object>(
            (value) => value,
            onError: (Object error, StackTrace _) => error,
          );
      await _waitUntil(() => hooks.stopFuture != null);
      await hooks.stopFuture;
      expect(running.runtime.forcedShutdown, isTrue);
      expect(running.runtime.state, InternalServerState.stopped);
      expect(running.runtime.activeRequests, 0);
      expect(hooks.forcedShutdownCount, 1);
      expect(await response, isA<HttpException>());
      gate.complete('too late');
    });
  });
}

final class _RecordingHooks implements InternalLifecycleHooks {
  _RecordingHooks({this.onCommitted});

  final void Function(InternalResponseLifecycle lifecycle)? onCommitted;
  int started = 0;
  int committed = 0;
  int completed = 0;
  int disconnected = 0;
  int shutdownStartedCount = 0;
  int shutdownCompletedCount = 0;
  int forcedShutdownCount = 0;
  final failures = <Object>[];
  final completionAttempts = <int>[];
  final completedStates = <InternalResponseState>[];

  @override
  void requestStarted(HttpRequest request) => started++;

  @override
  void responseCommitted(HttpRequest request) {
    committed++;
    onCommitted?.call(responseLifecycleFor(request));
  }

  @override
  void requestCompleted(HttpRequest request) {
    completed++;
    final lifecycle = responseLifecycleFor(request);
    completionAttempts.add(lifecycle.completionAttempts);
    completedStates.add(lifecycle.state);
  }

  @override
  void requestFailed(HttpRequest request, Object error, StackTrace stackTrace) {
    failures.add(error);
  }

  @override
  void clientDisconnected(HttpRequest request, Object error) => disconnected++;

  @override
  void shutdownStarted() => shutdownStartedCount++;

  @override
  void shutdownCompleted() => shutdownCompletedCount++;

  @override
  void forcedShutdown() => forcedShutdownCount++;
}

final class _StopOnRequestHooks extends _RecordingHooks {
  _StopOnRequestHooks({this.timeout = const Duration(seconds: 2)});

  final Duration timeout;
  ExperimentalServerRuntime? runtime;
  Future<void>? stopFuture;
  int? activeAtStop;

  @override
  void requestStarted(HttpRequest request) {
    super.requestStarted(request);
    if (stopFuture != null) return;
    activeAtStop = runtime!.activeRequests;
    stopFuture = runtime!.stop(timeout: timeout);
  }
}

final class _RunningRuntime {
  const _RunningRuntime(this.runtime, this.client);

  final ExperimentalServerRuntime runtime;
  final HttpClient client;

  int get port => runtime.boundPort!;

  static Future<_RunningRuntime> start(
    HandlerDispatch dispatch, {
    InternalLifecycleHooks? hooks,
  }) async {
    final runtime = ExperimentalServerRuntime(
      dispatch: dispatch,
      port: 0,
      hooks: hooks,
    );
    await runtime.start();
    return _RunningRuntime(runtime, HttpClient());
  }

  Future<_TestResponse> get(String path) async {
    final request = await client.getUrl(Uri.http('127.0.0.1:$port', path));
    final response = await request.close();
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(',');
    });
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    return _TestResponse(response.statusCode, headers, bytes);
  }

  Future<void> close() async {
    client.close(force: true);
    await runtime.stop(timeout: const Duration(milliseconds: 200));
  }
}

final class _TestResponse {
  const _TestResponse(this.statusCode, this.headers, this.bodyBytes);

  final int statusCode;
  final Map<String, String> headers;
  final List<int> bodyBytes;

  String get body => utf8.decode(bodyBytes);
  String? header(String name) => headers[name.toLowerCase()];
}

Future<void> _waitUntil(bool Function() predicate) async {
  final watch = Stopwatch()..start();
  while (!predicate()) {
    if (watch.elapsed > const Duration(seconds: 3)) {
      throw TimeoutException('Condition did not become true.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
