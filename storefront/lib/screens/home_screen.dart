import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/catalog_gate.dart';
import '../widgets/common.dart';
import 'shell.dart';

/// Shop front: greeting, search, filters, category chips and product grid.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.categoryId, this.seriesId});

  final String? categoryId;
  final String? seriesId;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late String? _categoryId = widget.categoryId;
  late String? _seriesId = widget.seriesId;
  var _query = '';
  var _inStockOnly = false;

  @override
  void didUpdateWidget(HomeScreen old) {
    super.didUpdateWidget(old);
    if (old.categoryId != widget.categoryId || old.seriesId != widget.seriesId) {
      setState(() {
        _categoryId = widget.categoryId;
        _seriesId = widget.seriesId;
      });
    }
  }

  Future<void> _openFilters(Catalog catalog) async {
    final result = await showModalBottomSheet<(String?, bool)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => _FilterSheet(catalog: catalog, seriesId: _seriesId, inStockOnly: _inStockOnly),
    );
    if (result != null) {
      setState(() {
        _seriesId = result.$1;
        _inStockOnly = result.$2;
      });
    }
  }

  List<ShopProduct> _visible(Catalog catalog) => [
    for (final p in catalog.products)
      if ((_categoryId == null || p.categoryId == _categoryId) &&
          (_seriesId == null || p.seriesId == _seriesId) &&
          (!_inStockOnly ||
              p.availability == Availability.inStock ||
              p.availability == Availability.fewLeft) &&
          p.matches(_query))
        p,
  ]..sort((a, b) => (a.canOrder ? 0 : 1).compareTo(b.canOrder ? 0 : 1));

  @override
  Widget build(BuildContext context) {
    return CatalogGate(
      builder: (catalog) {
        final favourites = ref.watch(favouritesProvider);
        final products = _visible(catalog);
        final series = catalog.seriesOf(_seriesId);
        final filtersOn = _seriesId != null || _inStockOnly;

        return SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                sliver: SliverList.list(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Hello, welcome 👋',
                                style: TextStyle(fontSize: 13, color: ShopColors.grey),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                catalog.settings.name,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        CircleIconButton(
                          icon: Icons.grid_view_rounded,
                          tooltip: 'Browse by series',
                          onPressed: () => context.push('/browse'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              hintText: 'Search merch…',
                              prefixIcon: Icon(Icons.search, color: ShopColors.greyLight),
                            ),
                            textInputAction: TextInputAction.search,
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Badge(
                          isLabelVisible: filtersOn,
                          smallSize: 10,
                          backgroundColor: ShopColors.sale,
                          child: CircleIconButton(
                            icon: Icons.tune,
                            tooltip: 'Filters',
                            filled: true,
                            size: 50,
                            onPressed: () => _openFilters(catalog),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      PillChip(
                        label: 'All items',
                        icon: Icons.grid_view_rounded,
                        selected: _categoryId == null,
                        onSelected: () => setState(() => _categoryId = null),
                      ),
                      for (final c in catalog.categories) ...[
                        const SizedBox(width: 10),
                        PillChip(
                          label: c.name,
                          selected: _categoryId == c.id,
                          onSelected: () => setState(() => _categoryId = _categoryId == c.id ? null : c.id),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (series != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: InputChip(
                        label: Text('Series: ${series.name}'),
                        onDeleted: () => setState(() => _seriesId = null),
                      ),
                    ),
                  ),
                ),
              if (products.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyMessage(
                    icon: Icons.search_off,
                    title: 'Nothing found',
                    message: 'Try another search or clear the filters.',
                    action: OutlinedButton(
                      onPressed: () => setState(() {
                        _categoryId = null;
                        _seriesId = null;
                        _inStockOnly = false;
                      }),
                      child: const Text('Clear filters'),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, bottomBarClearance),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 20,
                      mainAxisExtent: 330,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, i) {
                      final p = products[i];
                      return ProductCard(
                        product: p,
                        seriesName: catalog.seriesOf(p.seriesId)?.name,
                        favourite: favourites.contains(p.id),
                        onFavourite: () => ref.read(favouritesProvider.notifier).toggle(p.id),
                        onTap: () => context.push('/p/${p.id}'),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.catalog, required this.seriesId, required this.inStockOnly});

  final Catalog catalog;
  final String? seriesId;
  final bool inStockOnly;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _seriesId = widget.seriesId;
  late bool _inStockOnly = widget.inStockOnly;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            const Text('Anime series', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PillChip(
                  label: 'All series',
                  selected: _seriesId == null,
                  onSelected: () => setState(() => _seriesId = null),
                ),
                for (final s in widget.catalog.series)
                  PillChip(
                    label: s.name,
                    selected: _seriesId == s.id,
                    onSelected: () => setState(() => _seriesId = s.id),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _inStockOnly,
              onChanged: (v) => setState(() => _inStockOnly = v),
              title: const Text('In stock only'),
              subtitle: const Text('Hide pre-order items'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context, (_seriesId, _inStockOnly)),
              child: const Text('Show results'),
            ),
          ],
        ),
      ),
    );
  }
}
