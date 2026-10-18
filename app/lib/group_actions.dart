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

  /// Сохраняет правки для всей группы. Для одной пары в один день правка только одна — старая заменяется
  /// (как и у личных правок); исключение — «свои» пары (add).
  Future<void> saveOverrides(List<Override> list) async {
    final token = _session.token;
    final hash = await _baseHash();
    final repo = container.read(groupSharedRepositoryProvider)!;
    final current = await repo.cached(_session.groupId);

    for (final o in list) {
      final toReplace = current.overrides.values.where((e) =>
          e.date == o.date && e.pair == o.pair && (o.type == OverrideType.add ? e.type == OverrideType.add : e.type != OverrideType.add));
      for (final old in toReplace) {
        await _api.deleteOverride(token, old.id);
      }
      await _api.putOverride(
        token,
        GroupOverrideRow(
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
        ),
      );
    }
    await _refresh();
  }

  Future<void> deleteOverride(String id) async {
    await _api.deleteOverride(_session.token, id);
    await _refresh();
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
    await _api.putHomework(_session.token, GroupHomeworkRow(id: id ?? newUuid(), subject: subject, text: text, dueDate: due, kind: kind, subgroup: subgroup, files: refs));
    // ДЗ сохранено: локальные копии становятся «скачанными» файлами старосты
    for (final e in local.entries) {
      await filesService!.remember(e.key, e.value);
    }
    await _refresh();
  }

  Future<void> deleteHomework(String id) async {
    await _api.deleteHomework(_session.token, id);
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
