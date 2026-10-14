import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/core/allocation.dart';

int sum(List<int> xs) => xs.fold(0, (a, b) => a + b);

void main() {
  test('splits proportionally', () {
    expect(allocate(1000, [1, 1, 2]), [250, 250, 500]);
  });

  test('parts always sum to the total', () {
    final parts = allocate(100, [1, 1, 1]);
    expect(sum(parts), 100);
    expect(parts, [34, 33, 33]);
  });

  test('largest remainder gets the extra unit', () {
    // 10 * 2/7 = 2.857, 10 * 5/7 = 7.142 -> remainders favour the first.
    expect(allocate(10, [2, 5]), [3, 7]);
  });

  test('all-zero weights split evenly', () {
    expect(allocate(10, [0, 0, 0]), [4, 3, 3]);
  });

  test('zero weight among others gets nothing', () {
    expect(allocate(500, [0, 3, 2]), [0, 300, 200]);
  });

  test('negative totals keep their sign', () {
    expect(allocate(-100, [1, 1, 1]), [-34, -33, -33]);
  });

  test('handles large amounts without overflow', () {
    final parts = allocate(9007199254740, [123456789, 987654321]);
    expect(sum(parts), 9007199254740);
  });

  test('rejects negative weights', () {
    expect(() => allocate(10, [1, -1]), throwsArgumentError);
  });

  test('empty weights give empty result', () {
    expect(allocate(10, []), isEmpty);
  });
}
