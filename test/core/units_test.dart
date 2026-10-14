import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/core/units.dart';

void main() {
  test('parses kg into grams', () {
    expect(parseKgToGrams('1.25'), 1250);
    expect(parseKgToGrams('3'), 3000);
    expect(parseKgToGrams('0,5'), 500);
    expect(parseKgToGrams('0.125'), 125);
    expect(parseKgToGrams('1.2345'), isNull);
    expect(parseKgToGrams('abc'), isNull);
    expect(parseKgToGrams(''), isNull);
  });

  test('formats grams as kg', () {
    expect(formatKg(1250), '1.25 kg');
    expect(formatKg(3000), '3 kg');
    expect(formatKg(125), '0.125 kg');
    expect(editableKg(1250), '1.25');
    expect(editableKg(0), '');
  });
}
