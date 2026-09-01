import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:oche_codegen/src/annotation_reader.dart';
import 'package:oche_codegen/src/application_analyzer.dart';
import 'package:oche_codegen/src/generation_error.dart';
import 'package:oche_codegen/src/source_emitter.dart';

final class OcheApplicationBuilder implements Builder {
  const OcheApplicationBuilder();

  @override
  Map<String, List<String>> get buildExtensions => const {
    '.dart': ['.oche.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) return;
    final library = await buildStep.resolver.libraryFor(buildStep.inputId);
    final roots = <ClassElement>[];
    for (final element in library.classes) {
      if (readOcheAnnotation(element, 'OcheApplication') != null) {
        roots.add(element);
      }
    }
    if (roots.isEmpty) return;
    if (roots.length > 1) {
      throw OcheGenerationError(
        '${buildStep.inputId.path} declares multiple @OcheApplication roots '
        '(${roots.map((root) => root.displayName).join(', ')}). Keep one '
        'application root per library.',
      );
    }

    final model = const ApplicationAnalyzer().analyze(roots.single);
    final source = const SourceEmitter().emit(model);
    final output = buildStep.inputId.changeExtension('.oche.dart');
    await buildStep.writeAsString(output, source);
  }
}
