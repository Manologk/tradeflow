import 'package:drift/drift.dart';

import 'database.dart';

/// Editable reference data: lookups, money places and shipping agents.
///
/// Items are archived rather than deleted so past records that use them keep
/// their names; archived items just disappear from pickers.
class SettingsRepository {
  SettingsRepository(this.db, this.storeId);

  final AppDatabase db;
  final String storeId;

  // Lookups ---------------------------------------------------------------

  Stream<List<Lookup>> watchLookups(LookupKind kind) =>
      (db.select(db.lookups)
            ..where((l) => l.storeId.equals(storeId) & l.kind.equalsValue(kind) & l.deletedAt.isNull())
            ..orderBy([
              (l) => OrderingTerm(expression: l.sortOrder),
              (l) => OrderingTerm(expression: l.name),
            ]))
          .watch();

  Future<void> addLookup(LookupKind kind, String name) async {
    final count = await _countLookups(kind);
    await db
        .into(db.lookups)
        .insert(
          LookupsCompanion.insert(storeId: storeId, kind: kind, name: name.trim(), sortOrder: Value(count)),
        );
  }

  Future<void> renameLookup(String id, String name) => (db.update(db.lookups)..where((l) => l.id.equals(id)))
      .write(LookupsCompanion(name: Value(name.trim()), updatedAt: Value(DateTime.now())));

  Future<void> setLookupArchived(String id, bool archived) =>
      (db.update(db.lookups)..where((l) => l.id.equals(id))).write(
        LookupsCompanion(archived: Value(archived), updatedAt: Value(DateTime.now())),
      );

  Future<int> _countLookups(LookupKind kind) async {
    final count = db.lookups.id.count();
    final query = db.selectOnly(db.lookups)
      ..addColumns([count])
      ..where(db.lookups.storeId.equals(storeId) & db.lookups.kind.equalsValue(kind));
    return (await query.getSingle()).read(count) ?? 0;
  }

  // Money places ----------------------------------------------------------

  Stream<List<MoneyPlace>> watchMoneyPlaces() =>
      (db.select(db.moneyPlaces)
            ..where((p) => p.storeId.equals(storeId) & p.deletedAt.isNull())
            ..orderBy([(p) => OrderingTerm(expression: p.sortOrder)]))
          .watch();

  Future<void> addMoneyPlace({
    required String name,
    required MoneyPlaceKind kind,
    required int openingBalanceZmw,
  }) async {
    final count = db.moneyPlaces.id.count();
    final existing =
        await (db.selectOnly(db.moneyPlaces)
              ..addColumns([count])
              ..where(db.moneyPlaces.storeId.equals(storeId)))
            .getSingle();
    await db
        .into(db.moneyPlaces)
        .insert(
          MoneyPlacesCompanion.insert(
            storeId: storeId,
            name: name.trim(),
            kind: kind,
            openingBalanceZmw: Value(openingBalanceZmw),
            sortOrder: Value(existing.read(count) ?? 0),
          ),
        );
  }

  Future<void> updateMoneyPlace(
    String id, {
    required String name,
    required MoneyPlaceKind kind,
    required int openingBalanceZmw,
  }) => (db.update(db.moneyPlaces)..where((p) => p.id.equals(id))).write(
    MoneyPlacesCompanion(
      name: Value(name.trim()),
      kind: Value(kind),
      openingBalanceZmw: Value(openingBalanceZmw),
      updatedAt: Value(DateTime.now()),
    ),
  );

  Future<void> setMoneyPlaceArchived(String id, bool archived) =>
      (db.update(db.moneyPlaces)..where((p) => p.id.equals(id))).write(
        MoneyPlacesCompanion(archived: Value(archived), updatedAt: Value(DateTime.now())),
      );

  // Agents ----------------------------------------------------------------

  Stream<List<Agent>> watchAgents() =>
      (db.select(db.agents)
            ..where((a) => a.storeId.equals(storeId) & a.deletedAt.isNull())
            ..orderBy([(a) => OrderingTerm(expression: a.name)]))
          .watch();

  /// Rates in US cents per kg, keyed by cargo type id.
  Future<Map<String, int>> agentRates(String agentId) async {
    final rows = await (db.select(
      db.agentRates,
    )..where((r) => r.agentId.equals(agentId) & r.deletedAt.isNull())).get();
    return {for (final r in rows) r.cargoTypeId: r.usdPerKg};
  }

  /// Creates or updates an agent and replaces its rates. Returns the agent id.
  Future<String> saveAgent({
    String? id,
    required String name,
    String? contact,
    required Map<String, int> usdPerKgByCargoType,
  }) {
    return db.transaction(() async {
      final now = DateTime.now();
      final cleanContact = (contact == null || contact.trim().isEmpty) ? null : contact.trim();
      final String agentId;
      if (id == null) {
        final agent = await db
            .into(db.agents)
            .insertReturning(
              AgentsCompanion.insert(storeId: storeId, name: name.trim(), contact: Value(cleanContact)),
            );
        agentId = agent.id;
      } else {
        agentId = id;
        await (db.update(db.agents)..where((a) => a.id.equals(id))).write(
          AgentsCompanion(name: Value(name.trim()), contact: Value(cleanContact), updatedAt: Value(now)),
        );
      }

      final existing = await (db.select(
        db.agentRates,
      )..where((r) => r.agentId.equals(agentId) & r.deletedAt.isNull())).get();
      final byCargo = {for (final r in existing) r.cargoTypeId: r};

      for (final MapEntry(key: cargoTypeId, value: rate) in usdPerKgByCargoType.entries) {
        final current = byCargo.remove(cargoTypeId);
        if (current == null) {
          await db
              .into(db.agentRates)
              .insert(
                AgentRatesCompanion.insert(
                  storeId: storeId,
                  agentId: agentId,
                  cargoTypeId: cargoTypeId,
                  usdPerKg: rate,
                ),
              );
        } else if (current.usdPerKg != rate) {
          await (db.update(db.agentRates)..where((r) => r.id.equals(current.id))).write(
            AgentRatesCompanion(usdPerKg: Value(rate), updatedAt: Value(now)),
          );
        }
      }
      // Rates the user cleared are soft-deleted so the removal can sync.
      for (final stale in byCargo.values) {
        await (db.update(db.agentRates)..where((r) => r.id.equals(stale.id))).write(
          AgentRatesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
        );
      }
      return agentId;
    });
  }

  Future<void> setAgentArchived(String id, bool archived) =>
      (db.update(db.agents)..where((a) => a.id.equals(id))).write(
        AgentsCompanion(archived: Value(archived), updatedAt: Value(DateTime.now())),
      );
}
