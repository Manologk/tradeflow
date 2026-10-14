import 'package:intl/intl.dart';

enum Currency {
  zmw('ZMW', 'K'),
  cny('CNY', '¥'),
  usd('USD', r'$');

  const Currency(this.code, this.symbol);

  final String code;
  final String symbol;
}

/// An amount in minor units (ngwee, fen, cents). Money is never a double.
class Money implements Comparable<Money> {
  const Money(this.minor, [this.currency = Currency.zmw]);

  const Money.zero([this.currency = Currency.zmw]) : minor = 0;

  final int minor;
  final Currency currency;

  static final _grouped = NumberFormat('#,##0.00', 'en_US');
  static final _pattern = RegExp(r'^\d+(\.\d{0,2})?$');

  /// Parses user input such as "1,184.50", "K 300" or "¥32.5".
  /// Returns null when the text is not a valid non-negative amount.
  static int? parseMinor(String input) {
    final cleaned = input.replaceAll(RegExp(r'[\s,K¥$]'), '');
    if (cleaned.isEmpty || !_pattern.hasMatch(cleaned)) return null;
    final parts = cleaned.split('.');
    final whole = int.parse(parts[0]);
    final fraction = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
    return whole * 100 + int.parse(fraction);
  }

  static Money? parse(String input, [Currency currency = Currency.zmw]) {
    final minor = parseMinor(input);
    return minor == null ? null : Money(minor, currency);
  }

  /// Formats minor units without the symbol, e.g. 118450 -> "1,184.50".
  static String plain(int minor) => _grouped.format(minor / 100);

  /// Plain editable text, e.g. 118450 -> "1184.50", 0 -> "".
  static String editable(int minor) => minor == 0 ? '' : (minor / 100).toStringAsFixed(2);

  Money operator +(Money other) {
    _checkCurrency(other);
    return Money(minor + other.minor, currency);
  }

  Money operator -(Money other) {
    _checkCurrency(other);
    return Money(minor - other.minor, currency);
  }

  Money operator -() => Money(-minor, currency);

  bool get isNegative => minor < 0;

  void _checkCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError('Cannot mix ${currency.code} and ${other.currency.code}');
    }
  }

  @override
  int compareTo(Money other) {
    _checkCurrency(other);
    return minor.compareTo(other.minor);
  }

  @override
  bool operator ==(Object other) => other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  /// e.g. "K1,184.50", "-K12.00", "¥320.00".
  @override
  String toString() => '${isNegative ? '-' : ''}${currency.symbol}${plain(minor.abs())}';
}
