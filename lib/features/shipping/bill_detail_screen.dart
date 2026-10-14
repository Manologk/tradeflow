import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/units.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../data/purchase_repository.dart';
import '../purchases/purchase_detail_screen.dart';
import '../purchases/purchase_labels.dart';
import 'bill_edit_screen.dart';

class BillDetailScreen extends ConsumerWidget {
  const BillDetailScreen({super.key, required this.billId});

  final String billId;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this bill?'),
        content: const Text('Its shipping cost is removed from the items it covered.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(shippingRepositoryProvider).deleteBill(billId);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bills = ref.watch(shippingBillsProvider).value;
    final bill = bills?.where((b) => b.bill.id == billId).firstOrNull;
    final purchases = {
      for (final p in ref.watch(purchasesProvider).value ?? const <PurchaseSummary>[]) p.purchase.id: p,
    };
    final cargoNames = {
      for (final c in ref.watch(lookupsProvider(LookupKind.cargoType)).value ?? const <Lookup>[])
        c.id: c.name,
    };

    if (bills == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (bill == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Bill not found')),
      );
    }

    final b = bill.bill;
    return Scaffold(
      appBar: AppBar(
        title: Text(bill.agent.name),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => BillEditScreen(existing: bill))),
          ),
          PopupMenuButton<String>(
            onSelected: (_) => _delete(context, ref),
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete'))],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(Money(b.paidZmw).toString(), style: theme.textTheme.headlineMedium),
          Text(
            [
              Money(b.totalUsd, Currency.usd).toString(),
              if (b.totalUsd > 0) 'K${(b.paidZmw / b.totalUsd).toStringAsFixed(3)} per \$1',
              'from ${bill.moneyPlace.name}',
            ].join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
          ),
          Text(
            '${shortDate.format(b.billedAt)} · ${formatKg(bill.weightGrams)}',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          for (final (i, line) in bill.lines.indexed)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Line ${i + 1} · ${cargoNames[line.line.cargoTypeId] ?? ''}',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        Text(Money(line.costZmw).toString(), style: theme.textTheme.titleSmall),
                      ],
                    ),
                    Text(
                      '${formatKg(line.line.weightGrams)} · ${Money(line.line.amountUsd, Currency.usd)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    for (final id in line.purchaseIds) _PurchaseLink(summary: purchases[id]),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PurchaseLink extends StatelessWidget {
  const _PurchaseLink({required this.summary});

  final PurchaseSummary? summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s == null) return const SizedBox.shrink();
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(purchaseStatusIcon(s.purchase.status), size: 20),
      title: Text(s.itemNames.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(s.trackingNumbers.join(', ')),
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => PurchaseDetailScreen(purchaseId: s.purchase.id))),
    );
  }
}
