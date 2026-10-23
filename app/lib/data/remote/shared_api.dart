// Связь с общим сервером старост (Supabase): читать данные группы может любой студент, писать — только староста по токену.
// Все обращения — вызовы функций сервера (POST /rest/v1/rpc/имя); напрямую к таблицам доступа нет.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain/group_shared.dart';
import '../../domain/teacher_homework.dart';
import '../../domain/web_pair.dart';

/// Ошибка обращения к серверу. [code] — машинное имя (bad_code, code_used, bad_token, too_many, network, server).
class SharedApiException implements Exception {
  const SharedApiException(this.code, [this.details]);
  final String code;
  final String? details;

  /// Понятное сообщение для человека.
  String get message => switch (code) {
        'bad_code' => 'Код не подошёл. Проверьте, что он введён без ошибок',
        'code_used' => 'Этот код уже использован. Попросите выдать новый',
        'too_many_attempts' => 'Слишком много неверных вводов кода. Подождите минуту и повторите',
        'bad_token' => 'Доступ отозван. Введите код заново',
        'too_many' => 'Слишком много записей у группы. Удалите ненужные',
        'file_too_big' => 'Файл слишком большой для общего сервера',
        'bad_pair' => 'Такого входа не найдено. Обновите страницу на компьютере и сканируйте новый код',
        'pair_expired' => 'Код входа устарел или уже использован. Обновите страницу на компьютере',
        'bad_number' => 'Число не подошло. Введите число, которое сейчас показано на экране компьютера',
        'bad_ticket' => 'Загрузка файла не разрешена. Повторите отправку',
        'no_object' => 'Файл не дошёл до сервера. Повторите отправку',
        'bad_file_type' => 'Такие файлы (программы, скрипты) отправлять нельзя',
        'bad_file_name' => 'Название файла не подошло. Переименуйте файл',
        'storage_full' => 'На сервере сейчас нет места для файлов. Дайте студентам ссылку на облако',
        'quota' => 'У группы закончилось место для файлов. Удалите старые ДЗ с файлами',
        'too_many_files' => 'К одному ДЗ можно прикрепить не больше 5 файлов',
        'no_file' => 'Файл не найден на сервере: возможно, староста удалил это ДЗ',
        'forbidden_group' => 'Эта группа не входит в ваш список. Напишите автору приложения, чтобы её добавили',
        'bad_groups' => 'Выберите хотя бы одну группу',
        'rate_limit' => 'Слишком много отправок за час. Подождите немного и повторите',
        'bad_batch' => 'Не удалось изменить это ДЗ. Отправьте его заново',
        'download_limit' => 'Скачали слишком много файлов, лимит исчерпан. Попробуйте позже',
        'storage_not_configured' => 'Сервер ещё не настроен для файлов. Попробуйте позже',
        'network' => 'Нет связи с сервером. Проверьте интернет и повторите',
        _ => 'Ошибка сервера${details == null ? '' : ': $details'}',
      };

  @override
  String toString() => 'SharedApiException($code${details == null ? '' : ', $details'})';
}

