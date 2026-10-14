import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../data/purchase_repository.dart';
import '../shipping/bill_edit_screen.dart';
import '../shipping/shipments_view.dart';
import 'purchase_detail_screen.dart';
import 'purchase_edit_screen.dart';
import 'purchase_labels.dart';

enum _BuyView { purchases, shipments, products }

class BuyScreen extends ConsumerStatefulWidget {
  const BuyScreen({super.key});

  @override
  ConsumerState<BuyScreen> createState() => _BuyScreenState();
}

class _BuyScreenState extends ConsumerState<BuyScreen> {
  var _view = _BuyView.purchases;
  var _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: switch (_view) {
        _BuyView.purchases => FloatingActionButton.extended(
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PurchaseEditScreen())),
          icon: const Icon(Icons.add),
          label: const Text('New purchase'),
        ),
        _BuyView.shipments => FloatingActionButton.extended(
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BillEditScreen())),
          icon: const Icon(Icons.add),
          label: const Text('Shipping bill'),
        ),
        _BuyView.products => null,
      },
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<_BuyView>(
              segments: const [
                ButtonSegment(value: _BuyView.purchases, label: Text('Purchases')),
                ButtonSegment(value: _BuyView.shipments, label: Text('Shipping')),
                ButtonSegment(value: _BuyView.products, label: Text('Products')),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.single),
            ),
          ),
          if (_view != _BuyView.shipments)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: InputDecoration(
                  hintText: _view == _BuyView.purchases
                      ? 'Search item, seller or tracking no.'
                      : 'Search products',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: switch (_view) {
              _BuyView.purchases => _PurchaseList(query: _query),
              _BuyView.shipments => const ShipmentsView(),
              _BuyView.products => _ProductList(query: _query),
            },
          ),
        ],
      ),
    );
  }
}

class _PurchaseList extends ConsumerWidget {
  const _PurchaseList({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(purchasesProvider).value;
    if (all == null) return const Center(child: CircularProgressIndicator());
    if (all.isEmpty) {
      return const EmptyState(
        icon: Icons.shopping_bag_outlined,
        title: 'No purchases yet',
        message: 'Log what you buy on Taobao, 1688 and the rest, with what your card was actually charged.',
      );
    }
    final matches = all.where((p) => p.matches(query)).toList();
    if (matches.isEmpty) {
      return const EmptyState(icon: Icons.search_off, title: 'Nothing matches your search');
    }

    // Group by status in journey order, so what needs attention is on top.
    final groups = <PurchaseStatus, List<PurchaseSummary>>{};
    for (final status in PurchaseStatus.values) {
      final inStatus = matches.where((p) => p.purchase.status == status).toList();
      if (inStatus.isNotEmpty) groups[status] = inStatus;
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final MapEntry(key: status, value: purchases) in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              '${purchaseStatusLabels[status]} · ${purchases.length}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          for (final summary in purchases) _PurchaseTile(summary: summary),
        ],
      ],
    );
  }
}

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({required this.summary});

  final PurchaseSummary summary;

  @override
  Widget build(BuildContext context) {
    final p = summary.purchase;
    final names = summary.itemNames;
    final title = names.isEmpty
        ? 'Purchase'
        : names.length <= 2
        ? names.join(', ')
        : '${names.take(2).join(', ')} +${names.length - 2} more';
    final subtitle = [
      shortDate.format(p.orderedAt),
      if (summary.platformName != null) summary.platformName!,
      '${summary.units} ${summary.units == 1 ? 'unit' : 'units'}',
    ].join(' · ');

    return ListTile(
      leading: Icon(purchaseStatusIcon(p.status)),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      trailing: Text(Money(p.paidZmw).toString(), style: Theme.of(context).textTheme.titleSmall),
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => PurchaseDetailScreen(purchaseId: p.id))),
    );
  }
}

class _ProductList extends ConsumerWidget {
  const _ProductList({required this.query});

  final String query;

  Future<void> _rename(BuildContext context, WidgetRef ref, Product product) async {
    final name = await promptForText(context, title: 'Rename product', label: 'Name', initial: product.name);
    if (name != null) await ref.read(purchaseRepositoryProvider).renameProduct(product.id, name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(productsProvider).value;
    final ledger = ref.watch(stockLedgerProvider).value;
    if (all == null) return const Center(child: CircularProgressIndicator());
    if (all.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No products yet',
        message: 'Products are created automatically when you log a purchase.',
      );
    }
    final q = query.trim().toLowerCase();
    final matches = all.where((p) => p.product.name.toLowerCase().contains(q)).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final summary in matches)
          ListTile(
            title: Text(summary.product.name),
            subtitle: Text(
              [
                if (ledger != null) '${ledger.stockOf(summary.product.id).qty} in stock',
                if (ledger?.stockOf(summary.product.id).unitCostZmw case final unit?)
                  'cost ${Money(unit)} each',
                if (summary.unitsOnTheWay > 0) '${summary.unitsOnTheWay} on the way',
              ].join(' · '),
            ),
            onTap: () => _rename(context, ref, summary.product),
          ),
      ],
    );
  }
}
