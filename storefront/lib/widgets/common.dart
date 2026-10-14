import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/money.dart';
import '../theme.dart';

/// Product photo with a calm placeholder while loading or when missing.
class ProductImage extends StatelessWidget {
  const ProductImage({super.key, required this.product, this.index = 0, this.radius = 20});

  final ShopProduct product;
  final int index;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = index < product.photos.length ? product.photos[index] : null;
    final placeholder = Container(
      color: ShopColors.surface,
      alignment: Alignment.center,
      child: Text(
        product.name.isEmpty ? '?' : product.name.characters.first.toUpperCase(),
        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w600, color: ShopColors.greyLight),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url == null
          ? placeholder
          : Image.network(
              url,
              fit: BoxFit.cover,
              semanticLabel: product.name,
              errorBuilder: (_, _, _) => placeholder,
              loadingBuilder: (context, child, progress) => progress == null ? child : placeholder,
            ),
    );
  }
}

/// Round white button with a soft border, as on the design's photo overlays.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 44,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;

  /// Dark filled variant (e.g. the filter button).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled ? ShopColors.ink : Colors.white,
        shape: CircleBorder(side: filled ? BorderSide.none : const BorderSide(color: Color(0xFFE6E5E5))),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: Icon(icon, size: size * 0.45, color: filled ? Colors.white : ShopColors.inkDeep),
          ),
        ),
      ),
    );
  }
}

/// Small round favourite toggle drawn over product photos.
class FavouriteButton extends StatelessWidget {
  const FavouriteButton({super.key, required this.selected, required this.onPressed, this.size = 32});

  final bool selected;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: selected ? 'Remove from favourites' : 'Add to favourites',
      child: Material(
        color: ShopColors.ink,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: Icon(
              selected ? Icons.favorite : Icons.favorite_border,
              size: size * 0.55,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// "−  2  +" stepper from the design.
class QtyStepper extends StatelessWidget {
  const QtyStepper({super.key, required this.value, required this.onChanged, this.min = 1, this.max = 99});

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String label, int next, bool enabled) => CircleIconButton(
      icon: icon,
      tooltip: label,
      size: 32,
      onPressed: enabled ? () => onChanged(next) : null,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(Icons.remove, 'Less', value - 1, value > min),
        SizedBox(
          width: 32,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        button(Icons.add, 'More', value + 1, value < max),
      ],
    );
  }
}

/// Price with the old price struck through when on sale.
class PriceText extends StatelessWidget {
  const PriceText({super.key, required this.product, this.size = 16});

  final ShopProduct product;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 6,
      children: [
        Text(
          kwacha(product.priceZmw),
          style: TextStyle(fontSize: size, fontWeight: FontWeight.w600),
        ),
        if (product.isOnSale)
          Text(
            kwacha(product.compareAtZmw!),
            style: TextStyle(
              fontSize: size * 0.75,
              color: ShopColors.grey,
              decoration: TextDecoration.lineThrough,
            ),
          ),
      ],
    );
  }
}

/// Availability as text plus icon, never colour alone.
class AvailabilityLabel extends StatelessWidget {
  const AvailabilityLabel({super.key, required this.product, this.compact = false});

  final ShopProduct product;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = switch (product.availability) {
      Availability.inStock => (Icons.check_circle_outline, 'In stock', ShopColors.grey),
      Availability.fewLeft => (Icons.local_fire_department_outlined, 'Only a few left', ShopColors.sale),
      Availability.preOrder => (
        Icons.schedule,
        compact
            ? 'Pre-order'
            : 'Pre-order${product.leadTimeWeeks == null ? '' : ' · arrives in ~${product.leadTimeWeeks} weeks'}',
        ShopColors.ink,
      ),
      Availability.soldOut => (Icons.block, 'Sold out', ShopColors.grey),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: compact ? 14 : 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: compact ? 12 : 14, color: color, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

/// Grid card: photo with favourite, name, series, price, availability.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.seriesName,
    required this.favourite,
    required this.onFavourite,
    required this.onTap,
  });

  final ShopProduct product;
  final String? seriesName;
  final bool favourite;
  final VoidCallback onFavourite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The photo takes whatever height the grid cell leaves after the
          // text, so long names never overflow.
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: product.canOrder ? 1 : 0.5,
                  child: ProductImage(product: product),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: FavouriteButton(selected: favourite, onPressed: onFavourite),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.25),
          ),
          if (seriesName != null)
            Text(seriesName!, style: const TextStyle(fontSize: 12, color: ShopColors.greyLight)),
          const SizedBox(height: 6),
          PriceText(product: product, size: 15),
          const SizedBox(height: 2),
          AvailabilityLabel(product: product, compact: true),
        ],
      ),
    );
  }
}

/// Selectable pill (categories, sizes).
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : ShopColors.inkDeep;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? ShopColors.ink : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? ShopColors.ink : const Color(0xFFE6E5E5))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onSelected,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 6)],
                Text(
                  label,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Centered message for empty lists and errors.
class EmptyMessage extends StatelessWidget {
  const EmptyMessage({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: ShopColors.surface, shape: BoxShape.circle),
              child: Icon(icon, size: 32, color: ShopColors.grey),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: ShopColors.grey),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
