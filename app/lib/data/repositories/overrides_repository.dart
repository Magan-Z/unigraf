// Личные правки расписания: «пару отменили», «перенесли в другую аудиторию», «добавил свою пару».
// Хранятся только на телефоне и никуда не отправляются.

import 'package:drift/drift.dart';

import '../../core/week.dart';
import '../../domain/models.dart';
import '../local/database.dart';

class OverridesRepository {
  OverridesRepository(this.db);
  final AppDatabase db;

  Future<List<Override>> all() async {
    final rows = await (db.select(db.overrides)..orderBy([(t) => OrderingTerm.asc(t.date), (t) => OrderingTerm.asc(t.pair)])).get();
    return rows.map(_fromRow).toList();
  }

  /// Сохраняет правку. Для одной пары в один день правка может быть только одна — старая заменяется.
  /// Исключение — «своя пара» (add): у одной пары может быть и обычное занятие, и своё.
  /// Правка «заменить» складывается с прежней заменой той же пары (аудитория, преподаватель, заметка, тип не теряются).
  Future<void> save(Override override) async {
    final day = dayOnly(override.date);
    if (override.type == OverrideType.replace) {
      final olds = await (db.select(db.overrides)
            ..where((t) => t.date.equals(day) & t.pair.equals(override.pair) & t.type.equals(OverrideType.replace.name) & t.repeatWeekly.equals(override.repeatWeekly)))
          .get();
      if (olds.isNotEmpty) override = override.mergedOver(_fromRow(olds.first));
    }
    await (db.delete(db.overrides)
          ..where((t) => t.date.equals(day) & t.pair.equals(override.pair) & t.type.equals(override.type.name)))
        .go();
    // Отмена и замена исключают друг друга
    if (override.type != OverrideType.add) {
      final other = override.type == OverrideType.cancel ? OverrideType.replace : OverrideType.cancel;
      await (db.delete(db.overrides)..where((t) => t.date.equals(day) & t.pair.equals(override.pair) & t.type.equals(other.name))).go();
    }
    await db.into(db.overrides).insert(OverridesCompanion.insert(
          date: day,
          pair: override.pair,
          type: override.type.name,
          subject: Value(override.subject),
          room: Value(override.room),
          teacher: Value(override.teacher),
          note: Value(override.note),
          kind: Value(override.kind?.name),
          repeatWeekly: Value(override.repeatWeekly),
          matchSubject: Value(override.matchSubject),
        ));
  }

  Future<void> delete(int id) => (db.delete(db.overrides)..where((t) => t.id.equals(id))).go();

  /// Убирает все правки пары в этот день («вернуть как было»).
  Future<void> clearPair(DateTime date, int pair) =>
      (db.delete(db.overrides)..where((t) => t.date.equals(dayOnly(date)) & t.pair.equals(pair))).go();

  Override _fromRow(OverrideRow row) => Override(
        id: row.id,
        date: dayOnly(row.date.toUtc()), // drift отдаёт дату в местном времени — возвращаем UTC-полночь
        pair: row.pair,
        type: OverrideType.values.firstWhere((t) => t.name == row.type, orElse: () => OverrideType.replace),
        subject: row.subject,
        room: row.room,
        teacher: row.teacher,
        note: row.note,
        kind: row.kind == null ? null : LessonKind.parse(row.kind!),
        repeatWeekly: row.repeatWeekly,
        matchSubject: row.matchSubject,
      );
}
