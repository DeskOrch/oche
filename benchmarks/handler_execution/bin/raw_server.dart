import 'package:handler_execution_benchmark/handler_execution_benchmark.dart';

Future<void> main(List<String> arguments) => runHandlerBenchmarkServer(
  arguments,
  name: 'handler-raw-dart-io',
  dispatch: rawHandlerDispatch,
);
