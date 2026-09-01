import 'package:hello_oche/application.oche.dart';

Future<void> main(List<String> arguments) {
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
  return ApplicationOche.run(host: host, port: port);
}
