import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/domain/costing.dart';

void main() {
  test('purchase cost split by CNY value', () {
    expect(itemPurchaseCosts(paidZmw: 37000, itemValuesCny: [5000, 5000]), [18500, 18500]);
  });

  test('effective rate', () {
    expect(effectiveRate(paidZmw: 37000, totalCny: 10000), closeTo(3.7, 1e-9));
    expect(effectiveRate(paidZmw: 100, totalCny: 0), isNull);
  });
}
