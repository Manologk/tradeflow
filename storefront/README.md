# TradeFlow Shop (storefront)

Customer-facing anime merch shop: browse, add to cart, order on WhatsApp. Built from the ChicCraze Figma design.
See [../docs/STOREFRONT_SPEC.md](../docs/STOREFRONT_SPEC.md).

```sh
flutter pub get
flutter test
flutter build web --release --no-web-resources-cdn

# Design preview with the test catalog (not the shipped app):
flutter build web -t preview/main.dart -o build/preview --no-web-resources-cdn
```

Until the online database is connected the shop shows "Opening soon".

Font: Encode Sans, SIL Open Font License (`assets/fonts/OFL.txt`).
