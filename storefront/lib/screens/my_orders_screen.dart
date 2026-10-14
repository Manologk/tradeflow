import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../domain/models.dart';
import '../domain/money.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';

const orderStatusLabels = {
  OrderStatus.received: 'Received',
  OrderStatus.confirmed: 'Confirmed',
  OrderStatus.ready: 'Ready',
  OrderStatus.delivered: 'Delivered',
  OrderStatus.cancelled: 'Cancelled',
};

/// Latest status of every order placed from this device.
final orderStatusesProvider = FutureProvider<Map<String, OrderStatus>>((ref) async {
  final orders = ref.watch(placedOrdersProvider);
  final repo = ref.watch(shopRepositoryProvider);
  final byPhone = <String, List<String>>{};
  for (final o in orders) {
    byPhone.putIfAbsent(o.phone, () => []).add(o.code);
  }
  final result = <String, OrderStatus>{};
  for (final MapEntry(key: phone, value: codes) in byPhone.entries) {
    result.addAll(await repo.orderStatuses(codes, phone));
  }
  return result;
});

class MyOrdersScreen extends ConsumerWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(placedOrdersProvider);
    final statuses = ref.watch(orderStatusesProvider);
    final date = DateFormat('d MMM yyyy');

    return SafeArea(
      bottom: false,
      child: orders.isEmpty
          ? EmptyMessage(
              icon: Icons.receipt_long_outlined,
              title: 'No orders yet',
              message: 'Orders you place from this phone show up here.',
              action: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(200, 52)),
                onPressed: () => context.go('/'),
                child: const Text('Start shopping'),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(orderStatusesProvider.future),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, bottomBarClearance),
                children: [
                  const Text('My orders', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  for (final o in orders)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFEDEDED)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  o.code,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${date.format(o.createdAt)} · ${o.units} ${o.units == 1 ? 'item' : 'items'} · ${kwacha(o.totalZmw)}',
                                  style: const TextStyle(color: ShopColors.grey),
                                ),
                              ],
                            ),
                          ),
                          _StatusPill(status: statuses.value?[o.code], loading: statuses.isLoading),
                        ],
                      ),
                    ),
                  if (statuses.hasError)
                    const Text(
                      "Couldn't check the latest status. Pull down to try again.",
                      style: TextStyle(color: ShopColors.grey),
                    ),
                ],
              ),
            ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.loading});

  final OrderStatus? status;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final label = status == null ? (loading ? 'Checking…' : 'Sent') : orderStatusLabels[status]!;
    final dark = status == OrderStatus.delivered || status == OrderStatus.ready;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: ShapeDecoration(
        color: dark ? ShopColors.ink : ShopColors.surface,
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: dark ? Colors.white : ShopColors.inkDeep,
        ),
      ),
    );
  }
}
