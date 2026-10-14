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
    final places = ref.watch(moneyPlacesProvider).value ?? const [];
    final active = places.where((p) => !p.archived).toList();
    final total = active.fold<int>(0, (sum, p) => sum + p.openingBalanceZmw);

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
                for (final place in active)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(place.name)),
                        Text(Money(place.openingBalanceZmw).toString()),
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
