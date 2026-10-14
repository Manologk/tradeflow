import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/money_repository.dart';
import '../../data/providers.dart';
import '../purchases/purchase_detail_screen.dart';
import '../purchases/purchase_labels.dart';
import '../sales/sale_detail_screen.dart';
import '../shipping/bill_detail_screen.dart';
import 'balance_check_screen.dart';
import 'money_dialogs.dart';

const gapLabels = {
  BalanceGapLabel.unrecorded: 'Taken out / unrecorded',
  BalanceGapLabel.personal: 'Personal use',
  BalanceGapLabel.forgotExpense: 'Business expense I forgot to log',
};

class MoneyScreen extends ConsumerWidget {
  const MoneyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final balances = (ref.watch(balancesProvider).value ?? const <PlaceBalance>[])
        .where((b) => !b.place.archived)
        .toList();
    final movements = ref.watch(movementsProvider).value;
    final lastCheck = ref.watch(lastBalanceCheckProvider).value;
    final places = {for (final b in balances) b.place.id: b.place.name};
    final total = balances.fold<int>(0, (sum, b) => sum + b.balanceZmw);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Money now', style: theme.textTheme.titleMedium),
                Text(Money(total).toString(), style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                for (final b in balances)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(child: Text(b.place.name)),
                        Text(
                          Money(b.balanceZmw).toString(),
                          style: b.balanceZmw < 0 ? TextStyle(color: theme.colorScheme.error) : null,
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        lastCheck == null ? 'Balances never checked' : 'Last checked ${_daysAgo(lastCheck)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context)
                              .push(MaterialPageRoute<void>(builder: (_) => const BalanceCheckScreen())),
                      child: const Text('Check balances'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => showExpenseDialog(context),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Expense'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => showTransferDialog(context),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Move money'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Money in and out', style: theme.textTheme.titleMedium),
        if (movements == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (movements.isEmpty)
          const EmptyState(icon: Icons.account_balance_wallet_outlined, title: 'No money movements yet')
        else
          for (final m in movements) _MovementTile(movement: m, placeName: places[m.placeId] ?? ''),
      ],
    );
  }

  static String _daysAgo(DateTime at) {
    final days = DateTime.now().difference(at).inDays;
    return switch (days) {
      0 => 'today',
      1 => 'yesterday',
      _ => '$days days ago',
    };
  }
}

class _MovementTile extends ConsumerWidget {
  const _MovementTile({required this.movement, required this.placeName});

  final Movement movement;
  final String placeName;

  (IconData, String) get _look {
    final m = movement;
    return switch (m.kind) {
      MovementKind.purchase => (
        Icons.shopping_bag_outlined,
        'Purchase${m.label == null ? '' : ': ${m.label}'}',
      ),
      MovementKind.shipping => (
        Icons.local_shipping_outlined,
        'Shipping${m.label == null ? '' : ' · ${m.label}'}',
      ),
      MovementKind.pickup => (Icons.inventory_2_outlined, 'Pickup: transport & storage'),
      MovementKind.salePayment => (
        Icons.sell_outlined,
        'Sale payment${m.label == null ? '' : ' · ${m.label}'}',
      ),
      MovementKind.expense => (
        Icons.receipt_long_outlined,
        '${m.label}${m.detail == null ? '' : ' · ${m.detail}'}',
      ),
      MovementKind.transferOut => (Icons.north_east, 'Moved to ${m.label}'),
      MovementKind.transferIn => (Icons.south_west, 'Moved from ${m.label}'),
      MovementKind.adjustment => (
        Icons.rule,
        gapLabels[BalanceGapLabel.values.byName(m.label ?? 'unrecorded')] ?? 'Balance check',
      ),
    };
  }

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    final m = movement;
    final repo = ref.read(moneyRepositoryProvider);
    void open(Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    switch (m.kind) {
      case MovementKind.purchase:
        open(PurchaseDetailScreen(purchaseId: m.id));
      case MovementKind.shipping:
        open(BillDetailScreen(billId: m.id));
      case MovementKind.salePayment:
        if (m.detail != null) open(SaleDetailScreen(saleId: m.detail!));
      case MovementKind.pickup:
        break;
      case MovementKind.expense:
        if (await _confirm(context, 'Delete this expense?')) await repo.deleteExpense(m.id);
      case MovementKind.transferOut || MovementKind.transferIn:
        if (await _confirm(context, 'Delete this transfer?')) await repo.deleteTransfer(m.id);
      case MovementKind.adjustment:
        final choice = await showModalBottomSheet<Object>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('What was this difference?')),
                for (final MapEntry(:key, :value) in gapLabels.entries)
                  ListTile(title: Text(value), onTap: () => Navigator.pop(context, key)),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Remove this balance check'),
                  onTap: () => Navigator.pop(context, 'delete'),
                ),
              ],
            ),
          ),
        );
        if (choice is BalanceGapLabel) await repo.labelGap(m.id, choice);
        if (choice == 'delete') await repo.deleteBalanceCheck(m.id);
    }
  }

  Future<bool> _confirm(BuildContext context, String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (icon, title) = _look;
    final amount = movement.amountZmw;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${shortDate.format(movement.at)} · $placeName'),
      trailing: Text(
        '${amount > 0 ? '+' : ''}${Money(amount)}',
        style: theme.textTheme.titleSmall?.copyWith(color: amount > 0 ? theme.colorScheme.primary : null),
      ),
      onTap: () => _onTap(context, ref),
    );
  }
}
