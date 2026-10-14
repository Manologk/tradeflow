import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../data/shipping_repository.dart';
import '../purchases/purchase_labels.dart';

/// Multi-select of open purchases. Returns null if cancelled.
Future<List<String>?> pickPurchases(
  BuildContext context, {
  required List<OpenPurchase> options,
  required Set<String> initial,
}) => showModalBottomSheet<List<String>>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _PurchasePicker(options: options, initial: initial),
);

class _PurchasePicker extends StatefulWidget {
  const _PurchasePicker({required this.options, required this.initial});

  final List<OpenPurchase> options;
  final Set<String> initial;

  @override
  State<_PurchasePicker> createState() => _PurchasePickerState();
}

class _PurchasePickerState extends State<_PurchasePicker> {
  late final _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(child: Text('Which purchases?', style: Theme.of(context).textTheme.titleMedium)),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _selected.toList()),
                  child: Text('Done (${_selected.length})'),
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.options.isEmpty
                ? const Center(child: Text('No purchases waiting for shipping'))
                : ListView(
                    controller: controller,
                    children: [
                      for (final o in widget.options)
                        CheckboxListTile(
                          value: _selected.contains(o.purchase.id),
                          onChanged: (on) => setState(() {
                            on == true ? _selected.add(o.purchase.id) : _selected.remove(o.purchase.id);
                          }),
                          title: Text(o.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            [
                              shortDate.format(o.purchase.orderedAt),
                              Money(o.purchase.paidZmw).toString(),
                              purchaseStatusLabels[o.purchase.status]!,
                              ...o.trackingNumbers,
                            ].join(' · '),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
