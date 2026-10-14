/// Splits [total] minor units across [weights] so the parts always sum
/// exactly to [total] (largest-remainder method).
///
/// Used everywhere a cost is spread over items: purchase totals, shipping
/// lines, collection costs. Ties go to the earliest index so results are
/// deterministic. If every weight is zero the total is split evenly.
List<int> allocate(int total, List<int> weights) {
  if (weights.isEmpty) return const [];
  if (weights.any((w) => w < 0)) {
    throw ArgumentError.value(weights, 'weights', 'must not be negative');
  }
  final sign = total < 0 ? -1 : 1;
  final amount = total.abs();
  final effective = weights.every((w) => w == 0) ? List.filled(weights.length, 1) : weights;
  final weightSum = effective.fold<int>(0, (a, b) => a + b);

  final parts = <int>[];
  final remainders = <int>[];
  var assigned = 0;
  for (final w in effective) {
    final product = BigInt.from(amount) * BigInt.from(w);
    final share = (product ~/ BigInt.from(weightSum)).toInt();
    parts.add(share);
    remainders.add((product % BigInt.from(weightSum)).toInt());
    assigned += share;
  }

  final order = List.generate(effective.length, (i) => i)
    ..sort((a, b) {
      final byRemainder = remainders[b].compareTo(remainders[a]);
      return byRemainder != 0 ? byRemainder : a.compareTo(b);
    });
  for (var i = 0; i < amount - assigned; i++) {
    parts[order[i]] += 1;
  }
  return [for (final p in parts) p * sign];
}
