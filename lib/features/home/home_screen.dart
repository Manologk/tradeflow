import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/providers.dart';
import '../../data/report_repository.dart';
import '../../domain/reports.dart';

/// The five numbers that answer "how is the business doing?" (spec §7).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.onOpenTab});

  /// Switches the main tab: 1 Buy, 2 Sell, 3 Money, 4 Reports.
  final ValueChanged<int>? onOpenTab;

  static const transitWarningDays = 30;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(snapshotProvider);
    return switch (snapshot) {
      AsyncData(:final value) => _Dashboard(snapshot: value, onOpenTab: onOpenTab),
      AsyncError(:final error) => Center(child: Text('Could not load: $error')),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.snapshot, required this.onOpenTab});

  final BusinessSnapshot snapshot;
  final ValueChanged<int>? onOpenTab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final thisMonth = snapshot.report(monthStart(now), nextMonth(now));
    final lastMonthStart = DateTime(now.year, now.month - 1);
    final lastMonth = snapshot.report(lastMonthStart, monthStart(now));
    final transitDays = snapshot.oldestTransit == null
        ? null
        : now.difference(snapshot.oldestTransit!).inDays;
    final debtDays = snapshot.oldestDebt == null ? null : now.difference(snapshot.oldestDebt!).inDays;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline);
    final warn = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _Tile(
          title: 'Profit this month',
          value: Money(thisMonth.netProfitZmw),
          valueColor: thisMonth.netProfitZmw < 0 ? theme.colorScheme.error : null,
          onTap: () => onOpenTab?.call(4),
          lines: [
            Text(
              'Sold ${Money(thisMonth.totals.revenueZmw)} · goods cost ${Money(thisMonth.totals.costZmw)}',
              style: muted,
            ),
            Text('Last month: ${Money(lastMonth.netProfitZmw)}', style: muted),
            if (thisMonth.missingCostUnits > 0)
              Text('${thisMonth.missingCostUnits} units sold with no recorded cost', style: warn),
          ],
        ),
        _Tile(
          title: 'Money in transit',
          value: Money(snapshot.transitZmw),
          onTap: () => onOpenTab?.call(1),
          lines: [
            Text(
              snapshot.transitPurchases == 0
                  ? 'Nothing on the way'
                  : '${snapshot.transitPurchases} ${snapshot.transitPurchases == 1 ? 'purchase' : 'purchases'}'
                        ' · oldest bought $transitDays days ago',
              style: (transitDays ?? 0) > HomeScreen.transitWarningDays ? warn : muted,
            ),
          ],
        ),
        _Tile(
          title: 'Owed to you',
          value: Money(snapshot.owedZmw),
          onTap: () => onOpenTab?.call(2),
          lines: [
            Text(debtDays == null ? 'Nobody owes you' : 'Oldest debt $debtDays days old', style: muted),
          ],
        ),
        _Tile(
          title: 'Stock value',
          value: Money(snapshot.stockValueZmw),
          onTap: () => onOpenTab?.call(1),
          lines: [
            Text('${snapshot.stockUnits} units in stock, at what they cost you', style: muted),
            if (snapshot.slowMovers.isNotEmpty)
              Text(
                '${snapshot.slowMovers.length} not sold in ${ReportRepository.slowMoverDays}+ days: '
                '${snapshot.slowMovers.take(3).map((id) => snapshot.names[id] ?? '').join(', ')}'
                '${snapshot.slowMovers.length > 3 ? '…' : ''}',
                style: warn,
              ),
          ],
        ),
        _Tile(
          title: 'Money now',
          value: Money(snapshot.moneyNowZmw),
          onTap: () => onOpenTab?.call(3),
          lines: [
            for (final b in snapshot.balances.where((b) => !b.place.archived))
              Row(
                children: [
                  Expanded(child: Text(b.place.name, style: muted)),
                  Text(Money(b.balanceZmw).toString(), style: muted),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.title, required this.value, required this.lines, this.onTap, this.valueColor});

  final String title;
  final Money value;
  final List<Widget> lines;
  final VoidCallback? onTap;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(value.toString(), style: theme.textTheme.headlineMedium?.copyWith(color: valueColor)),
              const SizedBox(height: 4),
              ...lines,
            ],
          ),
        ),
      ),
    );
  }
}
