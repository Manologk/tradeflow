import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../data/shipping_repository.dart';
import '../purchases/purchase_labels.dart';

/// Record picking goods up from the agent. Ticked purchases become stock;
/// transport and storage are spread over them.
class CollectScreen extends ConsumerStatefulWidget {
  const CollectScreen({super.key});

  @override
  ConsumerState<CollectScreen> createState() => _CollectScreenState();
}

class _CollectScreenState extends ConsumerState<CollectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _transport = TextEditingController();
  final _storage = TextEditingController();
  final _selected = <String>{};
  List<OpenPurchase>? _open;
  var _collectedAt = DateTime.now();
  String? _moneyPlaceId;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    ref.read(shippingRepositoryProvider).openPurchases().then((open) {
      if (!mounted) return;
      setState(() {
        _open = open;
        // Goods the agent has billed are the ones most likely to have arrived.
        _selected.addAll([
          for (final o in open)
            if (o.purchase.status == PurchaseStatus.inTransit) o.purchase.id,
        ]);
      });
    });
    _transport.addListener(() => setState(() {}));
    _storage.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _transport.dispose();
    _storage.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _collectedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _collectedAt = picked);
  }

  Future<void> _save(String? moneyPlaceId) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tick the purchases you collected')));
      return;
    }
    setState(() => _saving = true);
    final transport = moneyFromController(_transport);
    final storage = moneyFromController(_storage);
    try {
      await ref
          .read(shippingRepositoryProvider)
          .saveCollection(
            CollectionDraft(
              collectedAt: _collectedAt,
              transportZmw: transport,
              storageZmw: storage,
              moneyPlaceId: transport + storage > 0 ? moneyPlaceId : null,
              purchaseIds: _selected.toList(),
            ),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = _open;
    final places = (ref.watch(moneyPlacesProvider).value ?? const <MoneyPlace>[])
        .where((p) => !p.archived)
        .toList();
    // Pickup costs are usually paid in cash.
    final moneyPlaceId =
        _moneyPlaceId ??
        places.where((p) => p.kind == MoneyPlaceKind.cash).firstOrNull?.id ??
        places.firstOrNull?.id;
    final hasCost = moneyFromController(_transport) + moneyFromController(_storage) > 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Collect goods')),
      body: open == null
          ? const Center(child: CircularProgressIndicator())
          : open.isEmpty
          ? const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Nothing waiting to be collected',
              message: 'Purchases appear here until you collect them.',
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Collected on'),
                      child: Text(shortDate.format(_collectedAt)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('What did you collect?', style: theme.textTheme.titleMedium),
                  for (final o in open)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _selected.contains(o.purchase.id),
                      onChanged: (on) => setState(() {
                        on == true ? _selected.add(o.purchase.id) : _selected.remove(o.purchase.id);
                      }),
                      title: Text(o.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          shortDate.format(o.purchase.orderedAt),
                          purchaseStatusLabels[o.purchase.status]!,
                        ].join(' · '),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text('Pickup costs', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Optional. Spread over everything you ticked.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: MoneyField(controller: _transport, label: 'Transport'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MoneyField(controller: _storage, label: 'Storage fee'),
                      ),
                    ],
                  ),
                  if (hasCost && moneyPlaceId != null) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: moneyPlaceId,
                      decoration: const InputDecoration(labelText: 'Paid from'),
                      items: [for (final p in places) DropdownMenuItem(value: p.id, child: Text(p.name))],
                      onChanged: (v) => setState(() => _moneyPlaceId = v),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : () => _save(moneyPlaceId),
                    child: Text(
                      'Collect ${_selected.length} '
                      '${_selected.length == 1 ? 'purchase' : 'purchases'}',
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
