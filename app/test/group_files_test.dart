// Файлы и фото в ДЗ старосты: описание в ДЗ, загрузка на сервер, скачивание студентом и кэш в телефоне.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:unigraf/data/attachments/attachment_store.dart';
import 'package:unigraf/data/attachments/group_files.dart';
import 'package:unigraf/data/remote/shared_api.dart';
import 'package:unigraf/domain/attachment.dart';
import 'package:unigraf/domain/group_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  group('GroupHomeworkRow с подгруппой', () {
    test('ДЗ для подгруппы: читается, записывается, видно только своей подгруппе', () {
      final row = GroupHomeworkRow.fromJson({...FakeBackend().hw(), 'subgroup': 2});
      expect(row.subgroup, 2);
      expect(GroupHomeworkRow.fromJson(row.toJson()).subgroup, 2);
      expect(row.visibleTo(2), isTrue);
      expect(row.visibleTo(1), isFalse);
    });

    test('ДЗ без подгруппы (в том числе старое) видно всем', () {
      final row = GroupHomeworkRow.fromJson(FakeBackend().hw());
      expect(row.subgroup, isNull);
      expect(row.visibleTo(1) && row.visibleTo(2), isTrue);
    });
  });

  group('GroupHomeworkRow с файлами', () {
    test('список файлов читается и записывается без потерь', () {
      final row = GroupHomeworkRow.fromJson(FakeBackend().hw(files: [
        {'id': 'f1', 'name': 'Задачи.pdf', 'size': 2048},
        {'id': 'f2', 'name': 'Доска.jpg', 'size': 100},
      ]));
      expect(row.files.map((f) => f.name), ['Задачи.pdf', 'Доска.jpg']);
      expect(row.files.first.asAttachment.sizeText, '2 КБ');
      expect(row.files.last.asAttachment.isImage, isTrue);
      expect(GroupHomeworkRow.fromJson(row.toJson()).files.length, 2);
    });

    test('ДЗ без поля files (старый кэш или старый сервер) читается как «без файлов»', () {
      final json = FakeBackend().hw()..remove('files');
      expect(GroupHomeworkRow.fromJson(json).files, isEmpty);
    });

    test('номера всех файлов ДЗ группы: и старосты, и преподавателей', () {
      final state = GroupSharedState.empty.replaceWith({
        'server_time': 't',
        'overrides': [],
        'homework': [FakeBackend().hw(files: [{'id': 'f1', 'name': 'a.pdf', 'size': 5}])],
        'teacher_homework': [
          {...FakeBackend().hw(files: [{'id': 'f2', 'name': 'b.pdf', 'size': 6}]), 'id': 't1', 'author': 'Иванов А.Б.'},
        ],
      });
      expect(state.fileIds, {'f1', 'f2'});
      expect(GroupSharedState.empty.fileIds, isEmpty);
    });

    test('файлы переживают кэш телефона', () {
      final state = GroupSharedState.empty.replaceWith({
        'server_time': 't',
        'overrides': [],
        'homework': [FakeBackend().hw(files: [{'id': 'f1', 'name': 'a.pdf', 'size': 5}])],
      });
      expect(GroupSharedState.decode(state.encode()).homework['h1']!.files.single.id, 'f1');
    });
  });

  group('GroupFiles (загрузка и скачивание)', () {
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

    Future<Attachment> local(String name, List<int> bytes) =>
        store.save(PickedFileInfo(name: name, sizeBytes: bytes.length, readBytes: () async => Uint8List.fromList(bytes)));

    test('загрузка отправляет содержимое и возвращает описания для ДЗ', () async {
      final a = await local('Задачи.pdf', [1, 2, 3, 4]);
      var n = 0;
      final up = await service.upload('tok', [a], () => 'id-${n++}');

      expect(up.refs.single.id, 'id-0');
      expect(up.refs.single.name, 'Задачи.pdf');
      expect(up.refs.single.size, 4);
      expect(backend.files['id-0']!.bytes, [1, 2, 3, 4]);
      expect(up.local['id-0'], a);
    });

    test('слишком большой файл и слишком много файлов отклоняются до отправки', () async {
      final big = await local('большой.bin', List.filled(maxGroupFileBytes + 1, 7));
      await expectLater(service.upload('tok', [big], () => 'x'), throwsA(isA<SharedApiException>().having((e) => e.code, 'code', 'file_too_big')));

      final small = await local('a.txt', [1]);
      await expectLater(
        service.upload('tok', List.filled(maxGroupFilesPerHomework + 1, small), () => 'x'),
        throwsA(isA<SharedApiException>().having((e) => e.code, 'code', 'too_many_files')),
      );
      expect(backend.files, isEmpty); // ничего лишнего на сервер не ушло
    });

    test('скачивание: первый раз с сервера, второй раз из телефона', () async {
      backend.files['f1'] = (name: 'Лекция.pdf', bytes: [9, 8, 7]);
      const ref = GroupFileRef(id: 'f1', name: 'Лекция.pdf', size: 3);
      expect(service.cached('f1'), isNull);

      final first = await service.download('ofo-1-bi-25', ref);
      expect(File(first.path).readAsBytesSync(), [9, 8, 7]);
      final second = await service.download('ofo-1-bi-25', ref);
      expect(second.path, first.path);
      expect(backend.calls.where((c) => c == 'get_group_file'), hasLength(1));
    });

    test('большой файл скачивается целиком, хотя сервер ставит переносы строк в base64 (раньше такие файлы не скачивались)', () async {
      final big = List<int>.generate(300000, (i) => i % 251);
      backend.files['big'] = (name: 'Фото.jpg', bytes: big);
      final saved = await service.download('ofo-1-bi-25', const GroupFileRef(id: 'big', name: 'Фото.jpg', size: 300000));
      expect(File(saved.path).readAsBytesSync(), big);
    });

    test('закодированное имя файла показывается читаемо: %D0%A1… → Создание', () {
      expect(cleanFileName('%D0%A1%D0%BE%D0%B7%D0%B4%D0%B0%D0%BD%D0%B8%D0%B5_Telegram.pptx'), 'Создание_Telegram.pptx');
      expect(cleanFileName('Задачи 100%.pdf'), 'Задачи 100%.pdf'); // обычный знак процента не трогаем
      expect(cleanFileName('plain.pdf'), 'plain.pdf');
      expect(cleanFileName('%ZZ%D0'), '%ZZ%D0'); // нечитаемое оставляем как есть
      final row = GroupFileRef.fromJson({'id': 'x', 'name': '%D0%94%D0%97.docx', 'size': 5});
      expect(row.name, 'ДЗ.docx');
    });

    test('если скачанную копию удалили из памяти телефона — файл скачивается заново', () async {
      backend.files['f1'] = (name: 'a.txt', bytes: [1]);
      const ref = GroupFileRef(id: 'f1', name: 'a.txt', size: 1);
      final first = await service.download('ofo-1-bi-25', ref);
      File(first.path).deleteSync();

      expect(service.cached('f1'), isNull);
      await service.download('ofo-1-bi-25', ref);
      expect(backend.calls.where((c) => c == 'get_group_file'), hasLength(2));
    });

    test('ДЗ исчезло с сервера: его скачанные файлы стираются из телефона, нужные остаются', () async {
      backend.files['keep'] = (name: 'нужный.pdf', bytes: [1]);
      backend.files['gone'] = (name: 'старый.pdf', bytes: [2]);
      backend.files['gone2'] = (name: 'старый2.pdf', bytes: [3]);
      final keep = await service.download('ofo-1-bi-25', const GroupFileRef(id: 'keep', name: 'нужный.pdf', size: 1));
      final gone = await service.download('ofo-1-bi-25', const GroupFileRef(id: 'gone', name: 'старый.pdf', size: 1));
      final gone2 = await service.download('ofo-1-bi-25', const GroupFileRef(id: 'gone2', name: 'старый2.pdf', size: 1));

      final erased = await service.forgetExcept({'keep'});

      expect(erased, 2);
      expect(File(gone.path).existsSync(), isFalse);
      expect(File(gone2.path).existsSync(), isFalse);
      expect(File(keep.path).existsSync(), isTrue);
      expect(service.cached('gone'), isNull);
      expect(service.cached('keep'), isNotNull);
      // второй проход ничего не находит
      expect(await service.forgetExcept({'keep'}), 0);
    });

    test('чистка не падает, если файл уже стёрт вручную, и пустой кэш не трогает', () async {
      expect(await service.forgetExcept({}), 0);
      backend.files['f1'] = (name: 'a.txt', bytes: [1]);
      final a = await service.download('ofo-1-bi-25', const GroupFileRef(id: 'f1', name: 'a.txt', size: 1));
      File(a.path).deleteSync();
      expect(await service.forgetExcept({}), 1);
    });

    test('файл, которого нет на сервере, даёт понятную ошибку', () async {
      await expectLater(
        service.download('ofo-1-bi-25', const GroupFileRef(id: 'нет', name: 'x', size: 1)),
        throwsA(isA<SharedApiException>().having((e) => e.message, 'message', contains('не найден'))),
      );
    });
  });
}
