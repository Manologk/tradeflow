import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/database.dart';
import 'data/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(AppDatabase.open())],
    child: const TradeFlowApp(),
  ));
}
