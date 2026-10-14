import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../data/setup_repository.dart';

/// First run: name the store, set opening balances, optionally enter the
/// stock already on hand.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _PlaceRow {
  _PlaceRow(String name, this.kind) : name = TextEditingController(text: name);

  final TextEditingController name;
  final MoneyPlaceKind kind;
  final balance = TextEditingController();

  void dispose() {
    name.dispose();
    balance.dispose();
  }
}

class _StockRow {
  final name = TextEditingController();
  final qty = TextEditingController();
  final cost = TextEditingController();

  bool get isBlank => name.text.trim().isEmpty && qty.text.trim().isEmpty && cost.text.trim().isEmpty;

  void dispose() {
    name.dispose();
    qty.dispose();
    cost.dispose();
  }
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _stepCount = 3;

  final _formKeys = List.generate(_stepCount, (_) => GlobalKey<FormState>());
  final _storeName = TextEditingController();
  final _places = [for (final p in defaultPlaces) _PlaceRow(p.name, p.kind)];
  final _stock = <_StockRow>[];
  var _step = 0;
  var _saving = false;

  @override
  void dispose() {
    _storeName.dispose();
    for (final p in _places) {
      p.dispose();
    }
    for (final s in _stock) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _next() async {
    if (!_formKeys[_step].currentState!.validate()) return;
    if (_step < _stepCount - 1) {
      setState(() => _step++);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(setupRepositoryProvider).completeSetup(
            storeName: _storeName.text,
            places: [
              for (final p in _places)
                OpeningPlace(
                  name: p.name.text,
                  kind: p.kind,
                  balanceZmw: moneyFromController(p.balance),
                ),
            ],
            stock: [
              for (final s in _stock.where((s) => !s.isBlank))
                OpeningStockEntry(
                  productName: s.name.text,
                  qty: int.parse(s.qty.text.trim()),
                  unitCostZmw: moneyFromController(s.cost),
                ),
            ],
          );
      // The root widget switches to the main app when the store appears.
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save setup: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = [_storeStep(theme), _placesStep(theme), _stockStep(theme)];
    final isLast = _step == _stepCount - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(value: (_step + 1) / _stepCount),
            Expanded(
              child: Form(
                key: _formKeys[_step],
                child: ListView(padding: const EdgeInsets.all(24), children: steps[_step]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: _saving ? null : () => setState(() => _step--),
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : _next,
                    child: Text(isLast ? 'Finish setup' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _header(ThemeData theme, String title, String body) => [
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
        const SizedBox(height: 24),
      ];

  List<Widget> _storeStep(ThemeData theme) => [
        ..._header(
          theme,
          'Welcome to TradeFlow',
          'Track what your China orders really cost, what you sell, and where your money is.',
        ),
        TextFormField(
          controller: _storeName,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Business name'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
          onFieldSubmitted: (_) => _next(),
        ),
      ];

  List<Widget> _placesStep(ThemeData theme) => [
        ..._header(
          theme,
          'Where is your money?',
          'Enter what is in each place right now. Rename or remove places you do not use.',
        ),
        for (final (i, place) in _places.indexed) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: TextFormField(
                  controller: place.name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 4, child: MoneyField(controller: place.balance, label: 'Balance')),
              IconButton(
                tooltip: 'Remove',
                onPressed: _places.length == 1
                    ? null
                    : () => setState(() => _places.removeAt(i).dispose()),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _places.add(_PlaceRow('', MoneyPlaceKind.other))),
            icon: const Icon(Icons.add),
            label: const Text('Add a place'),
          ),
        ),
      ];

  List<Widget> _stockStep(ThemeData theme) => [
        ..._header(
          theme,
          'Stock you already have',
          'Optional. Add items you are holding now with a rough cost per item, '
              'so profit on them is counted. You can skip this.',
        ),
        for (final (i, row) in _stock.indexed) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 4, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        TextFormField(
                          controller: row.name,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(labelText: 'Item'),
                          validator: (v) => !row.isBlank && (v == null || v.trim().isEmpty)
                              ? 'Enter the item name'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: row.qty,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Quantity'),
                                validator: (v) {
                                  if (row.isBlank) return null;
                                  final qty = int.tryParse(v?.trim() ?? '');
                                  return (qty == null || qty <= 0) ? 'Enter a number' : null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: MoneyField(
                                controller: row.cost,
                                label: 'Cost each',
                                required: !row.isBlank,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: () => setState(() => _stock.removeAt(i).dispose()),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _stock.add(_StockRow())),
            icon: const Icon(Icons.add),
            label: const Text('Add an item'),
          ),
        ),
      ];
}
