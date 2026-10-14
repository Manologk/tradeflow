import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import 'agents_screen.dart';
import 'lookup_list_screen.dart';
import 'money_places_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  Future<void> _renameStore(BuildContext context, WidgetRef ref, Store store) async {
    final name = await promptForText(context, title: 'Business name', label: 'Name', initial: store.name);
    if (name != null) await ref.read(setupRepositoryProvider).renameStore(store.id, name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          if (store != null)
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Business name'),
              subtitle: Text(store.name),
              onTap: () => _renameStore(context, ref, store),
            ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Money places'),
            subtitle: const Text('Card, mobile money, cash and opening balances'),
            onTap: () => _open(context, const MoneyPlacesScreen()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.shopping_bag_outlined),
            title: const Text('Platforms'),
            subtitle: const Text('Where you buy: Taobao, 1688…'),
            onTap: () => _open(context, const LookupListScreen(kind: LookupKind.platform)),
          ),
          ListTile(
            leading: const Icon(Icons.local_shipping_outlined),
            title: const Text('Shipping agents'),
            subtitle: const Text('Agents and their rates per kg'),
            onTap: () => _open(context, const AgentsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Cargo types'),
            subtitle: const Text('Groups your agent charges different rates for'),
            onTap: () => _open(context, const LookupListScreen(kind: LookupKind.cargoType)),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: const Text('Sales channels'),
            subtitle: const Text('Where you sell: WhatsApp, Facebook…'),
            onTap: () => _open(context, const LookupListScreen(kind: LookupKind.channel)),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Expense categories'),
            onTap: () => _open(context, const LookupListScreen(kind: LookupKind.expenseCategory)),
          ),
        ],
      ),
    );
  }
}
