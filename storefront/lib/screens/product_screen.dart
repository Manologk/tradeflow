import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/models.dart';
import '../domain/money.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/catalog_gate.dart';
import '../widgets/common.dart';

class ProductScreen extends ConsumerWidget {
  const ProductScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Loading and error states sit on plain Material; the product itself gets
    // its own Scaffold so messages appear above the Add to Cart bar.
    return Material(
      color: Colors.white,
      child: CatalogGate(
        builder: (catalog) {
          final product = catalog.product(productId);
          if (product == null) {
            return EmptyMessage(
              icon: Icons.search_off,
              title: 'This item is no longer available',
              action: FilledButton(onPressed: () => context.go('/'), child: const Text('Back to shop')),
            );
          }
          return _ProductView(product: product, catalog: catalog);
        },
      ),
    );
  }
}

class _ProductView extends ConsumerStatefulWidget {
  const _ProductView({required this.product, required this.catalog});

  final ShopProduct product;
  final Catalog catalog;

  @override
  ConsumerState<_ProductView> createState() => _ProductViewState();
}

class _ProductViewState extends ConsumerState<_ProductView> {
  var _qty = 1;
  var _photo = 0;
  var _expanded = false;
  String? _size;
  String? _color;

  ShopProduct get p => widget.product;

  void _addToCart() {
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    // The options can be scrolled out of view, so say what's missing up front.
    final missing = p.sizes.isNotEmpty && _size == null
        ? 'Choose a size'
        : p.colors.isNotEmpty && _color == null
        ? 'Choose a colour'
        : null;
    if (missing != null) {
      messenger.showSnackBar(SnackBar(content: Text(missing)));
      return;
    }
    ref.read(cartProvider.notifier).add(CartLine(productId: p.id, size: _size, color: _color, qty: _qty));
    messenger.showSnackBar(
      SnackBar(
        content: Text('Added ${_qty > 1 ? '$_qty × ' : ''}${p.name} to your cart'),
        action: SnackBarAction(label: 'View cart', onPressed: () => context.push('/cart')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final favourite = ref.watch(favouritesProvider).contains(p.id);
    final series = widget.catalog.seriesOf(p.seriesId);
    final category = widget.catalog.category(p.categoryId);
    final photoCount = p.photos.isEmpty ? 1 : p.photos.length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            AspectRatio(
              aspectRatio: 0.85,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    itemCount: photoCount,
                    onPageChanged: (i) => setState(() => _photo = i),
                    itemBuilder: (_, i) => ProductImage(product: p, index: i, radius: 28),
                  ),
                  Positioned(
                    top: 14,
                    left: 14,
                    child: CircleIconButton(
                      icon: Icons.arrow_back_ios_new,
                      tooltip: 'Back',
                      onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    right: 14,
                    child: FavouriteButton(
                      selected: favourite,
                      size: 44,
                      onPressed: () => ref.read(favouritesProvider.notifier).toggle(p.id),
                    ),
                  ),
                  if (photoCount > 1)
                    Positioned(
                      bottom: 14,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < photoCount; i++)
                            Container(
                              width: i == _photo ? 18 : 6,
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: i == _photo ? Colors.white : Colors.white54,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    p.name,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, height: 1.2),
                  ),
                ),
                if (p.canOrder) ...[
                  const SizedBox(width: 12),
                  QtyStepper(value: _qty, onChanged: (v) => setState(() => _qty = v)),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [?series?.name, ?category?.name].join(' · '),
              style: const TextStyle(color: ShopColors.grey),
            ),
            const SizedBox(height: 10),
            AvailabilityLabel(product: p),
            if (p.description.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                p.description,
                maxLines: _expanded ? null : 3,
                overflow: _expanded ? null : TextOverflow.ellipsis,
                style: const TextStyle(color: ShopColors.grey, height: 1.5),
              ),
              if (p.description.length > 140)
                TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: ShopColors.inkDeep),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'Show less' : 'Read more…'),
                ),
            ],
            if (p.sizes.isNotEmpty || p.colors.isNotEmpty) ...[
              const Divider(height: 32),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.sizes.isNotEmpty)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Choose size', style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final s in p.sizes)
                                _SizeDot(
                                  label: s,
                                  selected: _size == s,
                                  onTap: () => setState(() => _size = s),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (p.colors.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _color == null ? 'Colour' : 'Colour: $_color',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          children: [
                            for (final c in p.colors)
                              _ColorDot(
                                color: c,
                                selected: _color == c.name,
                                onTap: () => setState(() => _color = c.name),
                              ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: FilledButton(
            onPressed: p.canOrder ? _addToCart : null,
            child: p.canOrder
                // Shrinks rather than overflows with big totals on narrow phones.
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shopping_cart_outlined, size: 20),
                        const SizedBox(width: 10),
                        Text('${p.isPreOrder ? 'Pre-order' : 'Add to Cart'} | ${kwacha(p.priceZmw * _qty)}'),
                        if (p.isOnSale) ...[
                          const SizedBox(width: 6),
                          Text(
                            kwacha(p.compareAtZmw! * _qty),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: Colors.white70,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: Colors.white70,
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : const Text('Sold out'),
          ),
        ),
      ),
    );
  }
}

class _SizeDot extends StatelessWidget {
  const _SizeDot({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Size $label',
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 40),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: ShapeDecoration(
            color: selected ? ShopColors.ink : Colors.white,
            shape: StadiumBorder(
              side: BorderSide(color: selected ? ShopColors.ink : const Color(0xFFE6E5E5)),
            ),
          ),
          // widthFactor keeps the pill as narrow as its label instead of
          // stretching across the row; the text sits in the middle.
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : ShopColors.inkDeep,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.selected, required this.onTap});

  final ShopColor color;
  final bool selected;
  final VoidCallback onTap;

  Color get _value {
    final hex = color.hex.replaceFirst('#', '');
    return Color(int.tryParse('FF$hex', radix: 16) ?? 0xFFA3A1A2);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: color.name,
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Colour ${color.name}',
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? ShopColors.ink : Colors.transparent, width: 2),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _value,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE6E5E5)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
