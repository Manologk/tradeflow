import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/core/money.dart';

void main() {
  group('Money.parseMinor', () {
    test('parses plain, grouped and symbol-prefixed amounts', () {
      expect(Money.parseMinor('1184.50'), 118450);
      expect(Money.parseMinor('1,184.5'), 118450);
      expect(Money.parseMinor('K 300'), 30000);
      expect(Money.parseMinor('¥32'), 3200);
      expect(Money.parseMinor('0.07'), 7);
    });

    test('rejects invalid input', () {
      expect(Money.parseMinor(''), isNull);
      expect(Money.parseMinor('abc'), isNull);
      expect(Money.parseMinor('1.234'), isNull);
      expect(Money.parseMinor('-5'), isNull);
      expect(Money.parseMinor('1.2.3'), isNull);
    });
  });

  test('formats with symbol and grouping', () {
    expect(const Money(118450).toString(), 'K1,184.50');
    expect(const Money(-1200).toString(), '-K12.00');
    expect(const Money(32000, Currency.cny).toString(), '¥320.00');
    expect(const Money(1080, Currency.usd).toString(), r'$10.80');
  });

  test('editable text round-trips through parse', () {
    expect(Money.editable(0), '');
    expect(Money.editable(118450), '1184.50');
    expect(Money.parseMinor(Money.editable(118450)), 118450);
  });

  test('arithmetic refuses to mix currencies', () {
    expect(const Money(100) + const Money(50), const Money(150));
    expect(() => const Money(100) + const Money(50, Currency.usd), throwsArgumentError);
  });
}
