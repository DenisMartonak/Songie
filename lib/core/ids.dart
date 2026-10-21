import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// New random UUID v4 string.
String newId() => _uuid.v4();
