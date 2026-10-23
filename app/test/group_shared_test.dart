// Общие данные группы: разбор ответов сервера, дельта-обновление, ошибки и кэш.

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unigraf/data/local/database.dart';
import 'package:unigraf/data/remote/shared_api.dart';
import 'package:unigraf/data/repositories/group_shared_repository.dart';
import 'package:unigraf/domain/group_shared.dart';
import 'package:unigraf/domain/models.dart';
import 'package:unigraf/domain/teacher_homework.dart';
import 'package:unigraf/redeem_nonce.dart';

import 'support/fakes.dart';

/// Поддельный сервер: запоминает вызовы и отвечает заранее заданным.
class FakeServer {
  final calls = <String, List<Map<String, dynamic>>>{};
  final responses = <String, Object Function(Map<String, dynamic> args)>{};
  int failWith = 0; // HTTP-код ошибки (0 — без ошибки)
  String failMessage = '';

  http.Client get client => MockClient((request) async {
        final fn = request.url.pathSegments.last;
        final args = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;
        calls.putIfAbsent(fn, () => []).add(args);
        expect(request.headers['apikey'], 'test-key');
        expect(request.url.path, startsWith('/rest/v1/rpc/'));
        if (failWith != 0) return http.Response.bytes(utf8.encode(jsonEncode({'message': failMessage})), failWith);
        final response = responses[fn];
        if (response == null) return http.Response('', 204);
        return http.Response.bytes(utf8.encode(jsonEncode(response(args))), 200);
      });
}

Map<String, dynamic> _override(String id, {String hash = 'h1', String room = '3-33', bool deleted = false, int pair = 4}) => {
      'id': id,
      'base_hash': hash,
      'date': '2026-10-14',
      'pair': pair,
      'type': 'replace',
      'subject': null,
      'room': room,
      'teacher': null,
      'note': 'староста',
      'kind': null,
      'repeat_weekly': false,
      'match_subject': null,
      'deleted': deleted,
      'updated_at': '2026-10-09T12:00:00+00:00',
    };

Map<String, dynamic> _homework(String id, {String text = 'Читать главу 3', bool deleted = false}) => {
      'id': id,
      'subject': 'Философия',
      'body': text,
      'due_date': '2026-10-14',
      'kind': null,
      'deleted': deleted,
      'updated_at': '2026-10-09T12:00:00+00:00',
    };

