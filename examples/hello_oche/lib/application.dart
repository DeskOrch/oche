import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:oche/oche.dart';

@Controller('/hello')
final class HelloController {
  @Get()
  String world() => 'Hello, World!';

  @Get('/{name}')
  Future<String> greet(@Path('name') String name) async {
    await Future<void>.delayed(Duration.zero);
    return 'Hello, $name!';
  }

  @Post('/{name}')
  void accept(@Path('name') String name) {}
}

@Controller('/users')
final class UserController {
  @Get('/search')
  String search() => 'User search';

  @Get('/{id}')
  String find(@Path('id') int id) => 'User $id';

  @Put('/{id}')
  Future<void> replace(@Path('id') int id) async {
    await Future<void>.delayed(Duration.zero);
  }

  @Patch('/{id}')
  Uint8List patch(@Path('id') int id) => Uint8List.fromList(utf8.encode('$id'));

  @Delete('/{id}')
  Future<Uint8List> delete(@Path('id') int id) async =>
      Uint8List.fromList(utf8.encode('deleted $id'));
}

@Controller('/async')
final class AsyncController {
  @Get('/sync/{id}')
  Future<String> immediate(@Path('id') int id) async => '{"id":$id}';
}

@Controller('/errors')
final class ErrorController {
  @Get('/sync')
  String sync() => throw StateError('sensitive sync detail');

  @Get('/async')
  Future<String> async() =>
      Future<String>.error(StateError('sensitive async detail'));
}

/// Cross-framework workloads used by the post-Phase-2A Linux validation gate.
@Controller('/validation')
final class ValidationController {
  @Get('/sync')
  String sync() => 'Hello, World!';

  @Get('/async')
  Future<String> async() async => 'Hello, World!';

  @Get('/users/{id}')
  String user(@Path('id') int id) => 'User $id';
}

@OcheApplication(
  controllers: [
    HelloController,
    UserController,
    AsyncController,
    ErrorController,
    ValidationController,
  ],
)
final class Application {}
