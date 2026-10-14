import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/providers.dart';

/// Home dashboard. For now only "Money now" has data; the other tiles arrive
/// with purchases, sales and reports.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final balances = ref.watch(balancesProvider).value ?? const [];
    final active = balances.where((b) => !b.place.archived).toList();
    final total = active.fold<int>(0, (sum, b) => sum + b.balanceZmw);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Money now', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(Money(total).toString(), style: theme.textTheme.headlineMedium),
                const SizedBox(height: 12),
                for (final b in active)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(b.place.name)),
                        Text(Money(b.balanceZmw).toString()),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
