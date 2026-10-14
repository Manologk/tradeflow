import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/domain/costing.dart';

const general = 'general';
const sensitive = 'sensitive';

CostItem item(String id, String purchase, int cost, {String cargo = general, int qty = 1}) =>
    CostItem(id: id, purchaseId: purchase, cargoTypeId: cargo, qty: qty, purchaseCostZmw: cost);

void main() {
  test('purchase cost split by CNY value', () {
    expect(itemPurchaseCosts(paidZmw: 37000, itemValuesCny: [5000, 5000]), [18500, 18500]);
  });

  test('effective rate', () {
    expect(effectiveRate(paidZmw: 37000, totalCny: 10000), closeTo(3.7, 1e-9));
    expect(effectiveRate(paidZmw: 100, totalCny: 0), isNull);
  });

  test('bill payment split across lines by USD amount', () {
    expect(billLineCosts(paidZmw: 300000, lineAmountsUsd: [1000, 2000]), [100000, 200000]);
  });

  group('landedCosts', () {
    test('without shipping, landed cost is the purchase cost', () {
      final costs = landedCosts(items: [item('a', 'p1', 5000, qty: 2)]);
      expect(costs['a']!.totalZmw, 5000);
      expect(costs['a']!.unitZmw, 2500);
    });

    test('one-by-one line goes entirely to its purchase', () {
      final costs = landedCosts(
        items: [item('a', 'p1', 10000), item('b', 'p2', 10000)],
        shippingLines: const [
          CostShippingLine(id: 'l1', cargoTypeId: general, costZmw: 4000, purchaseIds: ['p1']),
        ],
      );
      expect(costs['a']!.shippingZmw, 4000);
      expect(costs['b']!.shippingZmw, 0);
    });

    test('line is split within a purchase by item value', () {
      final costs = landedCosts(
        items: [item('a', 'p1', 30000), item('b', 'p1', 10000)],
        shippingLines: const [
          CostShippingLine(id: 'l1', cargoTypeId: general, costZmw: 4000, purchaseIds: ['p1']),
        ],
      );
      expect(costs['a']!.shippingZmw, 3000);
      expect(costs['b']!.shippingZmw, 1000);
    });

    test('consolidated line is split across purchases by value', () {
      final costs = landedCosts(
        items: [item('a', 'p1', 20000), item('b', 'p2', 60000)],
        shippingLines: const [
          CostShippingLine(id: 'l1', cargoTypeId: general, costZmw: 8000, purchaseIds: ['p1', 'p2']),
        ],
      );
      expect(costs['a']!.shippingZmw, 2000);
      expect(costs['b']!.shippingZmw, 6000);
    });

    test('a cargo-type line only lands on items of that type', () {
      final costs = landedCosts(
        items: [
          item('cable', 'p1', 10000),
          item('powerbank', 'p1', 10000, cargo: sensitive),
          item('shoes', 'p2', 40000),
        ],
        shippingLines: const [
          CostShippingLine(id: 'g', cargoTypeId: general, costZmw: 5000, purchaseIds: ['p1', 'p2']),
          CostShippingLine(id: 's', cargoTypeId: sensitive, costZmw: 3000, purchaseIds: ['p1', 'p2']),
        ],
      );
      expect(costs['cable']!.shippingZmw, 1000);
      expect(costs['shoes']!.shippingZmw, 4000);
      expect(costs['powerbank']!.shippingZmw, 3000);
    });

    test('line with no matching cargo type falls back to all covered items', () {
      final costs = landedCosts(
        items: [item('a', 'p1', 10000), item('b', 'p1', 30000)],
        shippingLines: const [
          CostShippingLine(id: 's', cargoTypeId: sensitive, costZmw: 2000, purchaseIds: ['p1']),
        ],
      );
      expect(costs['a']!.shippingZmw, 500);
      expect(costs['b']!.shippingZmw, 1500);
    });

    test('several lines on one purchase add up', () {
      final costs = landedCosts(
        items: [item('a', 'p1', 10000)],
        shippingLines: const [
          CostShippingLine(id: 'l1', cargoTypeId: general, costZmw: 1500, purchaseIds: ['p1']),
          CostShippingLine(id: 'l2', cargoTypeId: general, costZmw: 2500, purchaseIds: ['p1']),
        ],
      );
      expect(costs['a']!.shippingZmw, 4000);
    });

    test('collection cost split by purchase cost plus shipping', () {
      final costs = landedCosts(
        items: [item('a', 'p1', 10000), item('b', 'p2', 10000)],
        shippingLines: const [
          CostShippingLine(id: 'l1', cargoTypeId: general, costZmw: 10000, purchaseIds: ['p2']),
        ],
        collections: const [
          CostCollection(id: 'c1', costZmw: 3000, purchaseIds: ['p1', 'p2']),
        ],
      );
      // Weights 10000 vs 20000.
      expect(costs['a']!.collectionZmw, 1000);
      expect(costs['b']!.collectionZmw, 2000);
      expect(costs['b']!.totalZmw, 10000 + 10000 + 2000);
    });

    test('every ngwee is accounted for', () {
      final items = [
        item('a', 'p1', 3333, qty: 3),
        item('b', 'p1', 6667, cargo: sensitive),
        item('c', 'p2', 1001),
        item('d', 'p3', 0),
      ];
      final costs = landedCosts(
        items: items,
        shippingLines: const [
          CostShippingLine(id: 'l1', cargoTypeId: general, costZmw: 9999, purchaseIds: ['p1', 'p2', 'p3']),
          CostShippingLine(id: 'l2', cargoTypeId: sensitive, costZmw: 777, purchaseIds: ['p1']),
        ],
        collections: const [
          CostCollection(id: 'c', costZmw: 1234, purchaseIds: ['p1', 'p2', 'p3']),
        ],
      );
      final total = costs.values.fold<int>(0, (s, c) => s + c.totalZmw);
      expect(total, 3333 + 6667 + 1001 + 9999 + 777 + 1234);
    });

    test('lines and collections covering unknown purchases are ignored', () {
      final costs = landedCosts(
        items: [item('a', 'p1', 100)],
        shippingLines: const [
          CostShippingLine(id: 'l', cargoTypeId: general, costZmw: 50, purchaseIds: ['gone']),
        ],
        collections: const [CostCollection(id: 'c', costZmw: 50, purchaseIds: [])],
      );
      expect(costs['a']!.totalZmw, 100);
    });

    test('duplicate purchase ids on a line count once', () {
      final costs = landedCosts(
        items: [item('a', 'p1', 100), item('b', 'p2', 100)],
        shippingLines: const [
          CostShippingLine(id: 'l', cargoTypeId: general, costZmw: 100, purchaseIds: ['p1', 'p1', 'p2']),
        ],
      );
      expect(costs['a']!.shippingZmw, 50);
      expect(costs['b']!.shippingZmw, 50);
    });
  });
}
