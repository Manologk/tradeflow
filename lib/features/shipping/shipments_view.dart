import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/units.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../data/shipping_repository.dart';
import '../purchases/purchase_labels.dart';
import 'bill_detail_screen.dart';
import 'collect_screen.dart';

/// Shipping bills and collections, with a shortcut to collect arrived goods.
class ShipmentsView extends ConsumerWidget {
  const ShipmentsView({super.key});

  Future<void> _undoCollection(BuildContext context, WidgetRef ref, CollectionSummary c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Undo this collection?'),
        content: const Text('Its purchases go back to "on the way" and its pickup costs are removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Undo')),
        ],
      ),
    );
    if (confirmed == true) await ref.read(shippingRepositoryProvider).deleteCollection(c.collection.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bills = ref.watch(shippingBillsProvider).value;
    final collections = ref.watch(collectionsProvider).value;
    final purchases = ref.watch(purchasesProvider).value ?? const [];
    if (bills == null || collections == null) return const Center(child: CircularProgressIndicator());

    final waiting = purchases
        .where((p) => const [PurchaseStatus.inTransit, PurchaseStatus.atAgent].contains(p.purchase.status))
        .length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Collect arrived goods'),
              subtitle: Text(
                waiting == 0
                    ? 'Nothing billed is waiting'
                    : '$waiting ${waiting == 1 ? 'purchase' : 'purchases'} at the agent or on the way',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CollectScreen())),
            ),
          ),
        ),
        if (bills.isEmpty && collections.isEmpty)
          const EmptyState(
            icon: Icons.local_shipping_outlined,
            title: 'No shipping bills yet',
            message:
                'When your agent bills you, enter it here. Shipping is then added to what each item cost.',
          ),
        if (bills.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Shipping bills', style: theme.textTheme.labelLarge),
          ),
          for (final b in bills)
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text('${b.agent.name} · ${Money(b.bill.totalUsd, Currency.usd)}'),
              subtitle: Text(
                [
                  shortDate.format(b.bill.billedAt),
                  formatKg(b.weightGrams),
                  '${b.purchaseIds.length} ${b.purchaseIds.length == 1 ? 'purchase' : 'purchases'}',
                ].join(' · '),
              ),
              trailing: Text(Money(b.bill.paidZmw).toString(), style: theme.textTheme.titleSmall),
              onTap: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => BillDetailScreen(billId: b.bill.id))),
            ),
        ],
        if (collections.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Collections', style: theme.textTheme.labelLarge),
          ),
          for (final c in collections)
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(
                '${c.purchaseIds.length} ${c.purchaseIds.length == 1 ? 'purchase' : 'purchases'} collected',
              ),
              subtitle: Text(shortDate.format(c.collection.collectedAt)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c.costZmw > 0) Text(Money(c.costZmw).toString(), style: theme.textTheme.titleSmall),
                  PopupMenuButton<String>(
                    onSelected: (_) => _undoCollection(context, ref, c),
                    itemBuilder: (_) => const [PopupMenuItem(value: 'undo', child: Text('Undo collection'))],
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
