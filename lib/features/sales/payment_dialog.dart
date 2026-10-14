import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/providers.dart';

class PaymentInput {
  const PaymentInput(this.amountZmw, this.moneyPlaceId);

  final int amountZmw;
  final String moneyPlaceId;
}

/// Asks how much was received and where. Suggests [owedZmw].
Future<PaymentInput?> askForPayment(BuildContext context, {required String title, required int owedZmw}) =>
    showDialog<PaymentInput>(
      context: context,
      builder: (_) => _PaymentDialog(title: title, owedZmw: owedZmw),
    );

class _PaymentDialog extends ConsumerStatefulWidget {
  const _PaymentDialog({required this.title, required this.owedZmw});

  final String title;
  final int owedZmw;

  @override
  ConsumerState<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<_PaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: Money.editable(widget.owedZmw));
  String? _placeId;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final places = (ref.watch(moneyPlacesProvider).value ?? const <MoneyPlace>[])
        .where((p) => !p.archived)
        .toList();
    final placeId =
        _placeId ??
        places.where((p) => p.kind == MoneyPlaceKind.mobileMoney).firstOrNull?.id ??
        places.firstOrNull?.id;

    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Owed: ${Money(widget.owedZmw)}'),
            const SizedBox(height: 16),
            MoneyField(controller: _amount, label: 'Amount received', required: true),
            const SizedBox(height: 16),
            if (placeId != null)
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: placeId,
                decoration: const InputDecoration(labelText: 'Received into'),
                items: [for (final p in places) DropdownMenuItem(value: p.id, child: Text(p.name))],
                onChanged: (v) => setState(() => _placeId = v),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: placeId == null
              ? null
              : () {
                  if (!_formKey.currentState!.validate()) return;
                  final amount = moneyFromController(_amount);
                  if (amount <= 0) return;
                  Navigator.pop(context, PaymentInput(amount, placeId));
                },
          child: const Text('Record payment'),
        ),
      ],
    );
  }
}
