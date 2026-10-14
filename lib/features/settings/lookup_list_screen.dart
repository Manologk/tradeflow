import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/providers.dart';

/// Add, rename and archive the entries of one short list.
class LookupListScreen extends ConsumerWidget {
  const LookupListScreen({super.key, required this.kind});

  final LookupKind kind;

  static const _titles = {
    LookupKind.platform: ('Platforms', 'Platform'),
    LookupKind.cargoType: ('Cargo types', 'Cargo type'),
    LookupKind.channel: ('Sales channels', 'Channel'),
    LookupKind.expenseCategory: ('Expense categories', 'Category'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (title, singular) = _titles[kind]!;
    final repo = ref.watch(settingsRepositoryProvider);
    final items = ref.watch(lookupsProvider(kind)).value ?? const <Lookup>[];
    final active = items.where((l) => !l.archived).toList();
    final archived = items.where((l) => l.archived).toList();

    Future<void> add() async {
      final name = await promptForText(context, title: 'Add $singular', label: 'Name', confirmLabel: 'Add');
      if (name != null) await repo.addLookup(kind, name);
    }

    Future<void> rename(Lookup item) async {
      final name = await promptForText(context, title: 'Rename $singular', label: 'Name', initial: item.name);
      if (name != null) await repo.renameLookup(item.id, name);
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: add,
        icon: const Icon(Icons.add),
        label: Text('Add ${singular.toLowerCase()}'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          for (final item in active)
            ListTile(
              title: Text(item.name),
              onTap: () => rename(item),
              trailing: IconButton(
                tooltip: 'Archive',
                icon: const Icon(Icons.archive_outlined),
                onPressed: () => repo.setLookupArchived(item.id, true),
              ),
            ),
          if (archived.isNotEmpty) ...[
            const Divider(),
            const ListTile(dense: true, title: Text('Archived — hidden from pickers')),
            for (final item in archived)
              ListTile(
                title: Text(item.name, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                trailing: IconButton(
                  tooltip: 'Restore',
                  icon: const Icon(Icons.unarchive_outlined),
                  onPressed: () => repo.setLookupArchived(item.id, false),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
