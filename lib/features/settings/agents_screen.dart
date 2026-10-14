import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/providers.dart';

class AgentsScreen extends ConsumerWidget {
  const AgentsScreen({super.key});

  void _edit(BuildContext context, [Agent? agent]) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AgentEditScreen(agent: agent)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(settingsRepositoryProvider);
    final agents = ref.watch(agentsProvider).value ?? const <Agent>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Shipping agents')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add),
        label: const Text('Add agent'),
      ),
      body: agents.isEmpty
          ? const EmptyState(
              icon: Icons.local_shipping_outlined,
              title: 'No shipping agents yet',
              message:
                  'Add your agent and their rate per kg for each cargo type. '
                  'The rates fill in automatically when you enter a shipping bill.',
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final agent in agents)
                  ListTile(
                    enabled: !agent.archived,
                    title: Text(agent.name),
                    subtitle: Text(
                      [if (agent.contact != null) agent.contact!, if (agent.archived) 'archived'].join(' · '),
                    ),
                    onTap: agent.archived ? null : () => _edit(context, agent),
                    trailing: IconButton(
                      tooltip: agent.archived ? 'Restore' : 'Archive',
                      icon: Icon(agent.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
                      onPressed: () => repo.setAgentArchived(agent.id, !agent.archived),
                    ),
                  ),
              ],
            ),
    );
  }
}

class AgentEditScreen extends ConsumerStatefulWidget {
  const AgentEditScreen({super.key, this.agent});

  final Agent? agent;

  @override
  ConsumerState<AgentEditScreen> createState() => _AgentEditScreenState();
}

class _AgentEditScreenState extends ConsumerState<AgentEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.agent?.name ?? '');
  late final _contact = TextEditingController(text: widget.agent?.contact ?? '');
  final _rates = <String, TextEditingController>{};
  var _loadedRates = false;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _loadRates();
  }

  Future<void> _loadRates() async {
    final agent = widget.agent;
    final rates = agent == null
        ? const <String, int>{}
        : await ref.read(settingsRepositoryProvider).agentRates(agent.id);
    if (!mounted) return;
    setState(() {
      for (final MapEntry(:key, :value) in rates.entries) {
        _rateController(key).text = Money.editable(value);
      }
      _loadedRates = true;
    });
  }

  TextEditingController _rateController(String cargoTypeId) =>
      _rates.putIfAbsent(cargoTypeId, TextEditingController.new);

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    for (final c in _rates.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref
        .read(settingsRepositoryProvider)
        .saveAgent(
          id: widget.agent?.id,
          name: _name.text,
          contact: _contact.text,
          usdPerKgByCargoType: {
            for (final MapEntry(:key, :value) in _rates.entries)
              if (value.text.trim().isNotEmpty) key: moneyFromController(value),
          },
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cargoTypes = (ref.watch(lookupsProvider(LookupKind.cargoType)).value ?? const <Lookup>[])
        .where((c) => !c.archived)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.agent == null ? 'Add agent' : 'Edit agent')),
      body: !_loadedRates
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _name,
                    autofocus: widget.agent == null,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Agent name'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _contact,
                    decoration: const InputDecoration(labelText: 'Contact (optional)'),
                  ),
                  const SizedBox(height: 24),
                  Text('Rate per kg', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Leave blank if this agent does not ship that type.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 16),
                  for (final cargo in cargoTypes) ...[
                    MoneyField(
                      controller: _rateController(cargo.id),
                      label: cargo.name,
                      currency: Currency.usd,
                    ),
                    const SizedBox(height: 16),
                  ],
                  FilledButton(onPressed: _saving ? null : _save, child: const Text('Save agent')),
                ],
              ),
            ),
    );
  }
}
