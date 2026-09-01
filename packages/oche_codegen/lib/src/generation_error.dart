/// A deterministic, actionable error in an Oche source declaration.
final class OcheGenerationError implements Exception {
  const OcheGenerationError(this.message);

  final String message;

  @override
  String toString() => 'Oche generation failed: $message';
}
