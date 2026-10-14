# TradeFlow

Offline Android app for tracking China import purchases, shipping, stock, sales and profit — built for traders who buy on Taobao, Pinduoduo, 1688 and friends and resell locally.

See [docs/PRODUCT_SPEC.md](docs/PRODUCT_SPEC.md) for the admin app spec and [docs/STOREFRONT_SPEC.md](docs/STOREFRONT_SPEC.md) for the online shop.

## Install

Every push builds an APK in GitHub Actions (**Actions → Build → tradeflow-apk**). Tagged versions (`v*`) are attached to **Releases**.

## Develop

Requires Flutter 3.47.

```sh
flutter pub get
dart run build_runner build   # regenerate lib/data/database.g.dart after editing tables
flutter analyze
flutter test
flutter build apk --release
```

Release builds are signed with the key provided through the `TRADEFLOW_KEYSTORE*` / `TRADEFLOW_KEY_*` secrets; without them the APK is debug-signed.
