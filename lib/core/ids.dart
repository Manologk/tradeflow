import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Globally unique record id. UUIDs let records created offline on different
/// phones merge without collisions once cloud sync arrives.
String newId() => _uuid.v4();
