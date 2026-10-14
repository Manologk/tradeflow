import 'package:flutter/material.dart';

/// Colours and type from the ChicCraze style guide (see docs/STOREFRONT_SPEC.md).
abstract final class ShopColors {
  static const ink = Color(0xFF292526);
  static const inkDeep = Color(0xFF121111);
  static const grey = Color(0xFF787676);
  static const greyLight = Color(0xFFA3A1A2);
  static const surface = Color(0xFFF2F2F2);
  static const star = Color(0xFFFFC107);
  static const sale = Color(0xFFD64545);
}

ThemeData shopTheme() {
  const scheme = ColorScheme.light(
    primary: ShopColors.ink,
    onPrimary: Colors.white,
    secondary: ShopColors.grey,
    surface: Colors.white,
    onSurface: ShopColors.inkDeep,
    surfaceContainerHighest: ShopColors.surface,
    outline: ShopColors.greyLight,
    outlineVariant: Color(0xFFE6E5E5),
    error: ShopColors.sale,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'EncodeSans');
  return base.copyWith(
    scaffoldBackgroundColor: Colors.white,
    textTheme: base.textTheme.apply(bodyColor: ShopColors.inkDeep, displayColor: ShopColors.inkDeep),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: ShopColors.greyLight),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE6E5E5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE6E5E5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: ShopColors.ink, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: 'EncodeSans', fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: const StadiumBorder(side: BorderSide(color: Color(0xFFE6E5E5))),
      side: const BorderSide(color: Color(0xFFE6E5E5)),
      backgroundColor: Colors.white,
      selectedColor: ShopColors.ink,
      labelStyle: const TextStyle(fontFamily: 'EncodeSans', color: ShopColors.inkDeep),
      secondaryLabelStyle: const TextStyle(fontFamily: 'EncodeSans', color: Colors.white),
      checkmarkColor: Colors.white,
      showCheckmark: false,
    ),
  );
}
