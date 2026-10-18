// Проверка приложения целиком (без телефона): первый запуск, экран «Сегодня», «Неделя».
// Расписание берётся из встроенной копии assets/schedule, база — в памяти.


import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:unigraf/data/remote/shared_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unigraf/domain/notification_plan.dart';
import 'package:unigraf/app_state.dart';
import 'package:unigraf/core/clock.dart';
import 'package:unigraf/data/attachments/attachment_store.dart';
import 'package:unigraf/data/local/database.dart';
import 'package:unigraf/data/repositories/schedule_repository.dart';
import 'package:unigraf/main.dart';
import 'package:unigraf/theme/brand_colors.dart';
import 'package:unigraf/theme/next_design.dart';
import 'package:unigraf/update_check.dart';
import 'package:unigraf/features/week/week_screen.dart' show weekRangeText;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Future<void> _start(WidgetTester tester, {Map<String, Object> prefs = const {}, DateTime? now, FakeGateway? gateway, List extraOverrides = const [], SharedApi? sharedApi}) async {
  // Высокий «экран», чтобы весь список строился сразу (ListView строит только видимое)
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final db = AppDatabase(NativeDatabase.memory());
  // Базу открываем заранее и в реальном времени: внутри «поддельных» часов теста drift зависает
  await tester.runAsync(() => db.customSelect('select 1').get());
  addTearDown(() => tester.runAsync(db.close));

  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      databaseProvider.overrideWithValue(db),
      repositoryProvider.overrideWithValue(ScheduleRepository(db: db, assets: DiskAssets())),
      notificationGatewayProvider.overrideWithValue(gateway ?? FakeGateway()),
      clockProvider.overrideWithValue(FixedClock(now ?? DateTime.utc(2026, 10, 7, 10, 30))), // 13:30 по Москве
      sharedApiProvider.overrideWithValue(sharedApi), // по умолчанию общий сервер выключен; тесты старосты подставляют свой
      ...extraOverrides,
    ],
    child: const UniGrafApp(),
  ));
  await _settle(tester);
}

