/// Deterministic balanced schedules for repeated benchmark execution.
library;

const _balancedThreeWayIndices = <List<int>>[
  [0, 1, 2],
  [1, 2, 0],
  [2, 0, 1],
  [0, 2, 1],
  [1, 0, 2],
  [2, 1, 0],
];

/// Returns one of all six permutations in a fixed, repeating order.
///
/// [iteration] is one-based. Every item occupies the first, middle, and last
/// position once in each six-iteration cycle. The first five permutations also
/// place every item in every position at least once.
List<T> balancedThreeWayOrder<T>(List<T> items, int iteration) {
  if (items.length != 3) {
    throw ArgumentError.value(
      items,
      'items',
      'Exactly three items are required.',
    );
  }
  if (iteration < 1) {
    throw RangeError.range(iteration, 1, null, 'iteration');
  }
  final indices = _balancedThreeWayIndices[(iteration - 1) % 6];
  return indices.map((index) => items[index]).toList(growable: false);
}

/// Builds the raw-result schedule block, enforcing an all-or-none contract.
///
/// A standalone benchmark has no schedule block. Suite callers must provide
/// every field so generated results always satisfy the result schema.
Map<String, Object>? benchmarkScheduleMetadata({
  String? suiteRunId,
  int? iteration,
  int? trialSequence,
  List<String>? implementationOrder,
  int? implementationPosition,
  List<String>? endpointOrder,
  int? endpointPosition,
  int? cooldownSeconds,
}) {
  final values = <Object?>[
    suiteRunId,
    iteration,
    trialSequence,
    implementationOrder,
    implementationPosition,
    endpointOrder,
    endpointPosition,
    cooldownSeconds,
  ];
  if (values.every((value) => value == null)) return null;
  if (values.any((value) => value == null)) {
    throw const FormatException(
      'Suite schedule options must either all be supplied or all be omitted.',
    );
  }

  if (suiteRunId!.isEmpty) {
    throw const FormatException('--suite-run-id must not be empty.');
  }
  _validateOrder('implementation-order', implementationOrder!);
  _validateOrder('endpoint-order', endpointOrder!);
  if (iteration! < 1 || trialSequence! < 1) {
    throw RangeError('iteration and trial sequence must be positive.');
  }
  if (implementationPosition! < 1 || implementationPosition > 3) {
    throw RangeError.range(
      implementationPosition,
      1,
      3,
      'implementation-position',
    );
  }
  if (endpointPosition! < 1 || endpointPosition > 3) {
    throw RangeError.range(endpointPosition, 1, 3, 'endpoint-position');
  }
  if (cooldownSeconds! < 0) {
    throw RangeError.range(cooldownSeconds, 0, null, 'cooldown');
  }

  return {
    'suiteRunId': suiteRunId,
    'iteration': iteration,
    'trialSequence': trialSequence,
    'implementationOrder': implementationOrder,
    'implementationPosition': implementationPosition,
    'endpointOrder': endpointOrder,
    'endpointPosition': endpointPosition,
    'cooldownSeconds': cooldownSeconds,
  };
}

void _validateOrder(String name, List<String> order) {
  if (order.length != 3 || order.toSet().length != 3) {
    throw FormatException('--$name must contain three distinct values.');
  }
  if (order.any((value) => value.isEmpty)) {
    throw FormatException('--$name values must not be empty.');
  }
}
