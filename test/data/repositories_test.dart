import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeflow/data/database.dart';
import 'package:tradeflow/data/settings_repository.dart';
import 'package:tradeflow/data/setup_repository.dart';

void main() {
  late AppDatabase db;
  late SetupRepository setup;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    setup = SetupRepository(db);
  });

  tearDown(() => db.close());

  Future<SettingsRepository> setUpStore() async {
    final storeId = await setup.completeSetup(
      storeName: 'Mano Imports',
      places: const [
        OpeningPlace(name: 'Card', kind: MoneyPlaceKind.card, balanceZmw: 150000),
        OpeningPlace(name: 'Cash', kind: MoneyPlaceKind.cash, balanceZmw: 25050),
      ],
      stock: const [OpeningStockEntry(productName: 'Earbuds', qty: 4, unitCostZmw: 12000)],
    );
    return SettingsRepository(db, storeId);
  }

  test('no store before setup', () async {
    expect(await setup.watchStore().first, isNull);
  });

  test('setup creates store, places, default lists and opening stock', () async {
    final settings = await setUpStore();

    final store = await setup.watchStore().first;
    expect(store?.name, 'Mano Imports');

    final places = await settings.watchMoneyPlaces().first;
    expect(places.map((p) => (p.name, p.openingBalanceZmw)), [('Card', 150000), ('Cash', 25050)]);

    final cargo = await settings.watchLookups(LookupKind.cargoType).first;
    expect(cargo.map((c) => c.name), ['General', 'Sensitive (battery/liquid)']);
    final platforms = await settings.watchLookups(LookupKind.platform).first;
    expect(platforms.map((p) => p.name), contains('1688'));

    final stock = await db.select(db.openingStockItems).get();
    expect(stock.single.qty, 4);
    final product = await db.select(db.products).getSingle();
    expect(product.name, 'Earbuds');
    expect(stock.single.productId, product.id);
  });

  test('every record carries the store id and a uuid', () async {
    final settings = await setUpStore();
    final lookups = await db.select(db.lookups).get();
    expect(lookups.every((l) => l.storeId == settings.storeId), isTrue);
    expect(lookups.map((l) => l.id).toSet().length, lookups.length);
    expect(lookups.first.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
  });

  test('lookups can be added, renamed and archived', () async {
    final settings = await setUpStore();
    await settings.addLookup(LookupKind.channel, '  Instagram ');
    var channels = await settings.watchLookups(LookupKind.channel).first;
    final insta = channels.last;
    expect(insta.name, 'Instagram');

    await settings.renameLookup(insta.id, 'Instagram DM');
    await settings.setLookupArchived(insta.id, true);
    channels = await settings.watchLookups(LookupKind.channel).first;
    final updated = channels.firstWhere((c) => c.id == insta.id);
    expect(updated.name, 'Instagram DM');
    expect(updated.archived, isTrue);
    expect(updated.updatedAt.isBefore(insta.createdAt), isFalse);
  });

  test('money places can be added and edited', () async {
    final settings = await setUpStore();
    await settings.addMoneyPlace(
      name: 'Airtel Money',
      kind: MoneyPlaceKind.mobileMoney,
      openingBalanceZmw: 5000,
    );
    var places = await settings.watchMoneyPlaces().first;
    expect(places.last.name, 'Airtel Money');
    expect(places.last.sortOrder, 2);

    await settings.updateMoneyPlace(
      places.last.id,
      name: 'MTN MoMo',
      kind: MoneyPlaceKind.mobileMoney,
      openingBalanceZmw: 7000,
    );
    places = await settings.watchMoneyPlaces().first;
    expect((places.last.name, places.last.openingBalanceZmw), ('MTN MoMo', 7000));
  });

  test('agent rates are created, updated and cleared', () async {
    final settings = await setUpStore();
    final cargo = await settings.watchLookups(LookupKind.cargoType).first;
    final general = cargo[0].id;
    final sensitive = cargo[1].id;

    final agentId = await settings.saveAgent(
      name: 'Speedy Cargo',
      contact: ' ',
      usdPerKgByCargoType: {general: 900, sensitive: 1400},
    );
    expect(await settings.agentRates(agentId), {general: 900, sensitive: 1400});
    final agent = (await settings.watchAgents().first).single;
    expect(agent.contact, isNull);

    await settings.saveAgent(id: agentId, name: 'Speedy Cargo', usdPerKgByCargoType: {general: 950});
    expect(await settings.agentRates(agentId), {general: 950});

    // The cleared rate is soft-deleted, not erased, so it can sync later.
    final allRates = await db.select(db.agentRates).get();
    expect(allRates.where((r) => r.deletedAt != null).single.cargoTypeId, sensitive);
  });

  test('foreign keys are enforced', () async {
    await setUpStore();
    await expectLater(
      db
          .into(db.lookups)
          .insert(LookupsCompanion.insert(storeId: 'missing-store', kind: LookupKind.channel, name: 'Bad')),
      throwsA(isA<SqliteException>()),
    );
  });
}
