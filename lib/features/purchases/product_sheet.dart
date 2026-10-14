import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/problems_repository.dart';
import '../../data/providers.dart';
import '../problems/problem_dialogs.dart';
import 'purchase_labels.dart';

/// Actions on one product: rename, take units out of stock, see write-offs.
Future<void> showProductSheet(BuildContext context, Product product) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _ProductSheet(productId: product.id),
);

class _ProductSheet extends ConsumerWidget {
  const _ProductSheet({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final product = ref
        .watch(productsProvider)
        .value
        ?.where((p) => p.product.id == productId)
        .firstOrNull
        ?.product;
    if (product == null) return const SizedBox(height: 120);
    final stock = ref.watch(stockLedgerProvider).value?.stockOf(productId);
    final writeOffs = ref.watch(writeOffsProvider(productId)).value ?? const <Adjustment>[];
    final ledger = ref.watch(stockLedgerProvider).value;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.name, style: theme.textTheme.titleLarge),
            if (stock != null)
              Text(
                [
                  '${stock.qty} in stock',
                  if (stock.unitCostZmw != null) 'cost ${Money(stock.unitCostZmw!)} each',
                  if (stock.qty > 0) 'worth ${Money(stock.valueZmw)}',
                ].join(' · '),
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
              ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () async {
                final name = await promptForText(
                  context,
                  title: 'Rename product',
                  label: 'Name',
                  initial: product.name,
                );
                if (name != null) await ref.read(purchaseRepositoryProvider).renameProduct(product.id, name);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Take out of stock'),
              subtitle: const Text('Damaged, kept for yourself or given away'),
              onTap: () => showWriteOffDialog(context, product: product, inStock: stock?.qty ?? 0),
            ),
            if (writeOffs.isNotEmpty) ...[
              const Divider(),
              Text('Taken out of stock', style: theme.textTheme.titleSmall),
              for (final w in writeOffs)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    '${w.qty} × ${writeOffReasonLabels[WriteOffReason.values.asNameMap()[w.reason]] ?? 'Other'}',
                  ),
                  subtitle: Text(
                    [
                      shortDate.format(w.occurredAt),
                      if (ledger?.demandCosts[w.id] case final cost?) 'cost ${Money(cost.costZmw)}',
                      if (w.note != null) w.note!,
                    ].join(' · '),
                  ),
                  trailing: w.saleId != null
                      ? null
                      : IconButton(
                          tooltip: 'Undo',
                          icon: const Icon(Icons.undo),
                          onPressed: () => ref.read(problemsRepositoryProvider).deleteAdjustment(w.id),
                        ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
