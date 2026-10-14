import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/widgets.dart';
import '../../data/money_repository.dart';
import '../../data/providers.dart';

/// Type what is really in each place; differences are recorded so the app's
/// balances match reality again.
class BalanceCheckScreen extends ConsumerStatefulWidget {
  const BalanceCheckScreen({super.key});

  @override
  ConsumerState<BalanceCheckScreen> createState() => _BalanceCheckScreenState();
}

class _BalanceCheckScreenState extends ConsumerState<BalanceCheckScreen> {
  final _formKey = GlobalKey<FormState>();
  final _actual = <String, TextEditingController>{};
  var _saving = false;

  @override
  void dispose() {
    for (final c in _actual.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(String placeId) {
    return _actual.putIfAbsent(placeId, () {
      final c = TextEditingController();
      c.addListener(() => setState(() {}));
      return c;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final entered = {
      for (final MapEntry(:key, :value) in _actual.entries)
        if (value.text.trim().isNotEmpty) key: moneyFromController(value),
    };
    if (entered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter at least one balance')));
      return;
    }
    setState(() => _saving = true);
    await ref.read(moneyRepositoryProvider).recordBalanceCheck(entered);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balances = (ref.watch(balancesProvider).value ?? const <PlaceBalance>[])
        .where((b) => !b.place.archived)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Check balances')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Look at your card, mobile money and cash, and type what is really there. '
              'Leave a place blank to skip it.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Any difference is recorded as "taken out / unrecorded". It does not count against your profit, '
              'and you can say later what it was.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 24),
            for (final b in balances) ...[
              Text(b.place.name, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              MoneyField(
                controller: _controller(b.place.id),
                label: 'Actually there',
                helperText: 'App expects ${Money(b.balanceZmw)}${_gapText(b)}',
              ),
              const SizedBox(height: 20),
            ],
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Save balances')),
          ],
        ),
      ),
    );
  }

  String _gapText(PlaceBalance b) {
    final text = _actual[b.place.id]?.text.trim() ?? '';
    final actual = Money.parseMinor(text);
    if (actual == null) return '';
    final gap = actual - b.balanceZmw;
    if (gap == 0) return ' · matches';
    return gap < 0 ? ' · ${Money(-gap)} less' : ' · ${Money(gap)} more';
  }
}
