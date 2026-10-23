// Вход на компьютере (разбор QR и кода, экран подтверждения) и файлы преподавателя в хранилище (до 15 МБ, скачивание по ссылке).

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unigraf/app_state.dart';
import 'package:unigraf/data/attachments/attachment_store.dart';
import 'package:unigraf/data/attachments/group_files.dart';
import 'package:unigraf/data/local/database.dart';
import 'package:unigraf/data/remote/shared_api.dart';
import 'package:unigraf/domain/attachment.dart';
import 'package:unigraf/domain/web_pair.dart';
import 'package:unigraf/features/teacher/teacher_homework_screen.dart';
import 'package:unigraf/features/teacher/web_login_screen.dart';

import 'support/fakes.dart';

/// Даёт ответам «сервера» дойти: ждём реальное время и обновляем экран.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _pairId = '11111111-1111-4111-8111-111111111111';

void main() {
  group('разбор QR и текстового кода', () {
    test('QR страницы и голый номер запроса распознаются, чужое нет', () {
      expect(parsePairQr('unigraf://pair/$_pairId'), _pairId);
      expect(parsePairQr('  UNIGRAF://PAIR/${_pairId.toUpperCase()} '), _pairId);
      expect(parsePairQr(_pairId), _pairId);
      expect(parsePairQr('https://example.com/?x=$_pairId'), isNull);
      expect(parsePairQr('unigraf://pair/not-a-uuid'), isNull);
      expect(parsePairQr(''), isNull);
    });

    test('текстовый код: регистр, дефис и пробелы не важны; неверная форма отклоняется', () {
      expect(parseTextCode('qag3-v3fy'), 'QAG3V3FY');
      expect(parseTextCode(' QAG3 V3FY '), 'QAG3V3FY');
      expect(parseTextCode('QAG3V3F'), isNull); // 7 знаков
      expect(parseTextCode('QAG3V3F0'), isNull); // ноль и буква O сервер не выдаёт
      expect(parseTextCode('QAG3V3FI'), isNull);
    });

    test('компьютер из списка читается из ответа сервера', () {
      final s = WebSessionInfo.fromJson({'id': 'a', 'created_at': '2026-10-23T14:30:30.218777+00:00', 'last_seen': '2026-10-23T14:31:00+00:00'});
      expect(s.id, 'a');
      expect(s.lastSeen.isAfter(s.createdAt), isTrue);
    });
  });

  group('файлы преподавателя в хранилище', () {
    late FakeBackend backend;
    late FakeAttachmentStore store;
    late GroupFiles service;

    setUp(() async {
      backend = FakeBackend();
      store = FakeAttachmentStore();
      SharedPreferences.setMockInitialValues({});
      service = GroupFiles(api: backend.api(), store: store, prefs: await SharedPreferences.getInstance());
    });
    tearDown(() => store.dir.deleteSync(recursive: true));

    Future<Attachment> local(String name, int size) =>
        store.save(PickedFileInfo(name: name, sizeBytes: size, readBytes: () async => Uint8List.fromList(List.generate(size, (i) => i % 251))));

    test('файл 14 МБ уходит в хранилище по билету и регистрируется; скачивание по ссылке даёт те же байты', () async {
      final a = await local('Лекция.pptx', 14 * 1024 * 1024);
      var n = 0;
      final up = await service.upload('tok-teacher-TEACHCODE', [a], () => 'id-${n++}', teacher: true);

      expect(backend.calls, ['teacher_upload_ticket', 'storage_post', 'register_teacher_file']);
      expect(up.refs.single.size, 14 * 1024 * 1024);
      expect(backend.storagePaths['id-0'], 'tk0/id-0');
      expect(backend.calls, isNot(contains('put_teacher_file')));

      final bytes = await backend.api().getFile('ofo-1-bi-25', 'id-0');
      expect(bytes.length, 14 * 1024 * 1024);
      expect(bytes[1000], 1000 % 251);
      expect(backend.calls.last, 'storage_get');
    });

    test('больше 15 МБ и программы отклоняются до отправки, ничего на сервер не уходит', () async {
      final big = await local('большой.bin', maxTeacherFileBytes + 1);
      await expectLater(service.upload('t', [big], () => 'x', teacher: true), throwsA(isA<SharedApiException>().having((e) => e.code, 'code', 'file_too_big')));
      final exe = await local('setup.EXE', 10);
      await expectLater(service.upload('t', [exe], () => 'x', teacher: true), throwsA(isA<SharedApiException>().having((e) => e.code, 'code', 'bad_file_type')));
      expect(backend.calls, isEmpty);
    });

    test('староста по-прежнему не больше 8 МБ и без хранилища', () async {
      final big = await local('9мб.bin', 9 * 1024 * 1024);
      await expectLater(service.upload('t', [big], () => 'x'), throwsA(isA<SharedApiException>().having((e) => e.code, 'code', 'file_too_big')));
      final ok = await local('a.bin', 100);
      await service.upload('t', [ok], () => 'g1');
      expect(backend.calls, ['put_group_file']);
    });

    test('сервер без хранилища (приложение вышло раньше сервера): файлы до 8 МБ уходят старым путём, крупнее — понятная ошибка', () async {
      backend.storageEnabled = false;
      final small = await local('a.pdf', 2 * 1024 * 1024);
      await service.upload('tok-teacher-TEACHCODE', [small], () => 'old-1', teacher: true);
      expect(backend.calls, ['teacher_upload_ticket', 'put_teacher_file']);
      expect(backend.files['old-1']!.bytes.length, 2 * 1024 * 1024);

      final big = await local('b.pdf', 10 * 1024 * 1024);
      await expectLater(service.upload('tok-teacher-TEACHCODE', [big], () => 'old-2', teacher: true), throwsA(isA<SharedApiException>().having((e) => e.code, 'code', 'server')));
    });

    test('ссылка не на наше хранилище не скачивается', () async {
      final api = SharedApi('https://fake.test', 'key', client: MockClient((request) async {
        if (request.url.pathSegments.last == 'get_group_file') return http.Response('{"name":"x","url":"https://evil.example/file"}', 200);
        return http.Response('boom', 500);
      }));
      await expectLater(api.getFile('ofo-1-bi-25', 'f'), throwsA(isA<SharedApiException>().having((e) => e.code, 'code', 'server')));
    });

    test('старые файлы из базы скачиваются как раньше', () async {
      backend.files['f1'] = (name: 'a.txt', bytes: [1, 2, 3]);
      expect(await backend.api().getFile('ofo-1-bi-25', 'f1'), [1, 2, 3]);
    });
  });

  group('экран «Отправить ДЗ с компьютера»', () {
    Future<void> open(WidgetTester tester, FakeBackend backend, {String? scanned}) async {
      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'teacherToken': 'tok-teacher-TEACHCODE', 'teacherCodeName': 'Халиев М.С-У.', 'teacherCodeGroups': ['ofo-1-bi-25'],
      });
      final sp = await SharedPreferences.getInstance();
      final db = AppDatabase(NativeDatabase.memory());
      await tester.runAsync(() => db.customSelect('select 1').get());
      addTearDown(() => tester.runAsync(db.close));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          databaseProvider.overrideWithValue(db),
          sharedApiProvider.overrideWithValue(backend.api()),
          qrScanProvider.overrideWithValue((_) async => scanned),
        ],
        child: const MaterialApp(home: WebLoginScreen()),
      ));
      await settle(tester);
    }

    testWidgets('вход по текстовому коду', (tester) async {
      final backend = FakeBackend();
      await open(tester, backend);
      await tester.enterText(find.byType(TextField), 'qag3-v3fy');
      await tester.tap(find.text('Войти по коду'));
      await settle(tester);
      expect(backend.approvedLogins, ['QAG3V3FY']);
      expect(find.textContaining('Готово'), findsOneWidget);
    });

    testWidgets('неверная форма кода и неизвестный код объясняются по-русски', (tester) async {
      final backend = FakeBackend();
      await open(tester, backend);
      await tester.enterText(find.byType(TextField), 'ABC');
      await tester.tap(find.text('Войти по коду'));
      await tester.pump();
      expect(find.textContaining('Код состоит из 8 знаков'), findsOneWidget);
      expect(backend.calls.where((c) => c == 'web_pair_approve'), isEmpty);

      await tester.enterText(find.byType(TextField), 'ZZZZ-ZZZZ');
      await tester.tap(find.text('Войти по коду'));
      await settle(tester);
      expect(find.textContaining('Такого входа не найдено'), findsOneWidget);
    });

    testWidgets('QR: нужно число с экрана; неверное число отклоняется, верное подтверждает вход', (tester) async {
      final backend = FakeBackend();
      await open(tester, backend, scanned: 'unigraf://pair/$_pairId');
      await tester.tap(find.text('Сканировать QR'));
      await settle(tester);
      expect(find.text('Введите число с экрана'), findsOneWidget);
      expect(find.textContaining('Это не код из 8 знаков'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Войти')).onPressed, isNull); // пока цифр меньше четырёх

      await tester.enterText(find.byType(TextField).last, '1111');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      await settle(tester);
      expect(find.textContaining('Число не подошло'), findsOneWidget);
      expect(backend.approvedLogins, isEmpty);

      await tester.tap(find.text('Сканировать QR'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, '4242');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
      await settle(tester);
      expect(backend.approvedLogins, [_pairId]);
    });

    testWidgets('в окне числа можно перейти к вводу кода из 8 знаков', (tester) async {
      final backend = FakeBackend();
      await open(tester, backend, scanned: 'unigraf://pair/$_pairId');
      await tester.tap(find.text('Сканировать QR'));
      await settle(tester);
      await tester.tap(find.text('Лучше ввести код из 8 знаков'));
      await settle(tester);
      expect(find.text('Введите число с экрана'), findsNothing);
      expect(backend.approvedLogins, isEmpty);
      expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus, isTrue);
    });

    testWidgets('оба способа входа названы на экране', (tester) async {
      final backend = FakeBackend();
      await open(tester, backend);
      expect(find.text('Войдите одним из двух способов'), findsOneWidget);
      expect(find.text('По QR-коду'), findsOneWidget);
      expect(find.text('По коду'), findsOneWidget);
      expect(find.textContaining('число с экрана не нужны'), findsOneWidget);
    });

    testWidgets('в разделе «ДЗ» режима преподавателя есть вход для отправки с компьютера', (tester) async {
      final backend = FakeBackend();
      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'teacherToken': 'tok-teacher-TEACHCODE', 'teacherCodeName': 'Халиев М.С-У.', 'teacherCodeGroups': ['ofo-1-bi-25'],
      });
      final sp = await SharedPreferences.getInstance();
      final db = AppDatabase(NativeDatabase.memory());
      await tester.runAsync(() => db.customSelect('select 1').get());
      addTearDown(() => tester.runAsync(db.close));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          databaseProvider.overrideWithValue(db),
          sharedApiProvider.overrideWithValue(backend.api()),
        ],
        child: const MaterialApp(home: Scaffold(body: TeacherHomeworkScreen())),
      ));
      await settle(tester);
      expect(find.text('Отправить ДЗ с компьютера'), findsOneWidget);
      await tester.tap(find.text('Отправить ДЗ с компьютера'));
      await settle(tester);
      expect(find.text('Войдите одним из двух способов'), findsOneWidget);
    });

    testWidgets('чужой QR отклоняется без обращения к серверу', (tester) async {
      final backend = FakeBackend();
      await open(tester, backend, scanned: 'https://example.com/');
      await tester.tap(find.text('Сканировать QR'));
      await settle(tester);
      expect(find.textContaining('Это не код входа UniGraf'), findsOneWidget);
      expect(backend.calls.where((c) => c == 'web_pair_approve'), isEmpty);
    });

    testWidgets('список компьютеров: видно вход, «Завершить» убирает его', (tester) async {
      final backend = FakeBackend()..webSessions.add({'id': 's1', 'created_at': '2026-10-23T14:30:00+00:00', 'last_seen': '2026-10-23T14:35:00+00:00'});
      await open(tester, backend);
      expect(find.textContaining('Последнее действие'), findsOneWidget);
      await tester.tap(find.text('Завершить'));
      await settle(tester);
      expect(backend.webSessions, isEmpty);
      expect(find.textContaining('Сейчас нигде'), findsOneWidget);
    });
  });
}
