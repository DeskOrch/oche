import 'package:handler_execution_benchmark/handler_execution_benchmark.dart';
import 'package:handler_execution_benchmark/middleware_execution_benchmark.dart';

Future<void> main(List<String> arguments) => runHandlerBenchmarkServer(
  arguments,
  name: 'middleware-raw',
  dispatch: rawMiddlewareDispatch,
);
