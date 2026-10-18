// «Домашка студентам» у преподавателя: список отправленного не заставляет ждать долгий ответ сервера, если есть копия.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unigraf/app_state.dart';
import 'package:unigraf/data/remote/shared_api.dart';
import 'package:unigraf/domain/teacher_homework.dart';

TeacherHomeworkBatch _batch(String id, String subject) => TeacherHomeworkBatch(
      id: id,
      subject: subject,
      text: 'Номера 1-5',
      dueDate: DateTime.utc(2026, 10, 20),
      targets: const [TeacherSentTarget(groupId: 'ofo-1-bi-25')],
    );

Map<String, dynamic> _serverBatch(String id, String subject) => {
      'batch_id': id,
      'subject': subject,
      'body': 'Номера 1-5',
      'due_date': '2026-10-20',
      'kind': null,
      'files': [],
      'groups': [
        {'id': 'ofo-1-bi-25', 'subgroup': null},
      ],
    };

Future<ProviderContainer> _container(http.Client client, {bool withCache = true}) async {
  SharedPreferences.setMockInitialValues({
    'teacherToken': 'tok',
    'teacherCodeName': 'Иванов А.Б.',
    'teacherCodeGroups': ['ofo-1-bi-25'],
    if (withCache) 'teacherSentCache': jsonEncode([_batch('old', 'Старое').toJson()]),
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    sharedApiProvider.overrideWithValue(SharedApi('https://example.test', 'k', client: client)),
    teacherSentWaitProvider.overrideWithValue(const Duration(milliseconds: 50)),
  ]);
  addTearDown(container.dispose);
  return container;
}

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status);

void main() {
  test('сервер ответил: показываем свежий список и обновляем копию', () async {
    final container = await _container(MockClient((_) async => _json([_serverBatch('b1', 'Математика')])));
    final list = await container.read(teacherSentProvider.future);
    expect(list.single.subject, 'Математика');
    final saved = jsonDecode(container.read(sharedPreferencesProvider).getString('teacherSentCache')!) as List;
    expect((saved.single as Map)['subject'], 'Математика');
  });

  test('сервер долго молчит, а копия есть: список показывается сразу, поздний ответ обновляет копию', () async {
    final late = Completer<http.Response>();
    final container = await _container(MockClient((_) => late.future));
    final stopwatch = Stopwatch()..start();
    final list = await container.read(teacherSentProvider.future);
    expect(list.single.subject, 'Старое');
    expect(stopwatch.elapsedMilliseconds, lessThan(2000));

    late.complete(_json([_serverBatch('b1', 'Математика')]));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final saved = jsonDecode(container.read(sharedPreferencesProvider).getString('teacherSentCache')!) as List;
    expect((saved.single as Map)['subject'], 'Математика');
  });

  test('поздняя ошибка сервера после показа копии ничего не ломает', () async {
    final late = Completer<http.Response>();
    final container = await _container(MockClient((_) => late.future));
    final list = await container.read(teacherSentProvider.future);
    expect(list.single.subject, 'Старое');
    late.complete(_json({'message': 'boom'}, 500));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // копия осталась прежней
    final saved = jsonDecode(container.read(sharedPreferencesProvider).getString('teacherSentCache')!) as List;
    expect((saved.single as Map)['subject'], 'Старое');
  });

  test('сбой сервера при наличии копии: показываем копию', () async {
    final container = await _container(MockClient((_) async => _json({'message': 'boom'}, 500)));
    final list = await container.read(teacherSentProvider.future);
    expect(list.single.subject, 'Старое');
  });

  test('«Доступ отозван»: копию не показываем', () async {
    final container = await _container(MockClient((_) async => _json({'message': 'bad_token'}, 400)));
    await expectLater(
      container.read(teacherSentProvider.future),
      throwsA(isA<SharedApiException>().having((e) => e.code, 'code', 'bad_token')),
    );
  });

  test('копии нет и сервер недоступен: ошибка (как раньше)', () async {
    final container = await _container(MockClient((_) async => _json({'message': 'boom'}, 500)), withCache: false);
    await expectLater(container.read(teacherSentProvider.future), throwsA(isA<SharedApiException>()));
  });
}