/// Даёт загрузкам (ассеты, база) завершиться: несколько раз ждём реальное время и обновляем экран.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  const profile = {'form': 'ofo', 'groupId': 'ofo-1-bi-25', 'subgroup': 1, 'pe': 'male'};

  testWidgets('Первый запуск: выбор группы 1 БИ-25 → подгруппа → физ-ра → экран «Сегодня»', (tester) async {
    await _start(tester);
    expect(find.text('ФОРМА ОБУЧЕНИЯ'), findsOneWidget);

    await tester.tap(find.text('Очная'));
    await tester.pump();
    await tester.tap(find.text('2 курс'));
    await tester.pump();
    await tester.tap(find.text('1 БИ-25'));
    await tester.pump();
    expect(find.text('ПОДГРУППА'), findsOneWidget);

    await tester.tap(find.text('БИ-25-1'));
    await tester.pump();
    expect(find.text('ФИЗКУЛЬТУРА'), findsOneWidget);

    await tester.tap(find.text('Юноши'));
    await _settle(tester);
    expect(find.text('Сегодня'), findsWidgets); // нижняя панель
    expect(find.text('ФОРМА ОБУЧЕНИЯ'), findsNothing);
  });

  testWidgets('«Сегодня» 07.10.2026 13:30: идёт ТП в 2-05, дальше ЧТК практика 2-15', (tester) async {
    await _start(tester, prefs: profile);
    expect(find.text('2 неделя'), findsOneWidget);
    expect(find.text(kNextDesign ? 'Идёт сейчас' : 'СЕЙЧАС'), findsOneWidget);
    expect(find.text('Технологическое предпринимательство'), findsWidgets);
    expect(find.text('2-05'), findsWidgets);
    expect(find.text('ЧТК и этика'), findsOneWidget);
    expect(find.text('2-15'), findsOneWidget);
    expect(find.text('Кураторский час'), findsNothing); // он только на 1 неделе
  });

  // Только для тестовой сборки (flutter test --dart-define=NEXT_DESIGN=true): новые подсказки и заполнение линии времени
  testWidgets('Новый вид: в карточке «Сейчас» есть подсказка, что дальше', (tester) async {
    await _start(tester, prefs: profile);
    expect(find.textContaining('Дальше в '), findsOneWidget);
    expect(find.textContaining('ЧТК и этика'), findsWidgets);
  }, skip: !kNextDesign);

  testWidgets('«Неделя»: 1 неделя содержит кураторский час, 2 неделя — нет', (tester) async {
    await _start(tester, prefs: profile);
    await tester.tap(find.text('Неделя').last);
    await _settle(tester);
    expect(find.text('Кураторский час'), findsNothing); // сейчас 2 неделя

    await tester.tap(find.textContaining('1 неделя'));
    await _settle(tester);
    expect(find.text('Кураторский час'), findsOneWidget);
  });

  testWidgets('После последней пары открывается следующий учебный день', (tester) async {
    // 07.10.2026 18:30 по Москве — пары кончились → показывается четверг 08.10
    await _start(tester, prefs: profile, now: DateTime.utc(2026, 10, 7, 15, 30));
    expect(find.textContaining('четверг, 8 октября'), findsOneWidget);
  });

  testWidgets('Воскресенье → открывается понедельник', (tester) async {
    await _start(tester, prefs: profile, now: DateTime.utc(2026, 10, 11, 9, 0));
    expect(find.textContaining('понедельник, 12 октября'), findsOneWidget);
  });

  testWidgets('ДЗ: долгое нажатие на пару → срок сам = следующее занятие → появляется в списке ДЗ', (tester) async {
    await _start(tester, prefs: profile);

    await tester.longPress(find.text('ЧТК и этика').last);
    await _settle(tester);
    await tester.tap(find.text('Добавить ДЗ'));
    await _settle(tester);
    expect(find.text('Новое ДЗ'), findsOneWidget);
    // ЧТК в среду есть каждую неделю (1 нед — лекция, 2 нед — практика) → следующее занятие 14 октября
    expect(find.textContaining('Срок: среда, 14 октября'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Прочитать главу 3');
    await tester.pump();
    await tester.tap(find.text('Добавить'));
    await _settle(tester);
    expect(find.text('Новое ДЗ'), findsNothing);

    await tester.tap(find.text('ДЗ').last);
    await _settle(tester);
    expect(find.text('Прочитать главу 3'), findsOneWidget);
    expect(find.text('Позже'), findsOneWidget); // 14 октября — уже следующая неделя
  });

  testWidgets('ДЗ: прикрепить файл → он виден на карточке задания и открывается', (tester) async {
    final dir = Directory.systemTemp.createTempSync('hw_files');
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = File('${dir.path}/Задачи.pdf')..writeAsBytesSync(List.filled(2048, 1));
    final store = FakeAttachmentStore();
    addTearDown(() => store.dir.deleteSync(recursive: true));

    await _start(tester, prefs: profile, extraOverrides: [
      attachmentStoreProvider.overrideWithValue(store),
      attachmentPickerProvider.overrideWithValue(FakeAttachmentPicker([PickedFileInfo(name: 'Задачи.pdf', path: source.path, sizeBytes: 2048)])),
    ]);

    await tester.longPress(find.text('ЧТК и этика').last);
    await _settle(tester);
    await tester.tap(find.text('Добавить ДЗ'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Решить задачи');
    await tester.pump();

    await tester.tap(find.text('Прикрепить'));
    await _settle(tester);
    await tester.tap(find.text('Файл'));
    await _settle(tester);
    expect(find.text('Задачи.pdf'), findsOneWidget); // плитка в окне добавления
    expect(find.text('2 КБ'), findsOneWidget);

    await tester.tap(find.text('Добавить'));
    await _settle(tester);

    await tester.tap(find.text('ДЗ').last);
    await _settle(tester);
    expect(find.text('Решить задачи'), findsOneWidget);
    await tester.tap(find.text('Задачи.pdf'));
    await _settle(tester);
    expect(store.opened, ['Задачи.pdf']);
  });

  testWidgets('ДЗ: закрыли окно без сохранения — скопированные файлы удаляются', (tester) async {
    final dir = Directory.systemTemp.createTempSync('hw_files');
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = File('${dir.path}/Фото.jpg')..writeAsBytesSync([1, 2, 3]);
    final store = FakeAttachmentStore();
    addTearDown(() => store.dir.deleteSync(recursive: true));

    await _start(tester, prefs: profile, extraOverrides: [
      attachmentStoreProvider.overrideWithValue(store),
      attachmentPickerProvider.overrideWithValue(FakeAttachmentPicker([PickedFileInfo(name: 'Фото.jpg', path: source.path, sizeBytes: 3)])),
    ]);
    await tester.longPress(find.text('ЧТК и этика').last);
    await _settle(tester);
    await tester.tap(find.text('Добавить ДЗ'));
    await _settle(tester);
    await tester.tap(find.text('Прикрепить'));
    await _settle(tester);
    await tester.tap(find.text('Файл'));
    await _settle(tester);
    expect(find.text('Фото.jpg'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10)); // закрыть окно
    await _settle(tester);
    expect(store.deleted, ['Фото.jpg']);
  });

  testWidgets('Настройки: выбор цветовой темы меняет цвета и запоминается; «Чёрный фон» работает в тёмной теме', (tester) async {
    await _start(tester, prefs: {...profile, 'theme': 'light'});
    await tester.tap(find.text('Настройки').last);
    await _settle(tester);

    Color primary() => Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.primary;
    // по умолчанию — «Океан» (цвета логотипа)
    expect(primary(), BrandColors.scheme(AppPalette.ocean, Brightness.light).primary);

    await tester.tap(find.text('Петроль'));
    await _settle(tester);
    expect(primary(), BrandColors.scheme(AppPalette.petrol, Brightness.light).primary);
    expect((await SharedPreferences.getInstance()).getString('palette'), 'petrol');

    // Тёмная тема + чёрный фон
    await tester.tap(find.text('Тема').first);
    await _settle(tester);
    await tester.tap(find.text('Тёмная'));
    await _settle(tester);
    await tester.tap(find.text('Чёрный фон'));
    await _settle(tester);
    final surface = Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.surface;
    expect(surface, Colors.black);
  });

  testWidgets('Предметы: своё название и цвет через меню пары; выключатель в настройках возвращает названия из расписания', (tester) async {
    final gateway = FakeGateway();
    await _start(tester, prefs: profile, gateway: gateway);
    expect(find.text('ЧТК и этика'), findsWidgets);

    await tester.longPress(find.text('ЧТК и этика').last);
    await _settle(tester);
    await tester.tap(find.text('Название и цвет'));
    await _settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Своё короткое название'), 'Этика');
    await tester.tap(find.byTooltip('Коралловый'));
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await _settle(tester);

    // На экране — своё название; настоящее исчезло; в уведомлениях тоже своё
    expect(find.text('Этика'), findsWidgets);
    expect(find.text('ЧТК и этика'), findsNothing);
    expect(gateway.lastPlan.map((n) => n.title), contains('Этика → 2-15'));

    // Выключаем в настройках — возвращается название из расписания
    await tester.tap(find.text('Настройки').last);
    await _settle(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await _settle(tester);
    await tester.tap(find.text('Свои названия и цвета'));
    await _settle(tester);
    await tester.tap(find.text('Сегодня').last);
    await _settle(tester);
    expect(find.text('ЧТК и этика'), findsWidgets);
    expect(find.text('Этика'), findsNothing);
    expect(gateway.lastPlan.map((n) => n.title), contains('ЧТК и этика → 2-15'));
  });

  testWidgets('Быстрые действия на значке: ссылки открывают «Завтра», «Неделю» и «Поиск»', (tester) async {
    final links = FakeLinks();
    await _start(tester, prefs: profile, extraOverrides: [linkChannelProvider.overrideWithValue(links)]); // среда 7 октября
    expect(find.textContaining('среда, 7 октября'), findsWidgets);

    links.send('unigraf://day/tomorrow');
    await _settle(tester);
    expect(find.textContaining('четверг, 8 октября'), findsWidgets);

    links.send('unigraf://week');
    await _settle(tester);
    expect(find.text('1 неделя'), findsWidgets); // вкладка «Неделя»

    links.send('unigraf://search');
    await _settle(tester);
    expect(find.text('Свободные'), findsOneWidget); // вкладка «Поиск»
  });

  testWidgets('Общая лекция: на карточке значок «+1», в меню пары — с какими группами она объединена', (tester) async {
    await _start(tester, prefs: profile);

    // «Технологическое предпринимательство» — лекция вместе с 2 БИ-25; практика (ЧТК и этика) ни с кем не объединена
    expect(find.text('+1'), findsOneWidget);
    await tester.tap(find.text('Технологическое предпринимательство').last);
    await _settle(tester);
    expect(find.text('Лекция вместе с группами'), findsOneWidget);
    expect(find.text('2 БИ-25'), findsOneWidget);
  });

  testWidgets('Подпись внизу: без обновлений с сайта пишет дату расписания, а не «встроенная копия»', (tester) async {
    await _start(tester, prefs: profile);
    expect(find.textContaining('встроенная копия'), findsNothing);
    expect(find.textContaining('расписание от '), findsOneWidget);
  });

  testWidgets('Меню пары: полное ФИО преподавателя из справочника института', (tester) async {
    await _start(tester, prefs: profile);
    await tester.tap(find.text('Технологическое предпринимательство').last);
    await _settle(tester);
    expect(find.text('Халиев Магомед Сайд-Усманович'), findsOneWidget); // в расписании только «Халиев М.С-У.»
    expect(find.text('Преподаватель'), findsOneWidget);
  });

  group('Виджеты: добавление одним нажатием', () {
    testWidgets('подсказка на «Сегодня» → выбрать вид → система просит добавить; подсказка пропадает', (tester) async {
      final pinner = FakeWidgetPinner(supported: true);
      await _start(tester, prefs: profile, extraOverrides: [widgetPinnerProvider.overrideWithValue(pinner)]);

      expect(find.text('Виджет на главный экран'), findsOneWidget);
      await tester.tap(find.text('Добавить'));
      await _settle(tester);
      expect(find.text('Какой виджет добавить?'), findsOneWidget);
      await tester.tap(find.text('Ближайшая пара (строка)'));
      await _settle(tester);

      expect(pinner.pinned, ['StripWidget']);
      expect(find.text('Виджет на главный экран'), findsNothing);
    });

    testWidgets('«Скрыть подсказку» убирает её насовсем', (tester) async {
      await _start(tester, prefs: profile, extraOverrides: [widgetPinnerProvider.overrideWithValue(FakeWidgetPinner(supported: true))]);
      await tester.tap(find.byTooltip('Скрыть подсказку'));
      await _settle(tester);
      expect(find.text('Виджет на главный экран'), findsNothing);
    });

    testWidgets('на телефоне без поддержки подсказки нет, а в настройках — ручная инструкция', (tester) async {
      final pinner = FakeWidgetPinner(supported: false);
      await _start(tester, prefs: profile, extraOverrides: [widgetPinnerProvider.overrideWithValue(pinner)]);
      expect(find.text('Виджет на главный экран'), findsNothing);

      await tester.tap(find.text('Настройки').last);
      await _settle(tester);
      await tester.dragUntilVisible(find.text('Добавить виджет'), find.byType(Scrollable).first, const Offset(0, -300));
      await tester.tap(find.text('Добавить виджет'));
      await _settle(tester);
      await tester.tap(find.text('Сегодня').last);
      await _settle(tester);

      expect(pinner.pinned, isEmpty);
      expect(find.textContaining('Нажмите и удерживайте пустое место'), findsOneWidget);
    });
  });

  group('Староста и группа', () {
    // Хеш расписания 1 БИ-25 в встроенной копии: правки старосты привязаны к нему
    String groupHash() {
      final index = jsonDecode(File('assets/schedule/index.json').readAsStringSync()) as Map<String, dynamic>;
      for (final form in index['forms'] as List) {
        for (final g in (form as Map)['groups'] as List) {
          if ((g as Map)['id'] == 'ofo-1-bi-25') return g['hash'] as String;
        }
      }
      throw StateError('нет группы');
    }

    Future<void> openSettingsAndScrollTo(WidgetTester tester, String text) async {
      await tester.tap(find.text('Настройки').last);
      await _settle(tester);
      await tester.dragUntilVisible(find.text(text), find.byType(Scrollable).first, const Offset(0, -300));
      await _settle(tester);
    }

    testWidgets('студент видит правку старосты (аудитория 3-33, пометка), а правки к старому расписанию — нет', (tester) async {
      final backend = FakeBackend(hash: groupHash());
      backend.overrides['o1'] = backend.override(); // 7 октября, 4 пара: аудитория 3-33
      backend.overrides['old'] = backend.override(id: 'old', pair: 3, room: '9-99', hash: 'старый-хеш'); // к прошлому расписанию
      await _start(tester, prefs: profile, sharedApi: backend.api());
      await _settle(tester);

      expect(find.text('3-33'), findsWidgets);
      expect(find.text('2-15'), findsNothing); // прежняя аудитория заменена
      // сервер сохранил правку 9 октября в 12:00 UTC, то есть в 15:00 по Москве; сегодня в тесте 7 октября — с датой
      expect(find.text('изменено старостой 9 октября в 15:00'), findsOneWidget);
      expect(find.text('9-99'), findsNothing); // устаревшая правка не действует
    });

    testWidgets('выключатель «Правки и ДЗ старосты» возвращает расписание как есть', (tester) async {
      final backend = FakeBackend(hash: groupHash());
      backend.overrides['o1'] = backend.override();
      await _start(tester, prefs: profile, sharedApi: backend.api());
      await _settle(tester);
      expect(find.text('3-33'), findsWidgets);

      await openSettingsAndScrollTo(tester, 'Правки и ДЗ старосты');
      await tester.tap(find.text('Правки и ДЗ старосты'));
      await _settle(tester);
      await tester.tap(find.text('Сегодня').last);
      await _settle(tester);
      expect(find.text('3-33'), findsNothing);
      expect(find.text('2-15'), findsWidgets);
    });

    testWidgets('вкладка «Староста» в ДЗ: задание видно, отметить «сделано» можно у себя', (tester) async {
      final backend = FakeBackend(hash: groupHash());
      backend.homework['h1'] = backend.hw();
      await _start(tester, prefs: profile, sharedApi: backend.api());
      await _settle(tester);

      await tester.tap(find.text('ДЗ').last);
      await _settle(tester);
      expect(find.textContaining('Староста (1)'), findsOneWidget);
      await tester.tap(find.textContaining('Староста'));
      await _settle(tester);
      expect(find.text('Читать главу 3'), findsOneWidget);
      expect(find.text('от старосты'), findsOneWidget);
      expect(find.byTooltip('Удалить для всей группы'), findsNothing); // студент удалить не может

      await tester.tap(find.byType(Checkbox));
      await _settle(tester);
      expect(find.textContaining('Староста (0)'), findsOneWidget); // отметил выполненным
    });

    testWidgets('староста: неверный код — ошибка; верный код (регистр не важен) — режим старосты', (tester) async {
      final backend = FakeBackend(hash: groupHash());
      await _start(tester, prefs: profile, sharedApi: backend.api());
      await openSettingsAndScrollTo(tester, 'Я староста');

      await tester.tap(find.text('Я староста'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).last, 'WRONG');
      await tester.tap(find.text('Подтвердить'));
      await _settle(tester);
      expect(find.textContaining('Код не подошёл'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'goodcode'); // регистр не важен
      await tester.tap(find.text('Подтвердить'));
      await _settle(tester);
      expect(find.textContaining('Вы староста:'), findsOneWidget);
      expect(find.text('Изменения для группы'), findsOneWidget);
    });

    testWidgets('староста отменяет пару для всей группы: пара исчезает, на сервер уходит правка с хешем расписания', (tester) async {
      final backend = FakeBackend(hash: groupHash());
      await _start(tester, prefs: {...profile, 'editorToken': 'tok-GOODCODE', 'editorGroup': 'ofo-1-bi-25'}, sharedApi: backend.api());
      await _settle(tester);
      expect(find.text('ЧТК и этика'), findsWidgets);

      await tester.longPress(find.text('ЧТК и этика').last);
      await _settle(tester);
      await tester.dragUntilVisible(find.text('Отменить пару для группы'), find.byType(Scrollable).last, const Offset(0, -200));
      await tester.tap(find.text('Отменить пару для группы'));
      await _settle(tester);

      expect(backend.calls, contains('put_group_override'));
      final saved = backend.overrides.values.single;
      expect(saved['type'], 'cancel');
      expect(saved['pair'], 4);
      expect(saved['date'], '2026-10-07');
      expect(saved['base_hash'], groupHash());
      expect(find.text('ЧТК и этика'), findsNothing); // у всех (и у самого старосты) пары нет
    });

    testWidgets('староста задаёт ДЗ для всей группы: уходит на сервер и появляется во вкладке «Староста»', (tester) async {
      final backend = FakeBackend(hash: groupHash());
      await _start(tester, prefs: {...profile, 'editorToken': 'tok-GOODCODE', 'editorGroup': 'ofo-1-bi-25'}, sharedApi: backend.api());
      await _settle(tester);

      await tester.longPress(find.text('ЧТК и этика').last);
      await _settle(tester);
      await tester.tap(find.text('Добавить ДЗ'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).last, 'Подготовить доклад');
      await tester.tap(find.text('Для всей группы'));
      await _settle(tester);
      await tester.tap(find.text('Добавить'));
      await _settle(tester);

      expect(backend.homework.values.single['body'], 'Подготовить доклад');
      expect(backend.homework.values.single['subject'], 'ЧТК и этика');

      await tester.tap(find.text('ДЗ').last);
      await _settle(tester);
      await tester.tap(find.textContaining('Староста'));
      await _settle(tester);
      expect(find.text('Подготовить доклад'), findsOneWidget);
      expect(find.byTooltip('Удалить для всей группы'), findsOneWidget); // староста может удалить

      await tester.tap(find.byTooltip('Удалить для всей группы'));
      await _settle(tester);
      expect(backend.homework.values.single['deleted'], isTrue);
      expect(find.text('Подготовить доклад'), findsNothing);
    });

    testWidgets('староста прикрепляет файл к ДЗ группы: файл уходит на сервер, у старосты открывается без скачивания', (tester) async {
      final dir = Directory.systemTemp.createTempSync('hw_files');
      addTearDown(() => dir.deleteSync(recursive: true));
      final source = File('${dir.path}/Задачи.pdf')..writeAsBytesSync([5, 6, 7, 8]);
      final store = FakeAttachmentStore();
      addTearDown(() => store.dir.deleteSync(recursive: true));
      final backend = FakeBackend(hash: groupHash());
      await _start(tester, prefs: {...profile, 'editorToken': 'tok-GOODCODE', 'editorGroup': 'ofo-1-bi-25'}, sharedApi: backend.api(), extraOverrides: [
        attachmentStoreProvider.overrideWithValue(store),
        attachmentPickerProvider.overrideWithValue(FakeAttachmentPicker([PickedFileInfo(name: 'Задачи.pdf', path: source.path, sizeBytes: 4)])),
      ]);

      await tester.longPress(find.text('ЧТК и этика').last);
      await _settle(tester);
      await tester.tap(find.text('Добавить ДЗ'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).last, 'Решить задачи');
      await tester.tap(find.text('Для всей группы'));
      await _settle(tester);
      await tester.tap(find.text('Прикрепить'));
      await _settle(tester);
      await tester.tap(find.text('Файл'));
      await _settle(tester);
      await tester.tap(find.text('Добавить'));
      await _settle(tester);

      expect(backend.files.values.single.name, 'Задачи.pdf');
      expect(backend.files.values.single.bytes, [5, 6, 7, 8]);
      final saved = backend.homework.values.single;
      expect((saved['files'] as List).single['name'], 'Задачи.pdf');
      expect((saved['files'] as List).single['id'], backend.files.keys.single);

      await tester.tap(find.text('ДЗ').last);
      await _settle(tester);
      await tester.tap(find.textContaining('Староста'));
      await _settle(tester);
      await tester.tap(find.text('Задачи.pdf'));
      await _settle(tester);
      expect(store.opened, ['Задачи.pdf']);
      expect(backend.calls, isNot(contains('get_group_file'))); // свой файл не скачивается заново
    });

    testWidgets('студент видит файл от старосты, нажатие скачивает его и открывает; повторно — без скачивания', (tester) async {
      final store = FakeAttachmentStore();
      addTearDown(() => store.dir.deleteSync(recursive: true));
      final backend = FakeBackend(hash: groupHash());
      backend.files['f1'] = (name: 'Лекция.pdf', bytes: [1, 2, 3]);
      backend.homework['h1'] = backend.hw(files: [
        {'id': 'f1', 'name': 'Лекция.pdf', 'size': 3},
      ]);
      await _start(tester, prefs: profile, sharedApi: backend.api(), extraOverrides: [attachmentStoreProvider.overrideWithValue(store)]);

      await tester.tap(find.text('ДЗ').last);
      await _settle(tester);
      await tester.tap(find.textContaining('Староста'));
      await _settle(tester);
      expect(find.text('Лекция.pdf'), findsOneWidget);
      expect(find.byIcon(Icons.download_rounded), findsOneWidget); // ещё не скачан

      await tester.tap(find.text('Лекция.pdf'));
      await _settle(tester);
      expect(store.opened, ['Лекция.pdf']);
      expect(backend.calls.where((c) => c == 'get_group_file'), hasLength(1));
      expect(find.byIcon(Icons.download_rounded), findsNothing); // теперь лежит в телефоне

      await tester.tap(find.text('Лекция.pdf'));
      await _settle(tester);
      expect(store.opened, ['Лекция.pdf', 'Лекция.pdf']);
      expect(backend.calls.where((c) => c == 'get_group_file'), hasLength(1));
    });

    testWidgets('ДЗ удалили на сервере (например, через 3 недели после срока): скачанный файл стирается из телефона', (tester) async {
      final store = FakeAttachmentStore();
      addTearDown(() => store.dir.deleteSync(recursive: true));
      final backend = FakeBackend(hash: groupHash());
      backend.files['f1'] = (name: 'Лекция.pdf', bytes: [1, 2, 3]);
      backend.homework['h1'] = backend.hw(files: [
        {'id': 'f1', 'name': 'Лекция.pdf', 'size': 3},
      ]);
      await _start(tester, prefs: profile, sharedApi: backend.api(), extraOverrides: [attachmentStoreProvider.overrideWithValue(store)]);

      await tester.tap(find.text('ДЗ').last);
      await _settle(tester);
      await tester.tap(find.textContaining('Староста'));
      await _settle(tester);
      await tester.tap(find.text('Лекция.pdf'));
      await _settle(tester);
      expect(store.opened, ['Лекция.pdf']);
      expect(store.dir.listSync(), hasLength(1)); // файл лежит в телефоне

      // сервер убрал ДЗ (помечено удалённым позже, чем телефон последний раз обновлялся)
      backend.homework['h1'] = {...backend.homework['h1']!, 'deleted': true, 'updated_at': '2026-10-09T13:00:00+00:00'};
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); // как при возвращении в приложение
      await _settle(tester);

      expect(store.dir.listSync(), isEmpty); // скачанный файл стёрт
      expect(store.deleted, ['Лекция.pdf']);
    });

    testWidgets('нет интернета при скачивании файла: понятное сообщение, файл можно скачать позже', (tester) async {
      final store = FakeAttachmentStore();
      addTearDown(() => store.dir.deleteSync(recursive: true));
      final backend = FakeBackend(hash: groupHash());
      backend.homework['h1'] = backend.hw(files: [
        {'id': 'нет-на-сервере', 'name': 'Лекция.pdf', 'size': 3},
      ]);
      await _start(tester, prefs: profile, sharedApi: backend.api(), extraOverrides: [attachmentStoreProvider.overrideWithValue(store)]);

      await tester.tap(find.text('ДЗ').last);
      await _settle(tester);
      await tester.tap(find.textContaining('Староста'));
      await _settle(tester);
      await tester.tap(find.text('Лекция.pdf'));
      await _settle(tester);
      expect(find.textContaining('Файл не найден на сервере'), findsOneWidget);
      expect(store.opened, isEmpty);
      expect(find.byIcon(Icons.download_rounded), findsOneWidget); // осталась возможность повторить
    });

    testWidgets('ДЗ для подгруппы: студент видит общее и своё, ДЗ другой подгруппы скрыто', (tester) async {
      final backend = FakeBackend(hash: groupHash());
      backend.homework['all'] = {...backend.hw(id: 'all', text: 'Для всех'), 'subgroup': null};
      backend.homework['mine'] = {...backend.hw(id: 'mine', text: 'Для моей подгруппы'), 'subgroup': 1};
      backend.homework['other'] = {...backend.hw(id: 'other', text: 'Для второй подгруппы'), 'subgroup': 2};
      await _start(tester, prefs: profile, sharedApi: backend.api()); // профиль: подгруппа 1
      await tester.tap(find.text('ДЗ').last);
      await _settle(tester);

      expect(find.textContaining('Староста (2)'), findsOneWidget);
      await tester.tap(find.textContaining('Староста'));
      await _settle(tester);
      expect(find.text('Для всех'), findsOneWidget);
      expect(find.text('Для моей подгруппы'), findsOneWidget);
      expect(find.text('Для второй подгруппы'), findsNothing);
      expect(find.text('для БИ-25-1'), findsOneWidget);
    });

    testWidgets('староста видит ДЗ всех подгрупп и может удалить любое', (tester) async {
      final backend = FakeBackend(hash: groupHash());
      backend.homework['other'] = {...backend.hw(id: 'other', text: 'Для второй подгруппы'), 'subgroup': 2};
      await _start(tester, prefs: {...profile, 'editorToken': 'tok-GOODCODE', 'editorGroup': 'ofo-1-bi-25'}, sharedApi: backend.api());
      await tester.tap(find.text('ДЗ').last);
      await _settle(tester);
      await tester.tap(find.textContaining('Староста'));
      await _settle(tester);
      expect(find.text('Для второй подгруппы'), findsOneWidget);
      expect(find.text('для БИ-25-2'), findsOneWidget);
      expect(find.byTooltip('Удалить для всей группы'), findsOneWidget);
    });

    testWidgets('староста: у предмета с подгруппами можно выбрать подгруппу, у остальных выбора нет', (tester) async {
      final backend = FakeBackend(hash: groupHash());
      await _start(tester, prefs: {...profile, 'editorToken': 'tok-GOODCODE', 'editorGroup': 'ofo-1-bi-25'}, sharedApi: backend.api());

      Future<void> openSheet(String subject) async {
        await tester.tap(find.text('ДЗ').last);
        await _settle(tester);
        await tester.tap(find.text('Добавить ДЗ'));
        await _settle(tester);
        await tester.tap(find.byType(DropdownMenu<String>));
        await _settle(tester);
        await tester.tap(find.text(subject).last);
        await _settle(tester);
        await tester.enterText(find.byType(TextField).last, 'Выучить слова');
        await tester.tap(find.text('Для всей группы'));
        await _settle(tester);
      }

      // Философия делится не по подгруппам — выбора нет
      await openSheet('Философия');
      expect(find.text('Для кого ДЗ'), findsNothing);
      await tester.tapAt(const Offset(10, 10)); // закрыть окно
      await _settle(tester);

      await openSheet('Иностранный язык');
      expect(find.text('Для кого ДЗ'), findsOneWidget);
      await tester.tap(find.text('БИ-25-2'));
      await _settle(tester);
      await tester.tap(find.text('Добавить'));
      await _settle(tester);

      final saved = backend.homework.values.single;
      expect(saved['subject'], 'Иностранный язык');
      expect(saved['subgroup'], 2);
    });

    testWidgets('когда расписание обновилось (новый хеш), староста стирает устаревшие правки на сервере', (tester) async {
      final backend = FakeBackend(hash: 'старый-хеш');
      backend.overrides['o1'] = backend.override(); // привязана к «старому» расписанию
      await _start(tester, prefs: {...profile, 'editorToken': 'tok-GOODCODE', 'editorGroup': 'ofo-1-bi-25'}, sharedApi: backend.api());
      await _settle(tester);
      await _settle(tester);

      expect(backend.calls, contains('clear_stale_group_overrides'));
      expect(backend.overrides['o1']!['deleted'], isTrue);
      expect(find.text('3-33'), findsNothing);
    });

    testWidgets('без интернета остаётся то, что сохранено в телефоне; ошибок на экране нет', (tester) async {
      final backend = FakeBackend(hash: groupHash());
      backend.overrides['o1'] = backend.override();
      final failing = SharedApi('https://fake.test', 'key', client: MockClient((_) async => throw http.ClientException('нет сети')));
      await _start(tester, prefs: profile, sharedApi: failing);
      await _settle(tester);
      expect(find.text('3-33'), findsNothing); // ещё ничего не скачано
      expect(find.text('ЧТК и этика'), findsWidgets); // обычное расписание работает
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Поиск: свободные аудитории и расписание преподавателя', (tester) async {
    await _start(tester, prefs: profile); // среда 07.10.2026 13:30 МСК, 3 пара идёт

    await tester.tap(find.text('Поиск').last);
    await _settle(tester);

    // Преподаватель: набираем имя («Сайд-Усманович» — из середины полного ФИО) → выбираем из подсказок
    await tester.enterText(find.byType(TextField).first, 'Сайд-Усман');
    await _settle(tester);
    await tester.tap(find.text('Халиев Магомед Сайд-Усманович').last);
    await _settle(tester);
    expect(find.textContaining('Сейчас ведёт: Технологическое предпринимательство'), findsOneWidget);

    // Свободные аудитории на 3 пару: 2-05 занята, значит в списке свободных её нет
    await tester.tap(find.text('Свободные'));
    await _settle(tester);
    await tester.tap(find.text('3 пара'));
    await _settle(tester);
    expect(find.textContaining('свободно'), findsOneWidget);
    expect(find.widgetWithText(Chip, '2-05'), findsNothing);
    expect(find.widgetWithText(Chip, '3 корпус'), findsNothing); // «3 корпус» — не аудитория
  });

  testWidgets('Баннер «Расписание обновилось» показывается и закрывается кнопкой «Понятно»', (tester) async {
    await _start(tester, prefs: {...profile, 'updateBanner': ['Изменено: Ср, 4 пара — ЧТК и этика (аудитория: 2-15 → 2-16)']});
    expect(find.text('Расписание обновилось: 1 изменение'), findsOneWidget);
    expect(find.textContaining('2-15 → 2-16'), findsOneWidget);

    await tester.tap(find.text('Понятно'));
    await _settle(tester);
    expect(find.text('Расписание обновилось: 1 изменение'), findsNothing);
  });

  testWidgets('Крупный шрифт (×2) и узкий экран: ни на одной вкладке нет переполнения', (tester) async {
    // Настоящий шрифт приложения: тестовый шрифт Ahem намного шире и дал бы ложные переполнения
    await tester.runAsync(() async {
      final loader = FontLoader('Onest')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/Onest.ttf').readAsBytesSync())));
      await loader.load();
    });
    // Подсказка про виджет тоже показана (телефон умеет добавлять виджеты) — она не должна переполняться
    await _start(tester, prefs: profile, extraOverrides: [widgetPinnerProvider.overrideWithValue(FakeWidgetPinner(supported: true))]);
    tester.view.physicalSize = const Size(320, 640); // узкий телефон
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _settle(tester);

    for (final tab in ['Сегодня', 'Неделя', 'ДЗ', 'Поиск', 'Настройки']) {
      await tester.tap(find.text(tab).last);
      await _settle(tester);
      final problem = tester.takeException();
      if (problem != null) fail('вкладка «$tab» ломается при крупном шрифте: $problem');
    }
  });

  testWidgets('Крупный шрифт (×2): поиск преподавателя с длинным полным ФИО и режимы поиска не ломаются', (tester) async {
    await tester.runAsync(() async {
      final loader = FontLoader('Onest')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/Onest.ttf').readAsBytesSync())));
      await loader.load();
    });
    await _start(tester, prefs: profile);
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _settle(tester);

    await tester.tap(find.text('Поиск').last);
    await _settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Сайд-Усман');
    await _settle(tester);
    await tester.tap(find.text('Халиев Магомед Сайд-Усманович').last);
    await _settle(tester);
    expect(tester.takeException(), isNull);

    for (final mode in ['Аудитория', 'Свободные', 'Преподаватель']) {
      await tester.tap(find.text(mode));
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'режим «$mode»');
    }
  });

  testWidgets('Уведомления: план строится из расписания, разрешение спрашивается один раз', (tester) async {
    final gateway = FakeGateway();
    await _start(tester, prefs: profile, gateway: gateway); // среда 07.10.2026 13:30 МСК
    await _settle(tester);

    expect(gateway.permissionRequests, 1);
    expect(gateway.plans, isNotEmpty);
    final titles = gateway.lastPlan.map((n) => n.title).toList();
    expect(titles.first, 'ЧТК и этика → 2-15'); // пара в 14:40, напоминание в 14:30
    expect(titles, isNot(contains('Технологическое предпринимательство → 2-05'))); // уже идёт
  });

  testWidgets('Уведомления: если разрешения нет, кнопка в настройках открывает настройки телефона', (tester) async {
    final gateway = FakeGateway()..grantOnRequest = false; // пользователь отказал
    await _start(tester, prefs: {...profile, 'notificationAskCount': 2}, gateway: gateway);
    await tester.tap(find.text('Настройки').last);
    await _settle(tester);
    expect(gateway.permissionRequests, 0, reason: 'после двух вопросов при запуске больше не спрашиваем');

    await tester.tap(find.text('Разрешить уведомления'));
    await _settle(tester);
    expect(gateway.settingsOpened, 1);
  });

  testWidgets('Уведомления: нажатие открывает нужный день или вкладку «ДЗ»', (tester) async {
    final gateway = FakeGateway();
    await _start(tester, prefs: profile, gateway: gateway); // среда 07.10.2026
    expect(gateway.lastPlan.first.payload, 'day:2026-10-07');
    expect(find.textContaining('7 октября'), findsWidgets);

    gateway.tapController.add('day:2026-10-09'); // пятница
    await _settle(tester);
    expect(find.textContaining('9 октября'), findsWidgets);
    expect(find.textContaining('7 октября'), findsNothing);

    gateway.tapController.add(homeworkPayload);
    await _settle(tester);
    expect(find.text('Добавить ДЗ'), findsOneWidget);
  });

  testWidgets('Личные правки: отмена пары убирает её с экрана и из уведомлений, «Мои правки» возвращает', (tester) async {
    final gateway = FakeGateway();
    await _start(tester, prefs: profile, gateway: gateway);
    expect(find.text('ЧТК и этика'), findsWidgets);

    // Долгое нажатие на строку пары → «Отменить пару»
    await tester.longPress(find.text('ЧТК и этика').last);
    await _settle(tester);
    expect(find.text('Отменить пару'), findsOneWidget);
    await tester.tap(find.text('Отменить пару'));
    await _settle(tester);

    expect(find.text('ЧТК и этика'), findsNothing);
    expect(gateway.lastPlan.map((n) => n.title), isNot(contains('ЧТК и этика → 2-15')));
    expect(find.text('Мои правки (1)'), findsOneWidget);

    // Открываем список правок и убираем отмену
    await tester.tap(find.text('Мои правки (1)'));
    await _settle(tester);
    expect(find.text('Отменена: 4 пара'), findsOneWidget);
    await tester.tap(find.byTooltip('Убрать правку'));
    await _settle(tester);
    await tester.tapAt(const Offset(10, 10)); // закрыть окно
    await _settle(tester);

    expect(find.text('ЧТК и этика'), findsWidgets);
    expect(gateway.lastPlan.map((n) => n.title), contains('ЧТК и этика → 2-15'));
  });

  testWidgets('Личные правки: изменение аудитории показывается на экране и помечается', (tester) async {
    await _start(tester, prefs: profile);
    await tester.longPress(find.text('ЧТК и этика').last);
    await _settle(tester);
    await tester.tap(find.text('Изменить'));
    await _settle(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Аудитория'), '3-01');
    await tester.tap(find.text('Сохранить'));
    await _settle(tester);

    expect(find.text('3-01'), findsWidgets);
    expect(find.text('2-15'), findsNothing);
    expect(find.text('изменено вами'), findsOneWidget);
  });

  testWidgets('Личные правки: своя пара на свободный день', (tester) async {
    // Пятница 09.10 у юношей пуста (физ-ра только у девушек). Приложение сразу открывает субботу — листаем назад
    await _start(tester, prefs: profile, now: DateTime.utc(2026, 10, 9, 8, 0)); // пт 09.10, 11:00 МСК
    await tester.fling(find.byType(PageView), const Offset(600, 0), 2000);
    await _settle(tester);
    await tester.pumpAndSettle(); // дать странице докатиться до конца
    await _settle(tester);
    expect(find.textContaining('пятница, 9 октября'), findsOneWidget);
    expect(find.text('Пар нет'), findsOneWidget);

    await tester.tap(find.text('Мои правки').hitTestable());
    await _settle(tester);
    await tester.tap(find.text('Добавить свою пару'));
    await _settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Название'), 'Консультация');
    await tester.enterText(find.widgetWithText(TextField, 'Аудитория'), '2-10');
    await tester.pump();
    await tester.tap(find.text('Добавить'));
    await _settle(tester);
    await tester.tapAt(const Offset(10, 10));
    await _settle(tester);

    expect(find.text('Консультация'), findsWidgets);
    expect(find.text('2-10'), findsWidgets);
  });

  testWidgets('Перенос пары: ЧТК с 4 пары на 5 — на экране «перенесено», старое место пустое', (tester) async {
    final gateway = FakeGateway();
    await _start(tester, prefs: profile, gateway: gateway); // ср 07.10, 13:30
    await tester.longPress(find.text('ЧТК и этика').last);
    await _settle(tester);
    await tester.tap(find.text('Перенести'));
    await _settle(tester);
    expect(find.text('Перенести пару'), findsOneWidget);

    await tester.tap(find.text('5 пара'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Перенести'));
    await _settle(tester);

    // Время 5 пары — 16:20 (раньше ЧТК была в 14:40)
    expect(find.text('16:20'), findsOneWidget);
    expect(find.text('14:40'), findsNothing);
    expect(find.text('перенесено'), findsOneWidget);
    // Напоминание теперь за 10 минут до 16:20, то есть в 16:10 (13:10 UTC)
    expect(gateway.lastPlan.first.title, 'ЧТК и этика → 2-15');
    expect(gateway.lastPlan.first.fireAt, DateTime.utc(2026, 10, 7, 13, 10));
  });

  testWidgets('Отмена каждую неделю: в «Мои правки» видно правило, удаление возвращает пару', (tester) async {
    await _start(tester, prefs: profile);
    await tester.longPress(find.text('ЧТК и этика').last);
    await _settle(tester);
    await tester.tap(find.text('Отменить каждую неделю'));
    await _settle(tester);
    expect(find.text('ЧТК и этика'), findsNothing);

    await tester.tap(find.text('Мои правки (1)'));
    await _settle(tester);
    expect(find.textContaining('каждую неделю'), findsWidgets);
    await tester.tap(find.byTooltip('Убрать правку'));
    await _settle(tester);
    await tester.tapAt(const Offset(10, 10));
    await _settle(tester);
    expect(find.text('ЧТК и этика'), findsWidgets);
  });


  group('Режим преподавателя', () {
    // Преподаватель, у которого в среду 7 октября 13:00 общая лекция «Технологическое предпринимательство» у двух групп БИ-25
    const teacher = 'Халиев Магомед Сайд-Усманович';
    const teacherPrefs = {'role': 'teacher', 'teacherName': teacher};
    const teacherSession = {'teacherToken': 'tok-teacher-TEACHCODE', 'teacherCodeName': 'Халиев М.С-У.', 'teacherCodeGroups': ['ofo-1-bi-25', 'ofo-2-bi-25']};

    testWidgets('первый запуск: «Я преподаватель» → поиск себя в списке → расписание, где вместо преподавателя группы', (tester) async {
      await _start(tester);
      await tester.tap(find.text('Я преподаватель'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).first, 'Халиев');
      await _settle(tester);
      await tester.tap(find.text(teacher));
      await _settle(tester);

      // среда 07.10.2026 13:30: идёт общая лекция, на карточке группы
      expect(find.text('Технологическое предпринимательство'), findsWidgets);
      expect(find.textContaining('1\u00A0БИ-25'), findsWidgets);
      expect(find.textContaining('2\u00A0БИ-25'), findsWidgets);
      expect(find.text('Мои правки'), findsNothing); // личных правок у преподавателя нет
      expect(tester.takeException(), isNull);
    });

    testWidgets('меню пары у преподавателя: группы, «Отправить ДЗ студентам», без «Отменить/Перенести/Изменить»', (tester) async {
      await _start(tester, prefs: teacherPrefs);
      await _settle(tester);
      await tester.longPress(find.text('Технологическое предпринимательство').last);
      await _settle(tester);
      expect(find.text('Группы'), findsOneWidget);
      expect(find.text('Отправить ДЗ студентам'), findsOneWidget);
      expect(find.text('Название и цвет'), findsOneWidget);
      expect(find.text('Отменить пару'), findsNothing);
      expect(find.text('Перенести'), findsNothing);
      expect(find.text('Изменить'), findsNothing);
    });

    testWidgets('вкладка «ДЗ» без кода предлагает ввести код: неверный — ошибка, верный — открывается отправка', (tester) async {
      final backend = FakeBackend();
      await _start(tester, prefs: teacherPrefs, sharedApi: backend.api());
      await tester.tap(find.text('ДЗ').last);
      await _settle(tester);
      expect(find.text('Домашка студентам'), findsOneWidget);
      expect(find.text('Ввести код'), findsOneWidget);

      await tester.tap(find.text('Ввести код'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).last, 'WRONG');
      await tester.tap(find.text('Подтвердить'));
      await _settle(tester);
      expect(find.textContaining('Код не подошёл'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'teachcode'); // регистр не важен
      await tester.tap(find.text('Подтвердить'));
      await _settle(tester);
      expect(find.textContaining('Подпись для студентов: Халиев М.С-У.'), findsOneWidget);
      expect(find.text('Отправить ДЗ'), findsOneWidget);
      expect(find.text('Вы пока ничего не отправляли'), findsOneWidget);
    });

    testWidgets('отправка ДЗ: уходит всем разрешённым группам предмета и появляется в списке отправленного', (tester) async {
      final backend = FakeBackend();
      await _start(tester, prefs: {...teacherPrefs, ...teacherSession}, sharedApi: backend.api());
      await _settle(tester);

      await tester.longPress(find.text('Технологическое предпринимательство').last);
      await _settle(tester);
      await tester.tap(find.text('Отправить ДЗ студентам'));
      await _settle(tester);
      expect(find.text('1 БИ-25'), findsWidgets); // кнопки групп
      await tester.enterText(find.byType(TextField).last, 'Подготовить доклад');
      await tester.pump();
      await tester.tap(find.text('Отправить'));
      await _settle(tester);

      expect(backend.calls, contains('put_teacher_homework'));
      expect(backend.teacherRows.values.map((r) => r['group_id']).toSet(), {'ofo-1-bi-25', 'ofo-2-bi-25'});
      final row = backend.teacherRows.values.first;
      expect(row['body'], 'Подготовить доклад');
      expect(row['subject'], 'Технологическое предпринимательство');
      expect(row['author'], 'Халиев М.С-У.');

      await tester.tap(find.text('ДЗ').last);
      await _settle(tester);
      expect(find.text('Подготовить доклад'), findsOneWidget);
      expect(find.text('1 БИ-25'), findsWidgets);

      // удалить у студентов
      await tester.tap(find.byTooltip('Действия с заданием'));
      await _settle(tester);
      await tester.tap(find.text('Удалить у студентов'));
      await _settle(tester);
      await tester.tap(find.text('Удалить'));
      await _settle(tester);
      expect(backend.teacherRows.values.every((r) => r['deleted'] == true), isTrue);
      expect(find.text('Подготовить доклад'), findsNothing);
    });

    testWidgets('группа, которой нет в коде преподавателя, не предлагается и объясняется', (tester) async {
      final backend = FakeBackend()..teacherCodes['TEACHCODE'] = (name: 'Халиев М.С-У.', groups: ['ofo-1-bi-25']);
      await _start(tester, prefs: {...teacherPrefs, 'teacherToken': 'tok-teacher-TEACHCODE', 'teacherCodeName': 'Халиев М.С-У.', 'teacherCodeGroups': ['ofo-1-bi-25']}, sharedApi: backend.api());
      await _settle(tester);
      await tester.longPress(find.text('Технологическое предпринимательство').last);
      await _settle(tester);
      await tester.tap(find.text('Отправить ДЗ студентам'));
      await _settle(tester);
      expect(find.textContaining('Нет разрешения на отправку'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Текст');
      await tester.pump();
      await tester.tap(find.text('Отправить'));
      await _settle(tester);
      expect(backend.teacherRows.values.map((r) => r['group_id']).toSet(), {'ofo-1-bi-25'});
    });

    testWidgets('студент видит ДЗ преподавателя во вкладке «Преподаватели» с именем автора', (tester) async {
      final backend = FakeBackend();
      backend.teacherRows['b/ofo-1-bi-25'] = {
        'id': 'b/ofo-1-bi-25', 'group_id': 'ofo-1-bi-25', 'batch_id': 'b', 'author': 'Халиев М.С-У.', 'subject': 'Философия',
        'body': 'Прочитать главу 5', 'due_date': '2026-10-14', 'kind': null, 'subgroup': null, 'files': <Map<String, dynamic>>[],
        'deleted': false, 'updated_at': '2026-10-09T12:00:00+00:00',
      };
      await _start(tester, prefs: profile, sharedApi: backend.api());
      await _settle(tester);
      await tester.tap(find.text('ДЗ').last);
      await _settle(tester);
      await tester.tap(find.textContaining('Преподаватели'));
      await _settle(tester);
      expect(find.text('Прочитать главу 5'), findsOneWidget);
      expect(find.textContaining('от преподавателя: Халиев Магомед Сайд-Усманович'), findsOneWidget);
      expect(find.byTooltip('Удалить для всей группы'), findsNothing); // удалять может только преподаватель
    });

    testWidgets('переключение ролей: студент → преподаватель → студент, профиль студента сохраняется', (tester) async {
      await _start(tester, prefs: profile);
      expect(find.text('ЧТК и этика'), findsWidgets);

      await tester.tap(find.text('Настройки').last);
      await _settle(tester);
      await tester.tap(find.text('Я преподаватель'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).first, 'Халиев');
      await _settle(tester);
      await tester.tap(find.text(teacher));
      await _settle(tester);

      // теперь расписание преподавателя
      await tester.tap(find.text('Сегодня').last);
      await _settle(tester);
      expect(find.textContaining('1\u00A0БИ-25'), findsWidgets);
      expect(find.text('ЧТК и этика'), findsNothing);

      await tester.tap(find.text('Настройки').last);
      await _settle(tester);
      expect(find.text('Режим студента'), findsOneWidget);
      await tester.tap(find.text('Режим студента'));
      await _settle(tester);
      await tester.tap(find.text('Сегодня').last);
      await _settle(tester);
      expect(find.text('ЧТК и этика'), findsWidgets); // группа студента на месте
    });
  });

  group('Обновление приложения', () {
    List overridesFor(String current, UpdateInfo info) => [
          appVersionProvider.overrideWithValue(current),
          updateEnabledProvider.overrideWithValue(true),
          updateFetcherProvider.overrideWithValue(() async => info),
        ];

    testWidgets('на сайте версия новее: над содержимым появляется плашка, «Позже» её убирает', (tester) async {
      await _start(tester, prefs: profile, extraOverrides: overridesFor('0.3.4', const UpdateInfo(latest: '0.3.5')));
      expect(find.text('Вышла версия 0.3.5'), findsOneWidget);
      expect(find.text('2 неделя'), findsOneWidget); // расписание на месте
      await tester.tap(find.byTooltip('Позже'));
      await tester.pump();
      expect(find.text('Вышла версия 0.3.5'), findsNothing);
    });

    testWidgets('версия ниже минимальной: вместо приложения — экран «Нужно обновить»', (tester) async {
      await _start(tester, prefs: profile, extraOverrides: overridesFor('0.3.0', const UpdateInfo(latest: '0.3.5', min: '0.3.3')));
      expect(find.text('Нужно обновить приложение'), findsOneWidget);
      expect(find.text('Сегодня'), findsNothing);
    });

    testWidgets('нет данных о новой версии: плашки и блокировки нет', (tester) async {
      await _start(tester, prefs: profile);
      expect(find.textContaining('Вышла версия'), findsNothing);
      expect(find.text('Нужно обновить приложение'), findsNothing);
    });
  });

  group('Удобство на разных экранах', () {
    testWidgets('первый запуск на небольшом экране: после выбора формы список сам подкручивается к «Курсу»', (tester) async {
      await _start(tester);
      tester.view.physicalSize = const Size(390, 700);
      await tester.pump();
      await tester.tap(find.text('Очная'));
      await _settle(tester);
      // шаг «Курс» целиком в пределах экрана (без прокрутки он был бы ниже края)
      expect(tester.getRect(find.text('4 курс')).bottom, lessThanOrEqualTo(700));
      await tester.tap(find.text('2 курс'));
      await _settle(tester);
      expect(tester.getRect(find.text('1 БИ-25')).bottom, lessThanOrEqualTo(700));
    });

    testWidgets('широкий экран (компьютер): приложение встаёт колонкой по центру, а не растягивается на всю ширину', (tester) async {
      await _start(tester, prefs: profile);
      tester.view.physicalSize = const Size(1500, 900);
      await tester.pump();
      await _settle(tester);
      final scaffold = tester.getRect(find.byType(Scaffold).first);
      expect(scaffold.width, 720);
      expect(scaffold.center.dx, 750); // по центру окна
    });

    testWidgets('телефон: ширина не ограничивается', (tester) async {
      await _start(tester, prefs: profile);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      await _settle(tester);
      expect(tester.getRect(find.byType(Scaffold).first).width, 390);
    });
  });

  group('Неделя: дни отделены друг от друга', () {
    testWidgets('у каждого дня своя полоса: число, сколько пар, «сегодня»; сверху даты недели', (tester) async {
      await _start(tester, prefs: profile); // 07.10.2026, среда, 2 неделя
      await tester.tap(find.text('Неделя').last);
      await _settle(tester);

      expect(find.text('5–10 октября'), findsOneWidget); // даты недели в верхней панели
      expect(find.text('2 неделя · сейчас'), findsOneWidget);
      expect(find.text('Понедельник'), findsOneWidget);
      expect(find.text('4 пары · 09:00–16:10'), findsOneWidget); // сколько пар в этот день и во сколько
      expect(find.text('5'), findsWidgets); // плитка с числом дня
      expect(find.text('сегодня'), findsOneWidget); // только у 7 октября
      expect(find.text('Среда'), findsOneWidget);
    });

    testWidgets('дни без пар компактные: «пар нет», без точек и карточек', (tester) async {
      await _start(tester, prefs: profile);
      await tester.tap(find.text('Неделя').last);
      await _settle(tester);
      expect(find.textContaining('пар нет'), findsWidgets);
    });

    testWidgets('переключатель недели остаётся на месте и меняет даты', (tester) async {
      await _start(tester, prefs: profile);
      await tester.tap(find.text('Неделя').last);
      await _settle(tester);
      await tester.tap(find.text('1 неделя'));
      await _settle(tester);
      expect(find.text('12–17 октября'), findsOneWidget);
      expect(find.text('сегодня'), findsNothing); // сегодня во 2 неделе
    });
  });

  group('Неделя в воскресенье', () {
    testWidgets('воскресенье без своих пар: «Неделя» открывается на следующей неделе', (tester) async {
      // 11.10.2026 — воскресенье конца 2 недели (5–10 октября); следующая — 1 неделя, 12–17 октября
      await _start(tester, prefs: profile, now: DateTime.utc(2026, 10, 11, 10, 30));
      await tester.tap(find.text('Неделя').last);
      await _settle(tester);
      expect(find.text('12–17 октября'), findsOneWidget);
      expect(find.text('1 неделя · сейчас'), findsOneWidget);
      expect(find.text('сегодня'), findsNothing); // сегодня воскресенье, его в списке дней нет
    });

    testWidgets('в субботу неделя ещё текущая', (tester) async {
      await _start(tester, prefs: profile, now: DateTime.utc(2026, 10, 10, 10, 30));
      await tester.tap(find.text('Неделя').last);
      await _settle(tester);
      expect(find.text('5–10 октября'), findsOneWidget);
      expect(find.text('2 неделя · сейчас'), findsOneWidget);
    });
  });

  test('даты недели: в одном месяце и на стыке месяцев', () {
    expect(weekRangeText(DateTime(2026, 10, 5), DateTime(2026, 10, 10)), '5–10 октября');
    expect(weekRangeText(DateTime(2026, 9, 28), DateTime(2026, 10, 3)), '28 сент – 3 окт');
  });
}
