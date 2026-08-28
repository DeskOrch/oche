import 'package:routing_kernel_benchmark/routing_kernel_benchmark.dart';

Future<void> main(List<String> arguments) => runKernelBenchmarkServer(
  arguments,
  name: 'raw_dart_io kernel',
  dispatch: rawKernelDispatch,
);
