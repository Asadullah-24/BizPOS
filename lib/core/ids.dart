import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Globally unique row id. Rows created on different phones never collide,
/// which is what makes merging backups safe.
String newId() => _uuid.v4();

int nowMs() => DateTime.now().millisecondsSinceEpoch;
