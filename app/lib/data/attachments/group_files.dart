// Файлы и фото, которые староста прикрепил к ДЗ группы: загрузка на сервер и скачивание студентами.
// Скачанный файл один раз сохраняется в телефоне (как обычное вложение), дальше открывается без интернета.

import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/attachment.dart';
import '../../domain/group_shared.dart';
import '../remote/shared_api.dart';
import 'attachment_store.dart';

/// Лимиты общего сервера (те же числа проверяет и сам сервер).
const maxGroupFileBytes = 8 * 1024 * 1024; // староста: файл лежит в базе сервера

/// Преподаватель: файлы лежат в хранилище сервера (с версии 0.6.0), поэтому можно крупнее.
const maxTeacherFileBytes = 15 * 1024 * 1024;
const maxGroupFilesPerHomework = 5;

// Программы и скрипты преподаватель отправлять не может (так же проверяет сервер)
final _blockedFile = RegExp(r'\.(exe|apk|bat|cmd|com|msi|scr|js|jse|vbs|vbe|wsf|ps1|sh|jar|dll|lnk|reg|hta|cpl)$');

class GroupFiles {
  GroupFiles({required this.api, required this.store, required this.prefs});

  final SharedApi api;
  final AttachmentStore store;
  final SharedPreferences prefs;

  static const _key = 'groupFileCache';

  Map<String, dynamic> _map() {
    try {
      return jsonDecode(prefs.getString(_key) ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Файл, уже лежащий в телефоне (скачанный раньше или загруженный самим старостой). Null — ещё нет.
  Attachment? cached(String fileId) {
    final j = _map()[fileId] as Map<String, dynamic>?;
    if (j == null) return null;
    final a = Attachment(name: j['name'] as String, path: j['path'] as String, sizeBytes: (j['size'] as num?)?.toInt());
    return store.exists(a) ? a : null;
  }

  Future<void> remember(String fileId, Attachment a) {
    final map = _map()..[fileId] = {'name': a.name, 'path': a.path, 'size': a.sizeBytes};
    return prefs.setString(_key, jsonEncode(map));
  }

  /// Стирает из памяти телефона скачанные файлы, которых больше нет ни в одном ДЗ группы (ДЗ удалили или оно устарело:
  /// сервер убирает ДЗ через 3 недели после срока сдачи). [liveIds] — номера файлов, которые ещё нужны. Возвращает, сколько стёрто.
  Future<int> forgetExcept(Set<String> liveIds) async {
    final map = _map();
    var erased = 0;
    for (final id in [...map.keys]) {
      if (liveIds.contains(id)) continue;
      final j = map.remove(id);
      erased++;
      if (j is Map<String, dynamic> && j['path'] is String && j['name'] is String) {
        try {
          await store.delete(Attachment(name: j['name'] as String, path: j['path'] as String, sizeBytes: (j['size'] as num?)?.toInt()));
        } catch (_) {
          // не вышло стереть файл — запись всё равно убираем, телефон сам разберётся с памятью приложения
        }
      }
    }
    if (erased > 0) await prefs.setString(_key, jsonEncode(map));
    return erased;
  }

  /// Скачивает файл (если ещё не скачан) и возвращает его локальную копию.
  Future<Attachment> download(String groupId, GroupFileRef ref) async {
    final have = cached(ref.id);
    if (have != null) return have;
    final Uint8List bytes = await api.getFile(groupId, ref.id);
    final saved = await store.save(PickedFileInfo(name: ref.name, sizeBytes: bytes.length, readBytes: () async => bytes));
    await remember(ref.id, saved);
    return saved;
  }

  /// Загружает файлы на сервер. Возвращает описания для записи ДЗ и пары «номер → локальная копия» (чтобы староста не качал своё же).
  /// Файлы преподавателя идут в хранилище (до 15 МБ); если сервер ещё без хранилища, файлы до 8 МБ уходят старым путём.
  Future<({List<GroupFileRef> refs, Map<String, Attachment> local})> upload(String token, List<Attachment> files, String Function() newId, {bool teacher = false}) async {
    if (files.length > maxGroupFilesPerHomework) throw const SharedApiException('too_many_files');
    final limit = teacher ? maxTeacherFileBytes : maxGroupFileBytes;
    // Читаем и проверяем всё до первой отправки: ничего лишнего на сервер не уйдёт
    final loaded = <(Attachment, Uint8List)>[];
    for (final a in files) {
      final bytes = await store.readBytes(a);
      if (bytes == null) throw const SharedApiException('server', 'файл не найден в памяти телефона');
      if (bytes.length > limit) throw const SharedApiException('file_too_big');
      if (teacher && _blockedFile.hasMatch(a.name.toLowerCase())) throw const SharedApiException('bad_file_type');
      loaded.add((a, bytes));
    }
    String? ticket;
    var legacy = !teacher;
    if (teacher && loaded.isNotEmpty) {
      try {
        ticket = await api.teacherUploadTicket(token);
      } on SharedApiException catch (e) {
        // сервер без хранилища: все файлы не больше 8 МБ можно отправить старым путём
        if (e.code != 'server' || loaded.any((f) => f.$2.length > maxGroupFileBytes)) rethrow;
        legacy = true;
      }
    }
    final refs = <GroupFileRef>[];
    final local = <String, Attachment>{};
    for (final (a, bytes) in loaded) {
      final id = newId();
      final name = cleanFileName(a.name);
      if (legacy) {
        await (teacher ? api.putTeacherFile(token, id, name, bytes) : api.putFile(token, id, name, bytes));
      } else {
        await api.uploadToStorage(ticket!, id, bytes);
        await api.registerTeacherFile(token, id, ticket, name);
      }
      refs.add(GroupFileRef(id: id, name: name, size: bytes.length));
      local[id] = a;
    }
    return (refs: refs, local: local);
  }
}
