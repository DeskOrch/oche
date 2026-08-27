import 'dart:async';
import 'dart:io';

import 'package:oche_static_benchmark/oche_static_benchmark.dart';

Future<void> main(List<String> arguments) async {
  final options = _ServerOptions.parse(arguments);
  final addresses = await InternetAddress.lookup(options.host);
  if (addresses.isEmpty) {
    throw StateError('Could not resolve ${options.host}.');
  }

  final server = await startOcheStaticBenchmarkServer(
    address: addresses.first,
    port: options.port,
  );
  stdout.writeln('oche_static ready on ${options.host}:${server.port}');

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
