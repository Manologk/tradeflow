import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../data/sales_repository.dart';
import '../purchases/purchase_labels.dart';
import 'payment_dialog.dart';
import 'sale_detail_screen.dart';
import 'sale_edit_screen.dart';

enum _SellView { sales, owed }

class SellScreen extends ConsumerStatefulWidget {
  const SellScreen({super.key});

  @override
  ConsumerState<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends ConsumerState<SellScreen> {
  var _view = _SellView.sales;
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final owedTotal = (ref.watch(debtsProvider).value ?? const <CustomerDebt>[]).fold<int>(
      0,
      (sum, d) => sum + d.owedZmw,
    );
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SaleEditScreen())),
        icon: const Icon(Icons.add),
        label: const Text('New sale'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<_SellView>(
              segments: [
                const ButtonSegment(value: _SellView.sales, label: Text('Sales')),
                ButtonSegment(
                  value: _SellView.owed,
                  label: Text(owedTotal > 0 ? 'Owed ${Money(owedTotal)}' : 'Owed to me'),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.single),
            ),
          ),
          if (_view == _SellView.sales)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search item, customer or channel',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: switch (_view) {
              _SellView.sales => _SalesList(query: _query),
              _SellView.owed => const _OwedList(),
            },
          ),
        ],
      ),
    );
  }
}

class _SalesList extends ConsumerWidget {
  const _SalesList({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(salesProvider).value;
    if (all == null) return const Center(child: CircularProgressIndicator());
    if (all.isEmpty) {
      return const EmptyState(
        icon: Icons.sell_outlined,
        title: 'No sales yet',
        message: 'Record what you sell, including deposits on pre-orders and money still owed.',
      );
    }
    final matches = all.where((s) => s.matches(query)).toList();
    final waiting = matches.where((s) => s.isPendingPreOrder).toList();
    final done = matches.where((s) => !s.isPendingPreOrder).toList();
    final label = Theme.of(context).textTheme.labelLarge;

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        if (waiting.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Pre-orders waiting · ${waiting.length}', style: label),
          ),
          for (final s in waiting) _SaleTile(summary: s),
        ],
        if (done.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Sales', style: label),
          ),
          for (final s in done) _SaleTile(summary: s),
        ],
      ],
    );
  }
}

class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.summary});

  final SaleSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = summary.itemNames;
    final title = names.length <= 2
        ? names.join(', ')
        : '${names.take(2).join(', ')} +${names.length - 2} more';
    return ListTile(
      leading: Icon(summary.isPendingPreOrder ? Icons.schedule : Icons.sell_outlined),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          shortDate.format(summary.sale.soldAt),
          if (summary.customer != null) summary.customer!.name,
          if (summary.channelName != null) summary.channelName!,
        ].join(' · '),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(Money(summary.totalZmw).toString(), style: theme.textTheme.titleSmall),
          if (summary.owedZmw > 0)
            Text(
              'owes ${Money(summary.owedZmw)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
        ],
      ),
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => SaleDetailScreen(saleId: summary.sale.id))),
    );
  }
}

class _OwedList extends ConsumerWidget {
  const _OwedList();

  Future<void> _pay(BuildContext context, WidgetRef ref, CustomerDebt debt) async {
    final input = await askForPayment(
      context,
      title: 'Payment from ${debt.customer.name}',
      owedZmw: debt.owedZmw,
    );
    if (input == null) return;
    await ref
        .read(salesRepositoryProvider)
        .payDebt(
          debt: debt,
          amountZmw: input.amountZmw,
          moneyPlaceId: input.moneyPlaceId,
          paidAt: DateTime.now(),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref.watch(debtsProvider).value;
    if (debts == null) return const Center(child: CircularProgressIndicator());
    if (debts.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline,
        title: 'Nobody owes you money',
        message: 'Sales with a balance left show up here.',
      );
    }
    final theme = Theme.of(context);
    final now = DateTime.now();
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final d in debts)
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(d.customer.name),
            subtitle: Text(
              [
                '${d.sales.length} ${d.sales.length == 1 ? 'sale' : 'sales'}',
                'oldest ${now.difference(d.oldestSaleAt).inDays} days ago',
                if (d.customer.phone != null) d.customer.phone!,
              ].join(' · '),
            ),
            trailing: Text(
              Money(d.owedZmw).toString(),
              style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error),
            ),
            onTap: () => _pay(context, ref, d),
          ),
      ],
    );
  }
}
