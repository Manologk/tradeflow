import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../data/purchase_repository.dart';
import '../../domain/costing.dart';
import 'purchase_edit_screen.dart';
import 'purchase_labels.dart';

class PurchaseDetailScreen extends ConsumerWidget {
  const PurchaseDetailScreen({super.key, required this.purchaseId});

  final String purchaseId;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this purchase?'),
        content: const Text(
          'Use this for a purchase entered by mistake. '
          'For a refunded order, use Refund instead (coming soon) so the money is tracked.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(purchaseRepositoryProvider).deletePurchase(purchaseId);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(purchaseDetailProvider(purchaseId));
    return switch (detail) {
      AsyncData(value: final d?) => _DetailView(
        detail: d,
        landed: ref.watch(landedCostsProvider).value ?? const {},
        onEdit: () =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => PurchaseEditScreen(existing: d))),
        onDelete: () => _delete(context, ref),
        onStatus: (s) => ref.read(purchaseRepositoryProvider).setStatus(purchaseId, s),
      ),
      AsyncData() => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Purchase not found')),
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
}

class _DetailView extends StatelessWidget {
  const _DetailView({
    required this.detail,
    required this.landed,
    required this.onEdit,
    required this.onDelete,
    required this.onStatus,
  });

  final PurchaseDetail detail;
  final Map<String, ItemLandedCost> landed;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<PurchaseStatus> onStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = detail.purchase;
    final rate = effectiveRate(paidZmw: p.paidZmw, totalCny: p.totalCny);
    final canSetStatus = manualPurchaseStatuses.contains(p.status);
    final hasShipping = detail.items.any((i) => (landed[i.item.id]?.shippingZmw ?? 0) > 0);

    return Scaffold(
      appBar: AppBar(
        title: Text(detail.platform?.name ?? 'Purchase'),
        actions: [
          IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
          PopupMenuButton<String>(
            onSelected: (_) => onDelete(),
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete'))],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(Money(p.paidZmw).toString(), style: theme.textTheme.headlineMedium),
          Text(
            [
              Money(p.totalCny, Currency.cny).toString(),
              if (rate != null) rateLabel(rate),
              'from ${detail.moneyPlace.name}',
            ].join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 4),
          Text(
            [shortDate.format(p.orderedAt), if (p.sellerName != null) p.sellerName!].join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          if (canSetStatus)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in manualPurchaseStatuses)
                  ChoiceChip(
                    avatar: Icon(purchaseStatusIcon(s), size: 18),
                    label: Text(purchaseStatusLabels[s]!),
                    selected: p.status == s,
                    onSelected: (_) => onStatus(s),
                  ),
              ],
            )
          else
            Chip(
              avatar: Icon(purchaseStatusIcon(p.status), size: 18),
              label: Text(purchaseStatusLabels[p.status]!),
            ),
          const SizedBox(height: 24),
          Text('Items', style: theme.textTheme.titleMedium),
          for (final item in detail.items) _ItemTile(item: item, landed: landed[item.item.id]),
          if (!hasShipping)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Shipping is added to these costs when you enter the agent\'s bill.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          if (detail.sellerDeliveryCny > 0)
            Text(
              "Seller's delivery ${Money(detail.sellerDeliveryCny, Currency.cny)} is spread across the items.",
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          const SizedBox(height: 24),
          Text('Tracking numbers', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (detail.trackingNumbers.isEmpty)
            Text('None yet — edit to add when the seller ships.', style: theme.textTheme.bodyMedium)
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [for (final t in detail.trackingNumbers) Chip(label: Text(t))],
            ),
          if (p.orderRef != null || p.notes != null) ...[
            const SizedBox(height: 24),
            if (p.orderRef != null) Text('Order no. ${p.orderRef}'),
            if (p.notes != null) Text(p.notes!),
          ],
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.landed});

  final PurchaseItemDetail item;
  final ItemLandedCost? landed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cost = landed;
    final qty = item.item.qty;
    final extras = cost == null ? 0 : cost.shippingZmw + cost.collectionZmw;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(item.product.name, style: theme.textTheme.titleSmall)),
              Text(
                cost == null ? Money(item.costZmw).toString() : '${Money(cost.unitZmw)} each',
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          Text(
            '$qty × ${Money(item.item.unitPriceCny, Currency.cny)} · paid ${Money(item.costZmw)}',
            style: theme.textTheme.bodySmall,
          ),
          if (cost != null && extras > 0)
            Text(
              [
                if (cost.shippingZmw > 0) 'shipping ${Money(cost.shippingZmw)}',
                if (cost.collectionZmw > 0) 'pickup ${Money(cost.collectionZmw)}',
                'landed ${Money(cost.totalZmw)}',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
        ],
      ),
    );
  }
}
