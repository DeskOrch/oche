import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

const _ocheAnnotationLibrary = 'package:oche/src/annotations.dart';

DartObject? readOcheAnnotation(Element element, String className) {
  DartObject? result;
  for (final annotation in element.metadata.annotations) {
    final value = annotation.computeConstantValue();
    if (value == null || !_isOcheValue(value, className)) continue;
    if (result != null) {
      throw StateError(
        '${element.displayName} has more than one @$className annotation.',
      );
    }
    result = value;
  }
  return result;
}

bool _isOcheValue(DartObject value, String className) {
  final type = value.type;
  final typeElement = type?.element;
  return typeElement?.displayName == className &&
      typeElement?.library?.uri.toString() == _ocheAnnotationLibrary;
}

String readStringField(DartObject annotation, String field) {
  final value = annotation.getField(field)?.toStringValue();
  if (value == null) {
    throw StateError('Oche annotation field "$field" is not a string.');
  }
  return value;
}
