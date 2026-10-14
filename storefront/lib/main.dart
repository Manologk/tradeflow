import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Format money and dates the same way whatever language the visitor's
  // browser reports (some report locales intl doesn't know).
  Intl.defaultLocale = 'en_US';
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(overrides: [preferencesProvider.overrideWithValue(prefs)], child: const ShopApp()));
}
