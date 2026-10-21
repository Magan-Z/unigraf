// Общие данные группы в телефоне: кэш (чтобы работало без интернета) и обновление с сервера «дельтами».

import 'dart:math';


import '../../domain/group_shared.dart';
import '../local/database.dart';
import '../remote/shared_api.dart';

/// Результат обновления: что нового пришло.
class GroupSyncResult {
  const GroupSyncResult({required this.state, this.newHomework = const [], this.newTeacherHomework = const []});
  final GroupSharedState state;

  /// ДЗ преподавателей, которых раньше в телефоне не было.
  final List<GroupHomeworkRow> newTeacherHomework;

  /// ДЗ старосты, которых раньше в телефоне не было (для уведомления «староста добавил ДЗ»).
  final List<GroupHomeworkRow> newHomework;
}

class GroupSharedRepository {
  GroupSharedRepository(this.db, this.api);
  final AppDatabase db;
  final SharedApi api;

  /// Если телефон не обновлялся дольше, берём всё заново: «надгробия» удалённых строк на сервере живут 30 дней.
  static const fullRefreshAfter = Duration(days: 20);

  /// Небольшой запас по времени: строка, записанная сервером «задним числом», не потеряется.
  static const overlap = Duration(minutes: 1);

  Future<GroupSharedState> cached(String groupId) async {
    final row = await (db.select(db.groupSharedCache)..where((t) => t.groupId.equals(groupId))).getSingleOrNull();
    if (row == null) return GroupSharedState.empty;
    try {
      return GroupSharedState.decode(row.json);
    } catch (_) {
      return GroupSharedState.empty; // повреждённый кэш — просто загрузим заново
    }
  }

  Future<void> _save(String groupId, GroupSharedState state) => db.into(db.groupSharedCache).insertOnConflictUpdate(
        GroupSharedCacheCompanion.insert(groupId: groupId, json: state.encode()),
      );

  /// Меняет кэш прямо в телефоне, не обращаясь к серверу: действия старосты видны ему сразу, а с сервером сверяется следующее обновление.
  Future<void> change(String groupId, GroupSharedState Function(GroupSharedState) edit) async => _save(groupId, edit(await cached(groupId)));

  /// Забирает с сервера изменения и сохраняет в кэш. Ошибки связи пробрасываются: вызывающий решает, показывать ли их.
  Future<GroupSyncResult> sync(String groupId, {DateTime? now}) async {
    final before = await cached(groupId);
    final time = now ?? DateTime.now().toUtc();
    final full = before.since == null || before.syncedAt == null || time.difference(before.syncedAt!) > fullRefreshAfter;

    String? since;
    if (!full) {
      since = DateTime.parse(before.since!).subtract(overlap).toUtc().toIso8601String();
    }
    final delta = await api.getGroupData(groupId, since: since);
    final after = full ? before.replaceWith(delta, now: time) : before.merge(delta, now: time);
    await _save(groupId, after);

    final newHomework = [for (final h in after.homework.values) if (!before.homework.containsKey(h.id)) h];
    final newTeacher = [for (final h in after.teacherHomework.values) if (!before.teacherHomework.containsKey(h.id)) h];
    return GroupSyncResult(state: after, newHomework: newHomework, newTeacherHomework: newTeacher);
  }

  /// Забыть всё (например, студент сменил группу).
  Future<void> clear(String groupId) => (db.delete(db.groupSharedCache)..where((t) => t.groupId.equals(groupId))).go();
}

/// Случайный номер для новой строки (UUID v4): сервер принимает номер от клиента, чтобы правку можно было повторить без дублей.
String newUuid([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) => b.sublist(from, to).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
