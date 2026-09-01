import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:oche_core/oche_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'production runtime owns and completes a response exactly once',
    () async {
      var observedViolation = false;
      final runtime = OcheServerRuntime(
        dispatch: (request) {
          writeString(request, 'first');
          try {
            writeString(request, 'second');
          } on OcheResponseLifecycleViolation {
            observedViolation = true;
          }
        },
        address: InternetAddress.loopbackIPv4,
        port: 0,
      );
      await runtime.start();
      expect(runtime.state, OcheServerState.running);

      final response = await _get(runtime.boundPort!);
      expect(response, (status: HttpStatus.ok, body: 'first'));
      expect(observedViolation, isTrue);

      final firstStop = runtime.stop();
      final secondStop = runtime.stop();
      expect(identical(firstStop, secondStop), isTrue);
      await firstStop;
      expect(runtime.state, OcheServerState.stopped);
    },
  );

  test('production runtime drains an active async response', () async {
    final result = Completer<String>();
    final entered = Completer<void>();
    final runtime = OcheServerRuntime(
      dispatch: (request) {
        if (!entered.isCompleted) entered.complete();
        executeStringFuture(request, result.future);
      },
      address: InternetAddress.loopbackIPv4,
      port: 0,
    );
    await runtime.start();
    final responseFuture = _get(runtime.boundPort!);
    await entered.future;

    var stopped = false;
    final stopFuture = runtime
        .stop(timeout: const Duration(seconds: 2))
        .whenComplete(() => stopped = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(stopped, isFalse);

    result.complete('drained');
    expect(await responseFuture, (status: HttpStatus.ok, body: 'drained'));
    await stopFuture;
    expect(runtime.state, OcheServerState.stopped);
  });
}

Future<({int status, String body})> _get(int port) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/'));
    final response = await request.close();
    return (
      status: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
    );
  } finally {
    client.close(force: true);
  }
}