/// Случайная метка ввода кода: 32 символа 0-9a-f (128 бит), как ждёт сервер.
String newRedeemNonce([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
}

class SharedApi {
  SharedApi(this.baseUrl, this.key, {http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final String key; // публичный ключ проекта (не секретный)
  final http.Client _client;

  static const _timeout = Duration(seconds: 15);
  static const _fileTimeout = Duration(seconds: 120); // файлы большие, на слабой сети грузятся долго
  // Ввод кода: сервер гасит код сразу, а ответ с токеном мог бы не успеть вернуться. Поэтому ждём дольше обычного
  // (а если всё же не успел, повтор с той же меткой nonce вернёт тот же токен)
  static const _redeemTimeout = Duration(seconds: 30);

  Future<dynamic> _rpc(String function, Map<String, dynamic> args, {Duration timeout = _timeout}) async {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$base/rest/v1/rpc/$function'),
            headers: {'apikey': key, 'Content-Type': 'application/json'},
            body: jsonEncode(args),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const SharedApiException('network');
    } on http.ClientException {
      throw const SharedApiException('network');
    } on Exception {
      // например SocketException на телефоне: нет сети
      throw const SharedApiException('network');
    }

    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return text.isEmpty ? null : jsonDecode(text);
    }
    String? message;
    try {
      message = (jsonDecode(text) as Map<String, dynamic>)['message'] as String?;
    } catch (_) {}
    const known = {'bad_code', 'code_used', 'too_many_attempts', 'bad_token', 'too_many', 'bad_group', 'file_too_big', 'quota', 'too_many_files', 'no_file', 'download_limit', 'forbidden_group', 'bad_groups', 'rate_limit', 'bad_batch', 'bad_pair', 'pair_expired', 'bad_number', 'bad_ticket', 'no_object', 'bad_file_type', 'bad_file_name', 'storage_full', 'storage_not_configured', 'busy'};
    if (message != null && known.contains(message)) throw SharedApiException(message);
    throw SharedApiException('server', message ?? 'HTTP ${response.statusCode}');
  }

  /// Ответ на ввод кода. Сервер отказывает обычным ответом {"message": "bad_code"} (так ошибка не откатывает счётчик
  /// неверных вводов); код ответа при этом 400, но на случай 200 отказ распознаём и по телу.
  Map<String, dynamic> _asRedeemResult(dynamic value) {
    final r = _asMap(value);
    final message = r['message'];
    if (r['token'] == null && message is String) {
      const refusals = {'bad_code', 'code_used', 'too_many_attempts'};
      throw SharedApiException(refusals.contains(message) ? message : 'server', refusals.contains(message) ? null : message);
    }
    return r;
  }

  /// Анонимный счётчик пользователей (раз в сутки): случайный номер установки, платформа, версия.
  Future<void> pingUsage(String install, String platform, String version) =>
      _rpc('ping_usage', {'p_install': install, 'p_platform': platform, 'p_version': version}, timeout: const Duration(seconds: 6));

  /// Данные группы: с [since] — только изменения после этого момента, без — всё.
  Future<Map<String, dynamic>> getGroupData(String group, {String? since}) async =>
      _asMap(await _rpc('get_group_data', {'p_group': group, if (since != null) 'p_since': since}));

  /// Ответ должен быть объектом; иначе сервер ответил не так, как ждёт приложение.
  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    throw const SharedApiException('server', 'неожиданный ответ');
  }

  /// Ввод кода старосты. Возвращает группу и секретный токен для этого телефона.
  /// [nonce] — случайная метка этого ввода (см. [newRedeemNonce]): если ответ потерялся, повтор с той же меткой вернёт тот же токен.
  Future<EditorSession> redeem(String code, {String? nonce}) async {
    final r = _asRedeemResult(await _rpc('redeem_code', {'p_code': code, 'p_nonce': nonce ?? newRedeemNonce()}, timeout: _redeemTimeout));
    return EditorSession(token: r['token'] as String, groupId: r['group_id'] as String);
  }

  /// Проверяет, что токен действует. Возвращает группу.
  Future<String> checkEditor(String token) async {
    final r = await _rpc('check_editor', {'p_token': token});
    if (r is String) return r;
    throw const SharedApiException('server', 'неожиданный ответ');
  }

  Future<void> putOverride(String token, GroupOverrideRow row) => _rpc('put_group_override', {'p_token': token, 'p_row': row.toJson()});

  Future<void> deleteOverride(String token, String id) => _rpc('delete_group_override', {'p_token': token, 'p_id': id});

  /// Стирает правки, сделанные к старому расписанию. Возвращает, сколько стёрто.
  Future<int> clearStale(String token, String keepHash) async =>
      ((await _rpc('clear_stale_group_overrides', {'p_token': token, 'p_keep_hash': keepHash})) as num?)?.toInt() ?? 0;

  Future<void> putHomework(String token, GroupHomeworkRow row) => _rpc('put_group_homework', {'p_token': token, 'p_row': row.toJson()});

  Future<void> deleteHomework(String token, String id) => _rpc('delete_group_homework', {'p_token': token, 'p_id': id});

  /// Загружает файл староста: содержимое передаётся текстом base64 (так просто и работает с любым сервером).
  Future<void> putFile(String token, String id, String name, Uint8List bytes) =>
      _rpc('put_group_file', {'p_token': token, 'p_id': id, 'p_name': name, 'p_data': base64Encode(bytes)}, timeout: _fileTimeout);

  /// Скачивает файл группы по номеру. Читать может любой студент группы.
  /// Файл на сервере лежит либо в базе (ответ с содержимым base64), либо в хранилище (ответ со ссылкой: качаем по ней).
  Future<Uint8List> getFile(String group, String id) async {
    final r = _asMap(await _rpc('get_group_file', {'p_group': group, 'p_id': id}, timeout: _fileTimeout));
    final url = r['url'];
    if (url is String) return _download(url);
    // Postgres вставляет в base64 переносы строк, а Dart их не читает: убираем пробелы и переносы перед разбором
    return base64Decode((r['data'] as String).replaceAll(RegExp(r'\s'), ''));
  }

  /// Качает файл из хранилища по ссылке, которую выдал сервер (только https и только наше хранилище).
  Future<Uint8List> _download(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || !uri.path.startsWith('/storage/v1/object/public/homework/')) {
      throw const SharedApiException('server', 'неожиданная ссылка на файл');
    }
    try {
      final response = await _client.get(uri).timeout(_fileTimeout);
      if (response.statusCode == 200) return response.bodyBytes;
      throw response.statusCode == 400 || response.statusCode == 404 ? const SharedApiException('no_file') : SharedApiException('server', 'HTTP ${response.statusCode}');
    } on SharedApiException {
      rethrow;
    } on Exception {
      throw const SharedApiException('network');
    }
  }

  // ---------- преподаватель ----------

  /// Ввод кода преподавателя: имя, группы и секретный токен для этого телефона.
  Future<TeacherSession> redeemTeacher(String code, {String? nonce}) async {
    final r = _asRedeemResult(await _rpc('redeem_teacher_code', {'p_code': code, 'p_nonce': nonce ?? newRedeemNonce()}, timeout: _redeemTimeout));
    return TeacherSession.fromJson(r);
  }

  /// Отправляет ДЗ группам (или меняет прежнее, если у [batch] есть номер). Возвращает номер пачки.
  Future<String> putTeacherHomework(String token, TeacherHomeworkBatch batch) async {
    final r = await _rpc('put_teacher_homework', {'p_token': token, 'p_row': batch.toJson()});
    if (r is String) return r;
    throw const SharedApiException('server', 'неожиданный ответ');
  }

  Future<void> deleteTeacherHomework(String token, String batchId) => _rpc('delete_teacher_homework', {'p_token': token, 'p_batch': batchId});

  /// Всё, что преподаватель отправил (по пачкам, свежие сроки сверху).
  Future<List<TeacherHomeworkBatch>> getTeacherHomework(String token) async {
    final r = await _rpc('get_teacher_homework', {'p_token': token});
    if (r is! List) throw const SharedApiException('server', 'неожиданный ответ');
    return [for (final b in r) TeacherHomeworkBatch.fromJson(b as Map<String, dynamic>)];
  }

  /// Загружает файл преподавателя (один раз для всех групп отправки).
  Future<void> putTeacherFile(String token, String id, String name, Uint8List bytes) =>
      _rpc('put_teacher_file', {'p_token': token, 'p_id': id, 'p_name': name, 'p_data': base64Encode(bytes)}, timeout: _fileTimeout);

  // ---------- вход на компьютере и файлы в хранилище ----------

  /// Подтверждает вход на компьютере. [ref] — номер запроса из QR (тогда нужно [number] с экрана) или текстовый код.
  Future<void> webPairApprove(String token, String ref, {String? number}) async {
    final r = _asMap(await _rpc('web_pair_approve', {'p_teacher_token': token, 'p_ref': ref, 'p_number': ?number}));
    if (r['ok'] != true) {
      final message = r['message'];
      throw SharedApiException(message is String && _knownApproveRefusals.contains(message) ? message : 'server', null);
    }
  }

  static const _knownApproveRefusals = {'bad_pair', 'pair_expired', 'bad_number', 'too_many_attempts'};

  Future<List<WebSessionInfo>> webSessions(String token) async {
    final r = await _rpc('web_sessions_list', {'p_teacher_token': token});
    if (r is! List) throw const SharedApiException('server', 'неожиданный ответ');
    return [for (final s in r) WebSessionInfo.fromJson(s as Map<String, dynamic>)];
  }

  Future<void> webSessionRevoke(String token, String id) => _rpc('web_session_revoke', {'p_teacher_token': token, 'p_id': id});

  /// Билет на загрузку файлов в хранилище (живёт полчаса, до 5 файлов).
  Future<String> teacherUploadTicket(String token) async {
    final r = _asMap(await _rpc('teacher_upload_ticket', {'p_token': token}));
    final ticket = r['ticket'];
    if (ticket is String) return ticket;
    throw const SharedApiException('server', 'неожиданный ответ');
  }

  /// Кладёт файл в хранилище по билету (имя в хранилище: билет/номер файла). Ограничения проверяет само хранилище: до 15 МБ.
  Future<void> uploadToStorage(String ticket, String id, Uint8List bytes) async {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$base/storage/v1/object/homework/$ticket/$id'),
            headers: {'apikey': key, 'Authorization': 'Bearer $key', 'Content-Type': 'application/octet-stream'},
            body: bytes,
          )
          .timeout(_fileTimeout);
    } on Exception {
      throw const SharedApiException('network');
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (body.contains('EntityTooLarge') || response.statusCode == 413) throw const SharedApiException('file_too_big');
    if (body.contains('AccessDenied') || response.statusCode == 403) throw const SharedApiException('bad_ticket');
    throw SharedApiException('server', 'хранилище: HTTP ${response.statusCode}');
  }

  /// Сообщает серверу, что файл загружен: он проверит объект, размер и квоту и свяжет файл с преподавателем.
  Future<void> registerTeacherFile(String token, String id, String ticket, String name) =>
      _rpc('register_teacher_file', {'p_token': token, 'p_id': id, 'p_ticket': ticket, 'p_name': name});
}
