import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/providers.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/shell_screen.dart';

class TradeFlowApp extends StatelessWidget {
  const TradeFlowApp({super.key});

  static const _seed = Color(0xFF0F766E);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TradeFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: const _Root(),
    );
  }
}

/// Shows first-run setup until a store exists, then the main app.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider);
    return switch (store) {
      AsyncData(value: null) => const OnboardingScreen(),
      AsyncData() => const ShellScreen(),
      AsyncError(:final error) => Scaffold(body: Center(child: Text('Could not open data: $error'))),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}
