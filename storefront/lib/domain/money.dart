import 'package:intl/intl.dart';

final _grouped = NumberFormat('#,##0.00', 'en_US');
final _whole = NumberFormat('#,##0', 'en_US');

/// Formats ngwee as kwacha: 16299 -> "K162.99", 50000 -> "K500".
/// Whole amounts drop the decimals, which is how prices are usually shown.
String kwacha(int ngwee) {
  final sign = ngwee < 0 ? '-' : '';
  final abs = ngwee.abs();
  final text = abs % 100 == 0 ? _whole.format(abs ~/ 100) : _grouped.format(abs / 100);
  return '${sign}K$text';
}
