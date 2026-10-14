/// Parses a weight in kg such as "1.25" into grams. Null if invalid.
int? parseKgToGrams(String input) {
  final cleaned = input.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{0,3})?$').hasMatch(cleaned)) return null;
  final parts = cleaned.split('.');
  final fraction = parts.length > 1 ? parts[1].padRight(3, '0') : '000';
  return int.parse(parts[0]) * 1000 + int.parse(fraction);
}

/// 1250 -> "1.25 kg", 3000 -> "3 kg".
String formatKg(int grams) {
  final text = (grams / 1000).toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  return '$text kg';
}

/// Editable kg text, e.g. 1250 -> "1.25", 0 -> "".
String editableKg(int grams) => grams == 0 ? '' : formatKg(grams).replaceAll(' kg', '');
