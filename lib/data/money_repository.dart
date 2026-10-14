import 'package:drift/drift.dart';

import 'database.dart';

class PlaceBalance {
  const PlaceBalance({required this.place, required this.balanceZmw});

  final MoneyPlace place;
  final int balanceZmw;
}

/// Balance per money place, derived from every recorded money movement.
class MoneyRepository {
  MoneyRepository(this.db, this.storeId);

  final AppDatabase db;
  final String storeId;

  /// Opening balance minus purchase payments. Sales, shipping, expenses and
  /// transfers join this sum as their milestones land.
  Stream<List<PlaceBalance>> watchBalances() {
    final query = db.customSelect(
      '''
      SELECT mp.*,
        mp.opening_balance_zmw
          - (SELECT COALESCE(SUM(p.paid_zmw), 0) FROM purchases p
               WHERE p.money_place_id = mp.id AND p.deleted_at IS NULL) AS balance
      FROM money_places mp
      WHERE mp.store_id = ? AND mp.deleted_at IS NULL
      ORDER BY mp.sort_order
      ''',
      variables: [Variable.withString(storeId)],
      readsFrom: {db.moneyPlaces, db.purchases},
    );
    return query.watch().map((rows) => [
          for (final row in rows)
            PlaceBalance(place: db.moneyPlaces.map(row.data), balanceZmw: row.read<int>('balance')),
        ]);
  }
}