void main() {
  group('Разбор и слияние (GroupSharedState)', () {
    test('полная загрузка: правки и ДЗ читаются, дата — день без времени', () {
      final state = GroupSharedState.empty.replaceWith({
        'server_time': '2026-10-09T12:00:00.5+00:00',
        'overrides': [_override('a')],
        'homework': [_homework('h')],
      });
      expect(state.overrides['a']!.room, '3-33');
      expect(state.overrides['a']!.date, DateTime.utc(2026, 10, 14));
      expect(state.overrides['a']!.type, OverrideType.replace);
      expect(state.homeworkList.single.text, 'Читать главу 3');
      expect(state.since, '2026-10-09T12:00:00.5+00:00');
    });

    test('дельта: изменённая строка заменяется, удалённая пропадает, новая добавляется', () {
      var state = GroupSharedState.empty.replaceWith({
        'server_time': 't1',
        'overrides': [_override('a'), _override('b', pair: 3)],
        'homework': [_homework('h')],
      });
      state = state.merge({
        'server_time': 't2',
        'overrides': [_override('a', room: '1-11'), _override('b', deleted: true), _override('c', pair: 2)],
        'homework': [_homework('h', deleted: true)],
      });
      expect(state.overrides.keys.toSet(), {'a', 'c'});
      expect(state.overrides['a']!.room, '1-11');
      expect(state.homework, isEmpty);
      expect(state.since, 't2');
    });

    test('правки к старому расписанию (другой хеш) не действуют', () {
      final state = GroupSharedState.empty.replaceWith({
        'overrides': [_override('a', hash: 'старый'), _override('b', hash: 'новый')],
        'homework': [],
      });
      expect(state.activeOverrides('новый').map((o) => o.id), ['b']);
      expect(state.staleOverrides('новый').map((o) => o.id), ['a']);
      expect(state.activeOverrides(null), hasLength(2)); // хеш неизвестен — ничего не прячем
    });

    test('преобразование в Override помечает правку как правку старосты', () {
      final o = GroupSharedState.empty.replaceWith({'overrides': [_override('a')], 'homework': []}).overrides['a']!.toOverride();
      expect(o.fromGroup, isTrue);
      expect(o.remoteId, 'a');
      expect(o.room, '3-33');
    });

    test('кэш: сохранить и прочитать без потерь', () {
      final state = GroupSharedState.empty.replaceWith({
        'server_time': 't1',
        'overrides': [_override('a')],
        'homework': [_homework('h')],
      }, now: DateTime.utc(2026, 10, 9, 12));
      final back = GroupSharedState.decode(state.encode());
      expect(back.overrides['a']!.room, '3-33');
      expect(back.homework['h']!.text, 'Читать главу 3');
      expect(back.since, 't1');
      expect(back.syncedAt, DateTime.utc(2026, 10, 9, 12));
    });
  });

  group('SharedApi', () {
    late FakeServer server;
    late SharedApi api;
    setUp(() {
      server = FakeServer();
      api = SharedApi('https://example.test/', 'test-key', client: server.client);
    });

    test('ввод кода: возвращает группу и токен', () async {
      server.responses['redeem_code'] = (_) => {'group_id': 'ofo-1-bi-25', 'token': 'секрет'};
      final session = await api.redeem('ABCD123456');
      expect(session.groupId, 'ofo-1-bi-25');
      expect(session.token, 'секрет');
      expect(server.calls['redeem_code']!.single['p_code'], 'ABCD123456');
    });

    test('ввод кода: уходит случайная метка ввода (nonce), заданная метка передаётся как есть', () async {
      server.responses['redeem_code'] = (_) => {'group_id': 'ofo-1-bi-25', 'token': 'секрет'};
      await api.redeem('ABCD123456');
      await api.redeem('ABCD123456', nonce: 'a' * 32);
      final first = server.calls['redeem_code']![0]['p_nonce'] as String;
      expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(server.calls['redeem_code']![1]['p_nonce'], 'a' * 32);
      expect(newRedeemNonce(), isNot(newRedeemNonce()));
    });

    test('отказ приходит обычным ответом с message (так сервер не откатывает счётчик неверных вводов)', () async {
      // сервер отвечает HTTP 400 с телом {"message": ...}; на случай 200 с тем же телом отказ тоже распознаётся
      for (final message in ['bad_code', 'code_used', 'too_many_attempts']) {
        server.responses['redeem_code'] = (_) => {'message': message};
        await expectLater(api.redeem('x'), throwsA(isA<SharedApiException>().having((e) => e.code, 'code', message)));
      }
      server.responses['redeem_code'] = (_) => {'message': 'странное'};
      await expectLater(api.redeem('x'), throwsA(isA<SharedApiException>().having((e) => e.code, 'code', 'server')));
    });

    test('ошибки сервера превращаются в понятные сообщения', () async {
      for (final (message, text) in [
        ('bad_code', 'Код не подошёл'),
        ('code_used', 'уже использован'),
        ('too_many_attempts', 'Подождите минуту'),
        ('bad_token', 'отозван'),
        ('too_many', 'Слишком много'),
        ('download_limit', 'Попробуйте позже'),
        ('bad_number', 'Число не подошло'),
        ('bad_pair', 'Такого входа не найдено'),
        ('pair_expired', 'устарел'),
        ('bad_file_type', 'отправлять нельзя'),
        ('storage_full', 'ссылку на облако'),
      ]) {
        server.failWith = 400;
        server.failMessage = message;
        await expectLater(
          api.redeem('x'),
          throwsA(isA<SharedApiException>().having((e) => e.code, 'code', message).having((e) => e.message, 'message', contains(text))),
        );
      }
    });

    test('неизвестная ошибка — «ошибка сервера» с подробностью', () async {
      server.failWith = 500;
      server.failMessage = 'что-то сломалось';
      await expectLater(api.getGroupData('ofo-1-bi-25'), throwsA(isA<SharedApiException>().having((e) => e.message, 'message', contains('что-то сломалось'))));
    });

    test('нет сети — «нет связи»', () async {
      final offline = SharedApi('https://example.test', 'k', client: MockClient((_) async => throw http.ClientException('нет сети')));
      await expectLater(offline.getGroupData('ofo-1-bi-25'), throwsA(isA<SharedApiException>().having((e) => e.code, 'code', 'network')));
    });

    test('запись правки и ДЗ отправляет токен и строку', () async {
      final row = GroupOverrideRow.fromJson(_override('a'));
      await api.putOverride('tok', row);
      await api.putHomework('tok', GroupHomeworkRow.fromJson(_homework('h')));
      await api.deleteOverride('tok', 'a');
      await api.deleteHomework('tok', 'h');
      expect(server.calls['put_group_override']!.single['p_token'], 'tok');
      expect((server.calls['put_group_override']!.single['p_row'] as Map)['room'], '3-33');
      expect((server.calls['put_group_homework']!.single['p_row'] as Map)['body'], 'Читать главу 3');
      expect(server.calls['delete_group_override']!.single['p_id'], 'a');
      expect(server.calls['delete_group_homework']!.single['p_id'], 'h');
    });

    test('адрес склеивается правильно с / на конце и без него', () async {
      server.responses['get_group_data'] = (_) => {'server_time': 't', 'overrides': [], 'homework': []};
      await SharedApi('https://example.test', 'test-key', client: server.client).getGroupData('ofo-1-bi-25');
      await api.getGroupData('ofo-1-bi-25');
      expect(server.calls['get_group_data'], hasLength(2));
    });
  });

  group('GroupSharedRepository', () {
    late AppDatabase db;
    late FakeServer server;
    late GroupSharedRepository repo;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      server = FakeServer();
      repo = GroupSharedRepository(db, SharedApi('https://example.test', 'test-key', client: server.client));
    });
    tearDown(() => db.close());

    test('первый раз грузит всё (без p_since), потом — только изменения с запасом в минуту', () async {
      server.responses['get_group_data'] = (args) => args.containsKey('p_since')
          ? {'server_time': '2026-10-09T12:10:00+00:00', 'overrides': [_override('a', room: '1-11')], 'homework': []}
          : {'server_time': '2026-10-09T12:00:00+00:00', 'overrides': [_override('a')], 'homework': [_homework('h')]};

      final first = await repo.sync('ofo-1-bi-25', now: DateTime.utc(2026, 10, 9, 12));
      expect(server.calls['get_group_data']!.first.containsKey('p_since'), isFalse);
      expect(first.state.overrides['a']!.room, '3-33');
      expect(first.newHomework.single.id, 'h');

      final second = await repo.sync('ofo-1-bi-25', now: DateTime.utc(2026, 10, 9, 12, 10));
      final since = server.calls['get_group_data']!.last['p_since'] as String;
      expect(DateTime.parse(since), DateTime.utc(2026, 10, 9, 11, 59)); // 12:00 минус минута запаса
      expect(second.state.overrides['a']!.room, '1-11'); // изменилось
      expect(second.state.homework, hasLength(1)); // ДЗ не потерялось
      expect(second.newHomework, isEmpty);
    });

    test('новое ДЗ в дельте попадает в newHomework (для уведомления)', () async {
      server.responses['get_group_data'] = (args) => args.containsKey('p_since')
          ? {'server_time': 't2', 'overrides': [], 'homework': [_homework('h2', text: 'Новое')]}
          : {'server_time': '2026-10-09T12:00:00+00:00', 'overrides': [], 'homework': [_homework('h')]};
      await repo.sync('ofo-1-bi-25', now: DateTime.utc(2026, 10, 9, 12));
      final r = await repo.sync('ofo-1-bi-25', now: DateTime.utc(2026, 10, 9, 13));
      expect(r.newHomework.map((h) => h.id), ['h2']);
    });

    test('кэш живёт между запусками, ошибка сети его не стирает', () async {
      server.responses['get_group_data'] = (_) => {'server_time': '2026-10-09T12:00:00+00:00', 'overrides': [_override('a')], 'homework': []};
      await repo.sync('ofo-1-bi-25', now: DateTime.utc(2026, 10, 9, 12));

      server.failWith = 500;
      server.failMessage = 'упало';
      await expectLater(repo.sync('ofo-1-bi-25', now: DateTime.utc(2026, 10, 9, 13)), throwsA(isA<SharedApiException>()));
      expect((await repo.cached('ofo-1-bi-25')).overrides.keys, ['a']);
      expect((await repo.cached('другая-группа')).overrides, isEmpty);
    });

    test('если телефон давно не обновлялся (> 20 дней) — загрузка заново целиком', () async {
      server.responses['get_group_data'] = (_) => {'server_time': '2026-10-09T12:00:00+00:00', 'overrides': [_override('a')], 'homework': []};
      await repo.sync('ofo-1-bi-25', now: DateTime.utc(2026, 10, 9, 12));
      await repo.sync('ofo-1-bi-25', now: DateTime.utc(2026, 11, 20));
      expect(server.calls['get_group_data']!.last.containsKey('p_since'), isFalse);
    });

    test('повреждённый кэш не ломает приложение', () async {
      await db.customStatement("INSERT INTO group_shared_cache (group_id, json) VALUES ('ofo-1-bi-25', 'не json')");
      expect((await repo.cached('ofo-1-bi-25')).overrides, isEmpty);
    });

    test('newUuid: формат UUID v4, значения не повторяются', () {
      final a = newUuid(), b = newUuid();
      expect(a, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(a, isNot(b));
    });
  });

  group('ДЗ преподавателей', () {
    Map<String, dynamic> teacherRow(String id, {String author = 'Халиев М.С-У.', bool deleted = false, String text = 'Номера 1-5'}) => {
          'id': id,
          'subject': 'Математика',
          'body': text,
          'due_date': '2026-10-20',
          'kind': null,
          'subgroup': null,
          'files': <Map<String, dynamic>>[],
          'author': author,
          'deleted': deleted,
          'updated_at': '2026-10-09T12:00:00+00:00',
        };

    test('дельта: ДЗ преподавателей читаются отдельно от ДЗ старосты, у них есть автор; удалённое пропадает', () {
      var state = const GroupSharedState().merge({
        'server_time': 't1',
        'overrides': [],
        'homework': [_homework('h1')],
        'teacher_homework': [teacherRow('t1'), teacherRow('t2')],
      });
      expect(state.homework.keys, ['h1']);
      expect(state.teacherHomework.keys, containsAll(['t1', 't2']));
      expect(state.teacherHomework['t1']!.author, 'Халиев М.С-У.');
      expect(state.homework['h1']!.author, isNull);

      state = state.merge({'server_time': 't2', 'teacher_homework': [teacherRow('t1', deleted: true), teacherRow('t2', text: 'Новое')]});
      expect(state.teacherHomework.keys, ['t2']);
      expect(state.teacherHomework['t2']!.text, 'Новое');
    });

    test('сервер старой версии без ключа teacher_homework не ломает разбор', () {
      final state = const GroupSharedState().merge({'server_time': 't', 'overrides': [], 'homework': [_homework('h1')]});
      expect(state.teacherHomework, isEmpty);
    });

    test('кэш: сохраняется с ДЗ преподавателей, а кэш прежних версий (без этого поля) читается', () {
      final state = const GroupSharedState().merge({'server_time': 't', 'teacher_homework': [teacherRow('t1')]});
      final again = GroupSharedState.decode(state.encode());
      expect(again.teacherHomework['t1']!.author, 'Халиев М.С-У.');

      final old = jsonEncode({'since': 't', 'syncedAt': null, 'overrides': [], 'homework': [_homework('h1')]});
      expect(GroupSharedState.decode(old).teacherHomework, isEmpty);
    });

    test('обновление: новое ДЗ преподавателя попадает в newTeacherHomework (для уведомления)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final server = FakeServer();
      final repo = GroupSharedRepository(db, SharedApi('https://example.test', 'test-key', client: server.client));
      server.responses['get_group_data'] = (_) => {'server_time': '2026-10-09T12:05:00+00:00', 'overrides': [], 'homework': [], 'teacher_homework': [teacherRow('t1')]};
      final first = await repo.sync('ofo-1-bi-25');
      expect(first.newTeacherHomework.single.id, 't1');
      expect(first.newHomework, isEmpty);
      final second = await repo.sync('ofo-1-bi-25');
      expect(second.newTeacherHomework, isEmpty); // уже известно
    });
  });

  group('SharedApi: преподаватель', () {
    late FakeServer server;
    late SharedApi api;
    setUp(() {
      server = FakeServer();
      api = SharedApi('https://example.test', 'test-key', client: server.client);
    });

    test('ввод кода: имя, группы и токен', () async {
      server.responses['redeem_teacher_code'] = (_) => {'teacher': 'Халиев М.С-У.', 'groups': ['ofo-1-bi-25', 'ofo-2-bi-25'], 'token': 'tok'};
      final session = await api.redeemTeacher('ABC');
      expect(session.teacher, 'Халиев М.С-У.');
      expect(session.groups, ['ofo-1-bi-25', 'ofo-2-bi-25']);
      expect(session.token, 'tok');
      expect(server.calls['redeem_teacher_code']!.single['p_code'], 'ABC');
      expect(server.calls['redeem_teacher_code']!.single['p_nonce'], matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('отправка: токен, группы с подгруппой и файлы уходят строкой; возвращается номер отправки', () async {
      server.responses['put_teacher_homework'] = (_) => 'batch-1';
      final id = await api.putTeacherHomework(
        'tok',
        TeacherHomeworkBatch(
          subject: 'Математика',
          text: 'Номера 1-5',
          dueDate: DateTime.utc(2026, 10, 20),
          targets: const [TeacherSentTarget(groupId: 'ofo-1-bi-25'), TeacherSentTarget(groupId: 'ofo-2-bi-25', subgroup: 2)],
        ),
      );
      expect(id, 'batch-1');
      final sent = server.calls['put_teacher_homework']!.single;
      expect(sent['p_token'], 'tok');
      final row = sent['p_row'] as Map;
      expect(row['due_date'], '2026-10-20');
      expect(row['groups'], [
        {'id': 'ofo-1-bi-25'},
        {'id': 'ofo-2-bi-25', 'subgroup': 2},
      ]);
      expect(row.containsKey('batch_id'), isFalse); // новая отправка
    });

    test('список отправленного читается пачками', () async {
      server.responses['get_teacher_homework'] = (_) => [
            {
              'batch_id': 'b1',
              'subject': 'Математика',
              'body': 'Номера 1-5',
              'due_date': '2026-10-20',
              'kind': null,
              'files': [],
              'groups': [
                {'id': 'ofo-1-bi-25', 'subgroup': null},
              ],
            },
          ];
      final list = await api.getTeacherHomework('tok');
      expect(list.single.id, 'b1');
      expect(list.single.targets.single.groupId, 'ofo-1-bi-25');
    });

    test('ошибки сервера преподавателя превращаются в понятные сообщения', () async {
      for (final (message, text) in [
        ('forbidden_group', 'не входит в ваш список'),
        ('bad_groups', 'хотя бы одну группу'),
        ('rate_limit', 'Слишком много отправок'),
        ('bad_token', 'Доступ отозван'),
        ('code_used', 'уже использован'),
        ('too_many_attempts', 'Подождите минуту'),
        ('bad_code', 'Код не подошёл'),
      ]) {
        server.failWith = 400;
        server.failMessage = message;
        await expectLater(
          api.redeemTeacher('x'),
          throwsA(isA<SharedApiException>().having((e) => e.code, 'code', message).having((e) => e.message, 'message', contains(text))),
        );
      }
    });
  });

  group('Ввод кода без потерь (метка nonce)', () {
    late FakeBackend backend;
    late SharedApi api;
    late SharedPreferences prefs;
    setUp(() async {
      backend = FakeBackend();
      api = backend.api();
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    Future<EditorSession> enter(String code) =>
        redeemWithNonce(prefs: prefs, kind: 'editor', code: code, call: (nonce) => api.redeem(code.trim(), nonce: nonce));

    test('потерянный ответ: код погашен, но повтор того же кода возвращает тот же токен', () async {
      backend.loseNextRedeemResponse = true;
      await expectLater(enter('goodcode'), throwsA(isA<SharedApiException>().having((e) => e.code, 'code', 'network')));
      expect(prefs.getString('redeemNonce.editor'), startsWith('GOODCODE|')); // метка осталась в телефоне
      // повтор (в том числе после перезапуска приложения, регистр и пробелы не важны)
      final session = await enter(' GOODCODE ');
      expect(session.token, 'tok-GOODCODE');
      expect(session.groupId, 'ofo-1-bi-25');
      expect(prefs.getString('redeemNonce.editor'), isNull); // после успеха метка стирается
    });

    test('другой телефон с тем же кодом (другая метка) получает «уже использован»', () async {
      await enter('GOODCODE');
      await expectLater(
        api.redeem('GOODCODE', nonce: 'b' * 32),
        throwsA(isA<SharedApiException>().having((e) => e.code, 'code', 'code_used')),
      );
      // и без метки (старая версия приложения) повтор не проходит
      await expectLater(api.redeem('GOODCODE'), throwsA(isA<SharedApiException>().having((e) => e.code, 'code', 'code_used')));
    });

    test('метка относится к конкретному коду: для другого кода берётся новая', () async {
      backend.validCodes['OTHERCODE'] = 'ofo-2-bi-25';
      backend.loseNextRedeemResponse = true;
      await expectLater(enter('GOODCODE'), throwsA(isA<SharedApiException>()));
      final first = prefs.getString('redeemNonce.editor')!;
      final session = await enter('OTHERCODE');
      expect(session.groupId, 'ofo-2-bi-25');
      expect(first, startsWith('GOODCODE|'));
      expect(backend.codeNonces['OTHERCODE'], isNot(first.split('|').last));
    });

    test('неверный код стирает метку, сеть — оставляет', () async {
      await expectLater(enter('NOPE'), throwsA(isA<SharedApiException>().having((e) => e.code, 'code', 'bad_code')));
      expect(prefs.getString('redeemNonce.editor'), isNull);
    });

    test('подбор: после 20 неверных вводов даже верный код не принимается, но повтор с меткой проходит', () async {
      backend.loseNextRedeemResponse = true;
      await expectLater(enter('GOODCODE'), throwsA(isA<SharedApiException>().having((e) => e.code, 'code', 'network')));
      for (var i = 0; i < 20; i++) {
        await expectLater(api.redeem('GUESS$i'), throwsA(isA<SharedApiException>().having((e) => e.code, 'code', 'bad_code')));
      }
      backend.validCodes['NEWCODE'] = 'ofo-2-bi-25';
      await expectLater(api.redeem('NEWCODE'), throwsA(isA<SharedApiException>().having((e) => e.code, 'code', 'too_many_attempts')));
      // тот, у кого ответ потерялся, не заблокирован: у него есть метка
      expect((await enter('GOODCODE')).token, 'tok-GOODCODE');
    });

    test('преподаватель: повтор с той же меткой возвращает тот же токен', () async {
      const nonce = 'c0ffee00c0ffee00c0ffee00c0ffee00';
      final first = await api.redeemTeacher('teachcode', nonce: nonce);
      final again = await api.redeemTeacher('TEACHCODE', nonce: nonce);
      expect(again.token, first.token);
      await expectLater(api.redeemTeacher('TEACHCODE', nonce: 'd' * 32), throwsA(isA<SharedApiException>().having((e) => e.code, 'code', 'code_used')));
    });
  });
}
