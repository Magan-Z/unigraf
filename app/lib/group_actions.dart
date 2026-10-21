// Действия старосты: изменить, отменить, перенести пару для всей группы; задать ДЗ всей группе.
// Каждое действие отправляется на сервер по токену старосты, затем телефон сразу обновляет общие данные.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_state.dart';
import 'data/remote/shared_api.dart';
import 'data/repositories/group_shared_repository.dart';
import 'domain/attachment.dart';
import 'domain/group_shared.dart';
import 'domain/models.dart';
import 'redeem_nonce.dart';

class GroupEditorActions {
  GroupEditorActions(this.container);
  final ProviderContainer container;

  factory GroupEditorActions.of(BuildContext context) => GroupEditorActions(ProviderScope.containerOf(context));

  SharedApi get _api => container.read(sharedApiProvider) ?? (throw const SharedApiException('server', 'сервер не настроен'));
  EditorSession get _session => container.read(editorProvider) ?? (throw const SharedApiException('bad_token'));

  /// Хеш текущего расписания группы: к нему привязываются правки (при новом расписании они устаревают).
  Future<String> _baseHash() async {
    final index = await container.read(indexProvider.future);
    return index.findGroup(_session.groupId)?.hash ?? '';
  }

  Future<void> _refresh() => syncGroupShared(container);

  GroupSharedRepository get _repo => container.read(groupSharedRepositoryProvider)!;

  /// Староста видит своё действие сразу: меняем кэш в телефоне, не дожидаясь ответа сервера (он уходит следом).
  Future<void> _showNow(GroupSharedState Function(GroupSharedState) edit) async {
    await _repo.change(_session.groupId, edit);
    container.invalidate(groupSharedProvider);
  }

  /// Сохраняет правки для всей группы. Для одной пары в один день правка только одна — старая заменяется
  /// (как и у личных правок); исключение — «свои» пары (add).
  Future<void> saveOverrides(List<Override> list) async {
    final token = _session.token;
    final hash = await _baseHash();
    final current = await _repo.cached(_session.groupId);

    for (var o in list) {
      final same = [
        for (final e in current.overrides.values)
          if (e.date == o.date && e.pair == o.pair && (o.type == OverrideType.add ? e.type == OverrideType.add : e.type != OverrideType.add)) e,
      ];
      final toReplace = [for (final e in same) e.id];
      // «Заменить» складывается с прежней заменой этой пары: аудитория, заметка, тип (аттестация) не теряются
      if (o.type == OverrideType.replace) {
        final before = same.where((e) => e.type == OverrideType.replace && e.repeatWeekly == o.repeatWeekly);
        if (before.isNotEmpty) o = o.mergedOver(before.first.toOverride());
      }
      for (final old in toReplace) {
        await _api.deleteOverride(token, old);
      }
      final row = GroupOverrideRow(
        id: newUuid(),
        baseHash: hash,
        date: o.date,
        pair: o.pair,
        type: o.type,
        subject: o.subject,
        room: o.room,
        teacher: o.teacher,
        note: o.note,
        kind: o.kind,
        repeatWeekly: o.repeatWeekly,
        matchSubject: o.matchSubject,
      );
      await _api.putOverride(token, row);
      await _showNow((s) => s.withoutOverrides(toReplace).withOverrides([row]));
    }
    await _refresh();
  }

  /// Убирает правки. Они исчезают у старосты сразу; если сервер не ответил, правки возвращаются и показывается ошибка.
  Future<void> deleteOverrides(Iterable<String> ids) async {
    final token = _session.token;
    final order = ids.toSet().toList();
    final before = await _repo.cached(_session.groupId);
    final rows = {for (final id in order) if (before.overrides[id] != null) id: before.overrides[id]!};
    await _showNow((s) => s.withoutOverrides(order));
    final done = <String>{};
    try {
      for (final id in order) {
        await _api.deleteOverride(token, id);
        done.add(id);
      }
    } catch (_) {
      await _showNow((s) => s.withOverrides([for (final e in rows.entries) if (!done.contains(e.key)) e.value]));
      rethrow;
    }
    await _refresh();
  }

  Future<void> deleteOverride(String id) => deleteOverrides([id]);

  /// Убрать правку из списка. Перенос пары — это отмена на старом месте и своя пара на новом: убираются обе.
  Future<void> removeEdit(String id) async {
    final state = await _repo.cached(_session.groupId);
    final row = state.overrides[id];
    await deleteOverrides(row == null ? [id] : [for (final o in state.withMovePartner(row)) o.id]);
  }

  /// «Убрать правку старосты» у пары на экране: все правки группы, которые на неё действуют.
  /// Если пару переносили, возвращается и отмена на старом месте.
  Future<void> removeLessonEdits(ResolvedLesson lesson) async {
    final state = await _repo.cached(_session.groupId);
    final ids = <String>{};
    for (final o in state.overrides.values) {
      if (o.pair != lesson.pair || !o.toOverride().appliesOn(lesson.date)) continue;
      final affectsLesson = o.type == OverrideType.add ? (o.subject ?? 'Занятие') == lesson.subject : o.matchSubject == null || o.matchSubject == lesson.subject;
      if (affectsLesson) ids.addAll([for (final p in state.withMovePartner(o)) p.id]);
    }
    await deleteOverrides(ids);
  }

  /// Задать ДЗ для всей группы (или изменить существующее, если указан [id]).
  /// [files] — файлы и фото из окна «Добавить ДЗ»: сначала они уходят на сервер, потом сохраняется само ДЗ со списком файлов.
  Future<void> saveHomework({
    String? id,
    required String subject,
    required String text,
    required DateTime due,
    LessonKind? kind,
    int? subgroup,
    List<Attachment> files = const [],
  }) async {
    final filesService = container.read(groupFilesProvider);
    var refs = <GroupFileRef>[];
    var local = <String, Attachment>{};
    if (files.isNotEmpty && filesService != null) {
      final up = await filesService.upload(_session.token, files, newUuid);
      refs = up.refs;
      local = up.local;
    }
    final row = GroupHomeworkRow(id: id ?? newUuid(), subject: subject, text: text, dueDate: due, kind: kind, subgroup: subgroup, files: refs);
    await _api.putHomework(_session.token, row);
    // ДЗ сохранено: локальные копии становятся «скачанными» файлами старосты
    for (final e in local.entries) {
      await filesService!.remember(e.key, e.value);
    }
    await _showNow((s) => s.withHomework(row));
    await _refresh();
  }

  /// Удалить ДЗ у всей группы. У старосты оно пропадает сразу; если сервер не ответил, ДЗ возвращается и показывается ошибка.
  Future<void> deleteHomework(String id) async {
    final token = _session.token;
    final row = (await _repo.cached(_session.groupId)).homework[id];
    await _showNow((s) => s.withoutHomework(id));
    try {
      await _api.deleteHomework(token, id);
    } catch (_) {
      if (row != null) await _showNow((s) => s.withHomework(row));
      rethrow;
    }
    await _refresh();
  }

  /// Ввод кода старосты: сервер выдаёт токен, он сохраняется в телефоне.
  static Future<EditorSession> redeem(ProviderContainer container, String code) async {
    final api = container.read(sharedApiProvider) ?? (throw const SharedApiException('server', 'сервер не настроен'));
    final session = await redeemWithNonce(
      prefs: container.read(sharedPreferencesProvider),
      kind: 'editor',
      code: code,
      call: (nonce) => api.redeem(code.trim(), nonce: nonce),
    );
    await container.read(editorProvider.notifier).set(session);
    return session;
  }
}
