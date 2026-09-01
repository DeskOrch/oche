import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:oche_codegen/builder.dart';
import 'package:oche_codegen/oche_codegen.dart';
import 'package:test/test.dart';

const _inputId = 'oche_workspace|lib/phase2a_fixture.dart';
const _outputId = 'oche_workspace|lib/phase2a_fixture.oche.dart';

void main() {
  group('production Oche generator', () {
    test(
      'emits a typed segmented tree with specialized direct calls',
      () async {
        final generated = await _generate(r'''
import 'dart:async';
import 'dart:typed_data';
import 'package:oche/oche.dart';

@Controller('/users')
final class Users {
  @Get('/search')
  String search() => 'search';

  @Get('/{id}')
  String find(@Path('id') int id) => '$id';

  @Post('/{name}')
  Future<String> create(@Path('name') String name) async => name;

  @Put('/{id}')
  void replace(@Path('id') int id) {}

  @Patch('/{id}')
  Future<void> patch(@Path('id') int id) async {}

  @Delete('/{id}')
  Uint8List delete(@Path('id') int id) => Uint8List(0);
}

@Controller('/bytes')
final class Bytes {
  @Get()
  Future<Uint8List> bytes() async => Uint8List(0);
}

@OcheApplication(controllers: [Users, Bytes])
final class App {}
''');

        expect(generated, contains('final class AppOche'));
        expect(generated, contains('_initializeControllers('));
        expect(generated, contains('dispatch: _initializedDispatch'));
        expect(generated, contains('switch (segments.length)'));
        expect(generated, contains("case 'search':"));
        expect(generated, contains('int.tryParse(segments[1])'));
        expect(generated, contains('_controller0.find(path0)'));
        expect(generated, contains('executeStringFuture'));
        expect(generated, contains('executeVoidFuture'));
        expect(generated, contains('executeBytesFuture'));
        expect(
          generated.indexOf("case 'search':"),
          lessThan(generated.indexOf('int.tryParse(segments[1])')),
        );
        for (final forbidden in const [
          'Function.apply',
          'Map<String',
          'registerRoute',
          'dart:mirrors',
          'dynamic handler',
        ]) {
          expect(generated, isNot(contains(forbidden)));
        }
      },
    );

    test('output is deterministic', () async {
      const source = '''
import 'package:oche/oche.dart';
@Controller('/hello')
final class Hello { @Get() String get() => 'hello'; }
@OcheApplication(controllers: [Hello])
final class App {}
''';
      expect(await _generate(source), await _generate(source));
    });

    test('accepts an explicit zero-argument controller constructor', () async {
      final generated = await _generate('''
import 'package:oche/oche.dart';
@Controller('/hello')
final class Hello {
  Hello();
  @Get() String get() => 'hello';
}
@OcheApplication(controllers: [Hello])
final class App {}
''');
      expect(generated, contains('i0.Hello()'));
    });

    test('escapes literal route strings in generated Dart', () async {
      final generated = await _generate(r'''
import 'package:oche/oche.dart';
@Controller('/special')
final class Special {
  @Get("/it's-\$5") String get() => '';
}
@OcheApplication(controllers: [Special])
final class App {}
''');
      expect(generated, contains(r"case 'it\'s-\$5':"));
    });

    for (final diagnostic in <String, ({String source, String message})>{
      'duplicate literal route': (
        source: '''
@Controller('/users')
final class C {
  @Get() String first() => '';
  @Get() String second() => '';
}
''',
        message: 'Conflicting route GET /users',
      ),
      'duplicate parameter shape': (
        source: '''
@Controller('/users')
final class C {
  @Get('/{id}') String first(@Path('id') int id) => '';
  @Get('/{userId}') String second(@Path('userId') int id) => '';
}
''',
        message: 'Conflicting route GET /users/{}',
      ),
      'missing Path binding': (
        source: '''
@Controller('/users')
final class C { @Get('/{id}') String find() => ''; }
''',
        message: 'has no @Path("id") parameter',
      ),
      'unknown Path name': (
        source: '''
@Controller('/users')
final class C {
  @Get('/{id}') String find(@Path('userId') int id) => '';
}
''',
        message: '@Path("userId")',
      ),
      'duplicate Path binding': (
        source: '''
@Controller('/users')
final class C {
  @Get('/{id}') String find(
    @Path('id') int id,
    @Path('id') int other,
  ) => '';
}
''',
        message: 'binds @Path("id") more than once',
      ),
      'unsupported parameter type': (
        source: '''
@Controller('/users')
final class C {
  @Get('/{id}') String find(@Path('id') double id) => '';
}
''',
        message: 'Use non-nullable String or int',
      ),
      'unsupported return type': (
        source: '''
@Controller('/users')
final class C { @Get() int find() => 1; }
''',
        message: 'returns unsupported type int',
      ),
      'non-controller application entry': (
        source: 'final class C {}',
        message: 'is not annotated with @Controller',
      ),
      'unsupported controller constructor': (
        source: '''
@Controller('/users')
final class C {
  C(this.value);
  final int value;
  @Get() String find() => '';
}
''',
        message: 'Dependency injection is not supported in Phase 2A',
      ),
    }.entries) {
      test('diagnoses ${diagnostic.key}', () async {
        await _expectGenerationError(
          _applicationSource(diagnostic.value.source),
          diagnostic.value.message,
        );
      });
    }

    test('diagnoses multiple application roots in one library', () async {
      await _expectGenerationError('''
import 'package:oche/oche.dart';
@Controller()
final class C { @Get() String get() => ''; }
@OcheApplication(controllers: [C])
final class First {}
@OcheApplication(controllers: [C])
final class Second {}
''', 'multiple @OcheApplication roots');
    });
  });
}

String _applicationSource(String declarations) =>
    '''
import 'package:oche/oche.dart';
$declarations
@OcheApplication(controllers: [C])
final class App {}
''';

Future<String> _generate(String source) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'oche_workspace',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    ocheApplicationBuilder(BuilderOptions.empty),
    {_inputId: source},
    rootPackage: 'oche_workspace',
    readerWriter: readerWriter,
    outputs: null,
    flattenOutput: true,
  );
  if (!result.succeeded) {
    throw OcheGenerationError(result.errors.join('\n'));
  }
  return readerWriter.testing.readString(AssetId.parse(_outputId));
}

Future<void> _expectGenerationError(String source, String message) async {
  await expectLater(
    _generate(source),
    throwsA(
      isA<OcheGenerationError>().having(
        (error) => error.message,
        'message',
        contains(message),
      ),
    ),
  );
}
