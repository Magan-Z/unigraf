// Действия преподавателя: ввод кода, отправка ДЗ студентам, изменение и удаление отправленного.
// Всё уходит на сервер по токену преподавателя; без кода можно только смотреть расписание.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_state.dart';
import 'data/remote/shared_api.dart';
import 'data/repositories/group_shared_repository.dart';
import 'domain/attachment.dart';
import 'domain/group_shared.dart';
import 'domain/models.dart';
import 'redeem_nonce.dart';
import 'domain/teacher_homework.dart';
import 'domain/web_pair.dart';

class TeacherActions {
  TeacherActions(this.container);
  final ProviderContainer container;

  factory TeacherActions.of(BuildContext context) => TeacherActions(ProviderScope.containerOf(context));

  SharedApi get _api => container.read(sharedApiProvider) ?? (throw const SharedApiException('server', 'сервер не настроен'));
  TeacherSession get _session => container.read(teacherSessionProvider) ?? (throw const SharedApiException('bad_token'));

  /// Ввод кода преподавателя: сервер выдаёт токен, он сохраняется в телефоне.
  static Future<TeacherSession> redeem(ProviderContainer container, String code) async {
    final api = container.read(sharedApiProvider) ?? (throw const SharedApiException('server', 'сервер не настроен'));
    final session = await redeemWithNonce(
      prefs: container.read(sharedPreferencesProvider),
      kind: 'teacher',
      code: code,
      call: (nonce) => api.redeemTeacher(code.trim(), nonce: nonce),
    );
    await container.read(teacherSessionProvider.notifier).set(session);
    container.invalidate(teacherSentProvider);
    return session;
  }

  /// Отправляет ДЗ группам. Если у [id] есть номер, меняется прежняя отправка. Файлы сначала уходят на сервер.
  /// Возвращает номер отправки.
  Future<String> send({
    String? id,
    required String subject,
    required String text,
    required DateTime due,
    required List<TeacherSentTarget> targets,
    LessonKind? kind,
    List<Attachment> newFiles = const [],
    List<GroupFileRef> keepFiles = const [],
  }) async {
    final filesService = container.read(groupFilesProvider);
    var refs = [...keepFiles];
    var local = <String, Attachment>{};
    if (newFiles.isNotEmpty && filesService != null) {
      final up = await filesService.upload(_session.token, newFiles, newUuid, teacher: true);
      refs = [...refs, ...up.refs];
      local = up.local;
    }
    final batchId = await _api.putTeacherHomework(
      _session.token,
      TeacherHomeworkBatch(id: id, subject: subject, text: text, dueDate: due, kind: kind, targets: targets, files: refs),
    );
    // Отправлено: локальные копии становятся «скачанными» файлами преподавателя (не качать своё же)
    for (final e in local.entries) {
      await filesService!.remember(e.key, e.value);
    }
    container.invalidate(teacherSentProvider);
    return batchId;
  }

  Future<void> delete(String batchId) async {
    await _api.deleteTeacherHomework(_session.token, batchId);
    container.invalidate(teacherSentProvider);
  }

  /// Подтверждает вход на компьютере (по QR: [ref] — номер запроса и [number] с экрана; по тексту: только код).
  Future<void> approveWebLogin(String ref, {String? number}) => _api.webPairApprove(_session.token, ref, number: number);

  Future<List<WebSessionInfo>> webSessions() => _api.webSessions(_session.token);

  Future<void> endWebSession(String id) => _api.webSessionRevoke(_session.token, id);
}
