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

/// Returns a deterministic position-balanced order for two or more items.
///
/// The existing three-way sequence remains byte-for-byte compatible. Other
/// sizes use forward rotations followed by reverse rotations, so a full
/// `2 * items.length` cycle places each item in each position twice.
List<T> balancedOrder<T>(List<T> items, int iteration) {
  if (items.length == 3) return balancedThreeWayOrder(items, iteration);
  if (items.length < 2) {
    throw ArgumentError.value(
      items,
      'items',
      'At least two items are required.',
    );
  }
  if (iteration < 1) {
    throw RangeError.range(iteration, 1, null, 'iteration');
  }
  final cycleIndex = (iteration - 1) % (items.length * 2);
  final reverse = cycleIndex >= items.length;
  final rotation = cycleIndex % items.length;
  return List<T>.generate(items.length, (position) {
    final offset = reverse ? -position : position;
    return items[(rotation + offset) % items.length];
  }, growable: false);
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
  _validateOrder('implementation-order', implementationOrder!, minimum: 2);
  _validateOrder('endpoint-order', endpointOrder!, minimum: 1);
  if (iteration! < 1 || trialSequence! < 1) {
    throw RangeError('iteration and trial sequence must be positive.');
  }
  if (implementationPosition! < 1 ||
      implementationPosition > implementationOrder.length) {
    throw RangeError.range(
      implementationPosition,
      1,
      implementationOrder.length,
      'implementation-position',
    );
  }
  if (endpointPosition! < 1 || endpointPosition > endpointOrder.length) {
    throw RangeError.range(
      endpointPosition,
      1,
      endpointOrder.length,
      'endpoint-position',
    );
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

void _validateOrder(String name, List<String> order, {required int minimum}) {
  if (order.length < minimum || order.toSet().length != order.length) {
    throw FormatException(
      '--$name must contain at least $minimum distinct value(s).',
    );
  }
  if (order.any((value) => value.isEmpty)) {
    throw FormatException('--$name values must not be empty.');
  }
}
