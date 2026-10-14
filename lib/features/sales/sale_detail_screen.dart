import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../data/sales_repository.dart';
import '../../domain/fifo.dart';
import '../purchases/purchase_detail_screen.dart';
import '../purchases/purchase_labels.dart';
import 'payment_dialog.dart';
import 'sale_edit_screen.dart';

class SaleDetailScreen extends ConsumerWidget {
  const SaleDetailScreen({super.key, required this.saleId});

  final String saleId;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this sale?'),
        content: const Text(
          'Use this for a sale entered by mistake. Its payments are removed and the items go back into stock.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(salesRepositoryProvider).deleteSale(saleId);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _pay(BuildContext context, WidgetRef ref, SaleDetail d) async {
    final input = await askForPayment(context, title: 'Record payment', owedZmw: d.summary.owedZmw);
    if (input == null) return;
    await ref
        .read(salesRepositoryProvider)
        .addPayment(
          saleId: saleId,
          amountZmw: input.amountZmw,
          moneyPlaceId: input.moneyPlaceId,
          paidAt: DateTime.now(),
        );
  }

  Future<void> _deletePayment(BuildContext context, WidgetRef ref, Payment payment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove payment of ${Money(payment.amountZmw)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true) await ref.read(salesRepositoryProvider).deletePayment(payment.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(saleDetailProvider(saleId));
    final ledger = ref.watch(stockLedgerProvider).value;
    return switch (detail) {
      AsyncData(value: final d?) => _view(context, ref, d, ledger),
      AsyncData() => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Sale not found')),
      ),
      AsyncError(:final error) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('$error')),
      ),
      _ => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
    };
  }

  Widget _view(BuildContext context, WidgetRef ref, SaleDetail d, StockLedger? ledger) {
    final theme = Theme.of(context);
    final s = d.summary;
    final fulfilled = d.sale.status == SaleStatus.fulfilled;
    final costs = [for (final i in d.items) ledger?.demandCosts[i.item.id]];
    final totalCost = costs.fold<int>(0, (sum, c) => sum + (c?.costZmw ?? 0));
    final incomplete = costs.any((c) => c != null && !c.isComplete);
    final outline = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.customer?.name ?? 'Sale'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => SaleEditScreen(existing: d))),
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
          Text(Money(s.totalZmw).toString(), style: theme.textTheme.headlineMedium),
          Text(
            [
              shortDate.format(d.sale.soldAt),
              if (s.channelName != null) s.channelName!,
              if (s.customer?.phone != null) s.customer!.phone!,
            ].join(' · '),
            style: outline,
          ),
          const SizedBox(height: 12),
          if (s.isPendingPreOrder)
            Card(
              child: ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Pre-order waiting'),
                subtitle: const Text('Link the purchase you make for it, then mark it delivered.'),
                trailing: FilledButton(
                  onPressed: () => ref.read(salesRepositoryProvider).markFulfilled(saleId, DateTime.now()),
                  child: const Text('Delivered'),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text('Items', style: theme.textTheme.titleMedium),
          for (final (i, item) in d.items.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.product.name),
              subtitle: Text(
                [
                  '${item.item.qty} × ${Money(item.item.unitPriceZmw)}',
                  if (fulfilled && costs[i] != null) 'cost ${Money(costs[i]!.costZmw)}',
                ].join(' · '),
              ),
              trailing: Text(Money(item.item.qty * item.item.unitPriceZmw).toString()),
            ),
          if (fulfilled && ledger != null) ...[
            const Divider(),
            _row(theme, 'Sold for', Money(s.totalZmw)),
            _row(theme, 'Cost of goods', Money(totalCost)),
            _row(theme, 'Profit', Money(s.totalZmw - totalCost), bold: true),
            if (incomplete)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Some units had no recorded stock, so their cost is missing and profit is overstated. '
                  'Log the purchase they came from, or add opening stock.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Text('Payments', style: theme.textTheme.titleMedium)),
              if (s.owedZmw > 0)
                TextButton.icon(
                  onPressed: () => _pay(context, ref, d),
                  icon: const Icon(Icons.add),
                  label: const Text('Record payment'),
                ),
            ],
          ),
          if (d.payments.isEmpty) Text('Nothing received yet.', style: outline),
          for (final (payment, place) in d.payments)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(Money(payment.amountZmw).toString()),
              subtitle: Text('${shortDate.format(payment.paidAt)} · ${place.name}'),
              trailing: IconButton(
                tooltip: 'Remove payment',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deletePayment(context, ref, payment),
              ),
            ),
          if (s.owedZmw > 0)
            Text(
              'Still owed: ${Money(s.owedZmw)}',
              style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error),
            ),
          if (d.linkedPurchases.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Bought for this order', style: theme.textTheme.titleMedium),
            for (final p in d.linkedPurchases)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(purchaseStatusIcon(p.status)),
                title: Text(purchaseStatusLabels[p.status]!),
                subtitle: Text('${shortDate.format(p.orderedAt)} · ${Money(p.paidZmw)}'),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => PurchaseDetailScreen(purchaseId: p.id))),
              ),
          ],
          if (d.sale.notes != null) ...[const SizedBox(height: 16), Text(d.sale.notes!)],
        ],
      ),
    );
  }

  Widget _row(ThemeData theme, String label, Money value, {bool bold = false}) {
    final style = bold ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            value.toString(),
            style: style?.copyWith(color: bold && value.isNegative ? theme.colorScheme.error : null),
          ),
        ],
      ),
    );
  }
}
