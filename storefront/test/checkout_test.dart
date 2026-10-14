import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow_shop/domain/checkout.dart';
import 'package:tradeflow_shop/domain/models.dart';
import 'package:tradeflow_shop/domain/money.dart';

import 'fixtures.dart';

void main() {
  test('kwacha formatting', () {
    expect(kwacha(45000), 'K450');
    expect(kwacha(16299), 'K162.99');
    expect(kwacha(123456700), 'K1,234,567');
    expect(kwacha(-3000), '-K30');
  });

  test('cart is priced from the catalog; sold-out and missing items drop out', () {
    final lines = priceLines(const [
      CartLine(productId: 'p1', qty: 2),
      CartLine(productId: 'p2', size: 'L', color: 'Black', qty: 1),
      CartLine(productId: 'p3', qty: 1),
      CartLine(productId: 'gone', qty: 1),
    ], testCatalog);
    expect(lines.map((l) => (l.name, l.qty, l.totalZmw, l.preOrder)), [
      ('Naruto Sage Mode Figure', 2, 90000, false),
      ('Gojo Hoodie', 1, 38000, true),
    ]);
  });

  test('totals with delivery and pre-order deposit', () {
    final lines = priceLines(const [
      CartLine(productId: 'p1', qty: 1),
      CartLine(productId: 'p2', qty: 1),
    ], testCatalog);
    final totals = totalsFor(lines, testSettings, areaId: 'cbd');
    expect(totals.itemsZmw, 83000);
    expect(totals.deliveryZmw, 3000);
    expect(totals.totalZmw, 86000);
    expect(totals.depositZmw, 19000, reason: '50% of the K380 hoodie');
    expect(totals.units, 2);
  });

  test('deposit rounds up to whole kwacha', () {
    const line = OrderLine(productId: 'x', name: 'x', qty: 1, unitPriceZmw: 3333, preOrder: true);
    expect(depositFor(const [line], 50), 1700);
    expect(depositFor(const [line], 0), 0);
  });

  test('order codes are short and unambiguous', () {
    final code = newOrderCode(Random(1));
    expect(code, matches(RegExp(r'^TF-[A-HJ-NP-Z2-9]{4}$')));
  });

  test('Zambian phone numbers normalise to international digits', () {
    expect(normalisePhone('097 123 4567'), '260971234567');
    expect(normalisePhone('+260 96 1234567'), '260961234567');
    expect(normalisePhone('771234567'), '260771234567');
    expect(normalisePhone('12345'), isNull);
    expect(normalisePhone('0211234567'), isNull);
  });

  test('WhatsApp message reads like a clear order', () {
    final lines = priceLines(const [
      CartLine(productId: 'p1', qty: 2),
      CartLine(productId: 'p2', size: 'L', color: 'Black', qty: 1),
    ], testCatalog);
    final order = buildOrder(
      code: 'TF-7K3Q',
      now: DateTime(2026, 10, 14),
      customer: const Customer(name: 'Mwila', phone: '260971234567', areaId: 'cbd', notes: ' Call first '),
      lines: lines,
      settings: testSettings,
    );
    expect(whatsappMessage(order, testSettings), '''
Hi Otaku Corner! I'd like to order (TF-7K3Q):

• 2 × Naruto Sage Mode Figure: K900
• 1 × Gojo Hoodie (Size L, Black) [Pre-order ~3 weeks]: K380

Items: K1,280
Delivery (Lusaka CBD): K30
Total: K1,310
Pre-order deposit (50%): K190

Name: Mwila
Phone: +260971234567
Notes: Call first''');

    final link = whatsappLink(order, testSettings);
    expect(link.host, 'wa.me');
    expect(link.path, '/260971234567');
    expect(link.queryParameters['text'], startsWith("Hi Otaku Corner!"));
  });
}
