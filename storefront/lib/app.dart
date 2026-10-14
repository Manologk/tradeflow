import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/browse_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/favourites_screen.dart';
import 'screens/home_screen.dart';
import 'screens/my_orders_screen.dart';
import 'screens/order_sent_screen.dart';
import 'screens/product_screen.dart';
import 'screens/shell.dart';
import 'theme.dart';

GoRouter buildRouter() => GoRouter(
  routes: [
    ShellRoute(
      builder: (context, state, child) => ShopShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => HomeScreen(
            categoryId: state.uri.queryParameters['category'],
            seriesId: state.uri.queryParameters['series'],
          ),
        ),
        GoRoute(path: '/favourites', builder: (context, state) => const FavouritesScreen()),
        GoRoute(path: '/orders', builder: (context, state) => const MyOrdersScreen()),
      ],
    ),
    GoRoute(path: '/browse', builder: (context, state) => const BrowseScreen()),
    GoRoute(
      path: '/p/:id',
      builder: (context, state) => ProductScreen(productId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/cart', builder: (context, state) => const CartScreen()),
    GoRoute(
      path: '/order/:code',
      builder: (context, state) => OrderSentScreen(code: state.pathParameters['code']!),
    ),
  ],
);

class ShopApp extends ConsumerStatefulWidget {
  const ShopApp({super.key});

  @override
  ConsumerState<ShopApp> createState() => _ShopAppState();
}

class _ShopAppState extends ConsumerState<ShopApp> {
  late final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Shop',
      debugShowCheckedModeBanner: false,
      theme: shopTheme(),
      routerConfig: _router,
      // The design is for phones: on wide screens keep it phone-width.
      builder: (context, child) => ColoredBox(
        color: const Color(0xFFF6F6F7),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ClipRect(child: child),
          ),
        ),
      ),
    );
  }
}
