import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/checkout.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/catalog_gate.dart';
import '../widgets/common.dart';

/// Opens a link outside the app (WhatsApp). Overridden in tests.
final linkOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Cart and checkout in one screen, as in the design.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  CircleIconButton(
                    icon: Icons.arrow_back_ios_new,
                    tooltip: 'Back',
                    onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                  ),
                  const Expanded(
                    child: Text(
                      'Checkout',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            Expanded(
              child: CatalogGate(builder: (catalog) => _Checkout(catalog: catalog)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Checkout extends ConsumerStatefulWidget {
  const _Checkout({required this.catalog});

  final Catalog catalog;

  @override
  ConsumerState<_Checkout> createState() => _CheckoutState();
}

class _CheckoutState extends ConsumerState<_Checkout> {
  final _formKey = GlobalKey<FormState>();
  // Created in initState (not lazily) so dispose() never touches ref after
  // the widget has gone, e.g. when the cart is empty and the form never shows.
  late final TextEditingController _name;
  late final TextEditingController _phone;
  final _notes = TextEditingController();
  String? _areaId;
  var _sending = false;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(savedCustomerProvider);
    final areas = widget.catalog.settings.deliveryAreas;
    _name = TextEditingController(text: saved.name);
    _phone = TextEditingController(text: saved.phone.startsWith('260') ? '0${saved.phone.substring(3)}' : '');
    _areaId = areas.any((a) => a.id == saved.areaId) ? saved.areaId : areas.firstOrNull?.id;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _order(List<OrderLine> lines) async {
    if (!_formKey.currentState!.validate()) return;
    final settings = widget.catalog.settings;
    final customer = Customer(
      name: _name.text.trim(),
      phone: normalisePhone(_phone.text)!,
      areaId: _areaId,
      notes: _notes.text.trim(),
    );
    final order = buildOrder(
      code: newOrderCode(),
      now: DateTime.now(),
      customer: customer,
      lines: lines,
      settings: settings,
    );
    setState(() => _sending = true);

    // Save online so the order reaches the admin app. If that fails, the
    // WhatsApp message still carries everything the shop needs.
    var savedOnline = true;
    try {
      await ref.read(shopRepositoryProvider).submitOrder(order);
    } on Object {
      savedOnline = false;
    }
    final opened = await ref.read(linkOpenerProvider)(whatsappLink(order, settings));

    ref.read(savedCustomerProvider).save(customer);
    ref.read(placedOrdersProvider.notifier).add(order);
    ref.read(cartProvider.notifier).clear();
    if (!mounted) return;
    context.go('/order/${order.code}', extra: (order: order, savedOnline: savedOnline, opened: opened));
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final lines = ref.watch(pricedCartProvider);
    final settings = widget.catalog.settings;

    if (cart.isEmpty) {
      return EmptyMessage(
        icon: Icons.shopping_bag_outlined,
        title: 'Your cart is empty',
        message: 'Find something you love and add it here.',
        action: FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(200, 52)),
          onPressed: () => context.go('/'),
          child: const Text('Start shopping'),
        ),
      );
    }

    final totals = totalsFor(lines, settings, areaId: _areaId);
    final unavailable = cart.length - lines.length;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          for (final line in cart)
            if (widget.catalog.product(line.productId) case final p? when p.canOrder)
              _CartLineTile(line: line, product: p),
          if (unavailable > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '$unavailable ${unavailable == 1 ? 'item is' : 'items are'} no longer available and won\'t be ordered.',
                style: const TextStyle(color: ShopColors.sale),
              ),
            ),
          const SizedBox(height: 24),
          const Text('Delivery information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(labelText: 'Your name'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
            decoration: const InputDecoration(labelText: 'Phone number', hintText: '097 123 4567'),
            validator: (v) => normalisePhone(v ?? '') == null ? 'Enter a Zambian mobile number' : null,
          ),
          if (settings.deliveryAreas.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _areaId,
              decoration: const InputDecoration(labelText: 'Delivery'),
              items: [
                for (final a in settings.deliveryAreas)
                  DropdownMenuItem(
                    value: a.id,
                    child: Text('${a.name} · ${a.feeZmw == 0 ? 'free' : kwacha(a.feeZmw)}'),
                  ),
              ],
              onChanged: (v) => setState(() => _areaId = v),
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _notes,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              hintText: 'Landmark, best time to call…',
            ),
          ),
          const SizedBox(height: 24),
          _TotalRow(
            label: 'Total (${totals.units} ${totals.units == 1 ? 'item' : 'items'})',
            value: kwacha(totals.itemsZmw),
          ),
          _TotalRow(label: 'Delivery fee', value: kwacha(totals.deliveryZmw)),
          const Divider(height: 28),
          _TotalRow(label: 'Total', value: kwacha(totals.totalZmw), bold: true),
          if (totals.depositZmw > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: ShopColors.surface, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.schedule, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pre-order items need a ${settings.depositPercent}% deposit of ${kwacha(totals.depositZmw)}. '
                      "We'll share payment details on WhatsApp.",
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _sending || lines.isEmpty ? null : () => _order(lines),
            icon: _sending
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.chat_outlined),
            label: const Text('Order on WhatsApp'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Opens WhatsApp with your order ready to send. Pay by mobile money or on delivery.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: ShopColors.grey),
          ),
        ],
      ),
    );
  }
}

class _CartLineTile extends ConsumerWidget {
  const _CartLineTile({required this.line, required this.product});

  final CartLine line;
  final ShopProduct product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.read(cartProvider.notifier);
    final options = [if (line.size != null) 'Size ${line.size}', ?line.color].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEDEDED))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 72, height: 72, child: ProductImage(product: product, radius: 14)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      height: 24,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: 'Remove ${product.name}',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => cart.remove(line.key),
                      ),
                    ),
                  ],
                ),
                Text(
                  [if (options.isNotEmpty) options, if (product.isPreOrder) 'Pre-order'].join(' · '),
                  style: const TextStyle(fontSize: 12, color: ShopColors.greyLight),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        kwacha(product.priceZmw * line.qty),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    QtyStepper(value: line.qty, onChanged: (v) => cart.setQty(line.key, v)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: bold ? 17 : 15, fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
