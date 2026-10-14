import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/providers.dart';

const moneyPlaceKindLabels = {
  MoneyPlaceKind.card: 'Card',
  MoneyPlaceKind.mobileMoney: 'Mobile money',
  MoneyPlaceKind.cash: 'Cash',
  MoneyPlaceKind.other: 'Other',
};

class MoneyPlacesScreen extends ConsumerWidget {
  const MoneyPlacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(settingsRepositoryProvider);
    final places = ref.watch(moneyPlacesProvider).value ?? const <MoneyPlace>[];

    Future<void> edit([MoneyPlace? place]) async {
      final result = await showDialog<_PlaceForm>(
        context: context,
        builder: (_) => _PlaceDialog(place: place),
      );
      if (result == null) return;
      if (place == null) {
        await repo.addMoneyPlace(
          name: result.name,
          kind: result.kind,
          openingBalanceZmw: result.openingBalanceZmw,
        );
      } else {
        await repo.updateMoneyPlace(
          place.id,
          name: result.name,
          kind: result.kind,
          openingBalanceZmw: result.openingBalanceZmw,
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Money places')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: edit,
        icon: const Icon(Icons.add),
        label: const Text('Add place'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          for (final place in places)
            ListTile(
              enabled: !place.archived,
              title: Text(place.name),
              subtitle: Text(
                '${moneyPlaceKindLabels[place.kind]} · opening ${Money(place.openingBalanceZmw)}'
                '${place.archived ? ' · archived' : ''}',
              ),
              onTap: place.archived ? null : () => edit(place),
              trailing: IconButton(
                tooltip: place.archived ? 'Restore' : 'Archive',
                icon: Icon(place.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
                onPressed: () => repo.setMoneyPlaceArchived(place.id, !place.archived),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaceForm {
  const _PlaceForm(this.name, this.kind, this.openingBalanceZmw);

  final String name;
  final MoneyPlaceKind kind;
  final int openingBalanceZmw;
}

class _PlaceDialog extends StatefulWidget {
  const _PlaceDialog({this.place});

  final MoneyPlace? place;

  @override
  State<_PlaceDialog> createState() => _PlaceDialogState();
}

class _PlaceDialogState extends State<_PlaceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.place?.name ?? '');
  late final _balance =
      TextEditingController(text: Money.editable(widget.place?.openingBalanceZmw ?? 0));
  late var _kind = widget.place?.kind ?? MoneyPlaceKind.mobileMoney;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _PlaceForm(_name.text.trim(), _kind, moneyFromController(_balance)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.place == null ? 'Add money place' : 'Edit money place'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: widget.place == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<MoneyPlaceKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final MapEntry(:key, :value) in moneyPlaceKindLabels.entries)
                  DropdownMenuItem(value: key, child: Text(value)),
              ],
              onChanged: (v) => setState(() => _kind = v ?? _kind),
            ),
            const SizedBox(height: 16),
            MoneyField(
              controller: _balance,
              label: 'Opening balance',
              helperText: 'What was here when you started using TradeFlow',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
