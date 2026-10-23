// Инструмент разработчика (не часть набора тестов): рисует экраны приложения в PNG с настоящими шрифтами,
// чтобы оценить внешний вид без телефона. Запуск из папки app/:
//   flutter test tool/screenshots_test.dart
// Картинки появятся в /tmp/claude-shots/design/. Шрифт значков берётся из установленного Flutter.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unigraf/app_state.dart';
import 'package:unigraf/core/clock.dart';
import 'package:unigraf/data/local/database.dart';
import 'package:unigraf/data/remote/shared_api.dart';
import 'package:unigraf/data/repositories/schedule_repository.dart';
import 'package:unigraf/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';

const outDir = '/tmp/claude-shots/design';

// Для документов нужны снимки крупнее и в другой папке: SHOT_RATIO=3 SHOT_ROOT=/путь flutter test tool/screenshots_test.dart
final shotRatio = double.tryParse(Platform.environment['SHOT_RATIO'] ?? '') ?? 1;
final shotRoot = Platform.environment['SHOT_ROOT'] ?? '/tmp/claude-shots';
// Цветовая тема для снимков (id из brand_colors.dart: petrol, ocean, forest…): SHOT_PALETTE=ocean
final shotPalette = Platform.environment['SHOT_PALETTE'];

Future<void> loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/homebrew/share/flutter';
  Future<ByteData> read(String path) async => ByteData.sublistView(File(path).readAsBytesSync());
  final onest = FontLoader('Onest')..addFont(read('assets/fonts/Onest.ttf'));
  await onest.load();
  final icons = FontLoader('MaterialIcons')..addFont(read('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

Map<String, dynamic> backend0(String hash) => {
      'id': 'o1', 'base_hash': hash, 'date': '2026-10-07', 'pair': 4, 'type': 'replace', 'subject': null, 'room': '3-33',
      'teacher': null, 'note': null, 'kind': null, 'repeat_weekly': false, 'match_subject': null, 'deleted': false,
      'updated_at': '2026-10-09T12:00:00+00:00',
    };

Map<String, dynamic> backend0hw(String subject, String text, String due) =>
    {'id': '$subject$due', 'subject': subject, 'body': text, 'due_date': due, 'kind': null, 'deleted': false, 'updated_at': '2026-10-09T12:00:00+00:00'};

void main() {
  Future<void> shoot(WidgetTester tester, String name, {required bool dark, DateTime? now, double textScale = 1, Future<void> Function()? act, Map<String, Object> prefs = const {}, bool noProfile = false, Size size = const Size(1080, 2340), SharedApi? sharedApi, double pixelRatio = 1, String? dir}) async {
    tester.view.physicalSize = size;
    // Как на настоящем телефоне: строка состояния сверху и жестовая полоса снизу
    tester.view.padding = const FakeViewPadding(top: 72, bottom: 66);
    tester.view.viewPadding = const FakeViewPadding(top: 72, bottom: 66);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      if (!noProfile) ...{'form': 'ofo', 'groupId': 'ofo-1-bi-25', 'subgroup': 1, 'pe': 'male'},
      'theme': dark ? 'dark' : 'light',
      if (shotPalette != null) 'palette': shotPalette!,
      ...prefs,
    });
    final sp = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    await tester.runAsync(() => db.customSelect('select 1').get());
    addTearDown(() => tester.runAsync(db.close));

    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          databaseProvider.overrideWithValue(db),
          repositoryProvider.overrideWithValue(ScheduleRepository(db: db, assets: DiskAssets())),
          notificationGatewayProvider.overrideWithValue(FakeGateway()),
          sharedApiProvider.overrideWithValue(sharedApi),
          clockProvider.overrideWithValue(FixedClock(now ?? DateTime.utc(2026, 10, 7, 10, 30))), // ср 13:30 МСК
        ],
        child: const UniGrafApp(),
      ),
    ));

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    }

    await settle();
    if (name == '1-today-light') {
      debugPrint('RECT nav=${tester.getRect(find.byType(NavigationBar))} scaffold=${tester.getRect(find.byType(Scaffold).first)} view=${tester.view.physicalSize / tester.view.devicePixelRatio}');
    }
    if (act != null) {
      await act();
      await settle();
    }
    await tester.runAsync(() async {
      final target = (dir ?? outDir).replaceFirst('/tmp/claude-shots', shotRoot);
      Directory(target).createSync(recursive: true);
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: pixelRatio == 1 ? shotRatio : pixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$target/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final dark in [false, true]) {
    final suffix = dark ? 'dark' : 'light';

    testWidgets('today $suffix', (tester) async {
      await tester.runAsync(loadFonts);
      await shoot(tester, '1-today-$suffix', dark: dark);
    });

    testWidgets('week $suffix', (tester) async {
      await tester.runAsync(loadFonts);
      await shoot(tester, '2-week-$suffix', dark: dark, act: () async {
        await tester.tap(find.text('Неделя').last);
      });
    });

    testWidgets('homework $suffix', (tester) async {
      await tester.runAsync(loadFonts);
      await shoot(tester, '3-homework-$suffix', dark: dark, act: () async {
        await tester.tap(find.text('ДЗ').last);
      });
    });

    testWidgets('search $suffix', (tester) async {
      await tester.runAsync(loadFonts);
      await shoot(tester, '4-search-$suffix', dark: dark, act: () async {
        await tester.tap(find.text('Поиск').last);
      });
    });

    testWidgets('settings $suffix', (tester) async {
      await tester.runAsync(loadFonts);
      await shoot(tester, '5-settings-$suffix', dark: dark, act: () async {
        await tester.tap(find.text('Настройки').last);
      });
    });
  }

  testWidgets('onboarding', (tester) async {
    await tester.runAsync(loadFonts);
    await shoot(tester, '6-onboarding', dark: false, noProfile: true);
    await shoot(tester, '6-onboarding-dark', dark: true, noProfile: true);
  });

  for (final entry in {'today': null, 'week': 'Неделя', 'homework': 'ДЗ', 'search': 'Поиск', 'settings': 'Настройки'}.entries) {
    testWidgets('narrow big font ${entry.key}', (tester) async {
      await tester.runAsync(loadFonts);
      await shoot(tester, '8-narrow-${entry.key}', dark: false, textScale: 2, size: const Size(960, 2000), act: () async {
        if (entry.value != null) await tester.tap(find.text(entry.value!).last);
      });
    });
  }

  // Как на телефоне пользователя: шрифт крупнее обычного, вкладки поиска и этажи
  for (final tab in ['Преподаватель', 'Аудитория', 'Свободные']) {
    testWidgets('search phone $tab', (tester) async {
      await tester.runAsync(loadFonts);
      await shoot(tester, '9-search-phone-$tab', dark: false, textScale: 1.3, act: () async {
        await tester.tap(find.text('Поиск').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text(tab).first);
      });
    });
  }

  for (final entry in {'today': null, 'week': 'Неделя', 'homework': 'ДЗ', 'settings': 'Настройки'}.entries) {
    testWidgets('phone font ${entry.key}', (tester) async {
      await tester.runAsync(loadFonts);
      await shoot(tester, '9-phone-${entry.key}', dark: false, textScale: 1.3, act: () async {
        if (entry.value != null) await tester.tap(find.text(entry.value!).last);
      });
    });
  }

  // Все цветовые темы: «Сегодня» светлая и тёмная, настройки с выбором темы
  for (final id in ['ocean', 'forest', 'plum', 'sunset', 'graphite']) {
    for (final dark in [false, true]) {
      testWidgets('palette $id ${dark ? 'dark' : 'light'}', (tester) async {
        await tester.runAsync(loadFonts);
        await shoot(tester, 'A-palette-$id-${dark ? 'dark' : 'light'}', dark: dark, prefs: {'palette': id});
      });
    }
  }
  testWidgets('amoled', (tester) async {
    await tester.runAsync(loadFonts);
    await shoot(tester, 'A-amoled', dark: true, prefs: {'amoled': true, 'palette': 'ocean'});
  });
  testWidgets('settings palettes', (tester) async {
    await tester.runAsync(loadFonts);
    await shoot(tester, 'A-settings-themes', dark: false, act: () async {
      await tester.tap(find.text('Настройки').last);
      await tester.pumpAndSettle();
    });
  });

  // Староста и группа: правки видны студенту, вкладка ДЗ, настройки старосты
  String hashOfGroup() {
    final index = jsonDecode(File('assets/schedule/index.json').readAsStringSync()) as Map<String, dynamic>;
    for (final form in index['forms'] as List) {
      for (final g in (form as Map)['groups'] as List) {
        if ((g as Map)['id'] == 'ofo-1-bi-25') return g['hash'] as String;
      }
    }
    return '';
  }

  testWidgets('starosta student today', (tester) async {
    await tester.runAsync(loadFonts);
    final backend = FakeBackend(hash: hashOfGroup())..overrides['o1'] = backend0(hashOfGroup());
    await shoot(tester, 'B-starosta-today', dark: false, sharedApi: backend.api());
  });
  testWidgets('starosta homework tab', (tester) async {
    await tester.runAsync(loadFonts);
    final backend = FakeBackend(hash: hashOfGroup())
      ..homework['h1'] = backend0hw('Философия', 'Прочитать главу 3 и подготовить конспект', '2026-10-14')
      ..homework['h2'] = backend0hw('ЧТК и этика', 'Эссе на одну страницу', '2026-10-09');
    await shoot(tester, 'B-starosta-homework', dark: false, sharedApi: backend.api(), act: () async {
      await tester.tap(find.text('ДЗ').last);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Староста'));
      await tester.pumpAndSettle();
    });
  });
  testWidgets('starosta settings editor', (tester) async {
    await tester.runAsync(loadFonts);
    final backend = FakeBackend(hash: hashOfGroup());
    await shoot(tester, 'B-starosta-settings', dark: false, sharedApi: backend.api(), prefs: {'editorToken': 't', 'editorGroup': 'ofo-1-bi-25'}, act: () async {
      await tester.tap(find.text('Настройки').last);
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(find.text('Изменения для группы'), find.byType(Scrollable).first, const Offset(0, -200));
      await tester.pumpAndSettle();
    });
  });
  // Снимки для страницы-лендинга (data/web): высокое разрешение (1080×2340), настоящие шрифты, данные «как у живой группы».
  // Запуск:  flutter test tool/screenshots_test.dart --plain-name landing   →  /tmp/claude-shots/landing/
  const landingDir = '/tmp/claude-shots/landing';
  FakeBackend landingBackend() {
    final backend = FakeBackend(hash: hashOfGroup());
    final change = backend.override(room: '3-33')..['updated_at'] = '2026-10-07T07:30:00+00:00'; // староста в 10:30 по Москве
    backend.overrides['o1'] = change;
    backend.homework['h1'] = backend.hw(id: 'h1', subject: 'Философия', text: 'Прочитать главу 3, подготовить конспект', due: '2026-10-14',
        files: [{'id': 'f1', 'name': 'Глава 3.pdf', 'size': 1800000}]);
    backend.homework['h2'] = backend.hw(id: 'h2', subject: 'ЧТК и этика', text: 'Эссе на одну страницу', due: '2026-10-09');
    backend.homework['h3'] = backend.hw(id: 'h3', subject: 'Технологическое предпринимательство', text: 'Подготовить бизнес-идею, 3 слайда', due: '2026-10-15',
        files: [{'id': 'f2', 'name': 'Шаблон слайдов.pptx', 'size': 420000}]);
    // ДЗ от преподавателя: на снимке «Домашки» видны все три вкладки («Мои», «Староста», «Преподаватели»)
    backend.teacherRows['b1/ofo-1-bi-25'] = {
      'id': 'b1/ofo-1-bi-25', 'group_id': 'ofo-1-bi-25', 'batch_id': 'b1', 'author': 'Халиев М.С-У.', 'subject': 'Технологическое предпринимательство',
      'body': 'Подготовить доклад на 5 минут по бизнес-модели', 'due_date': '2026-10-16', 'kind': null, 'subgroup': null,
      'files': <Map<String, dynamic>>[], 'deleted': false, 'updated_at': '2026-10-09T12:00:00+00:00',
    };
    return backend;
  }

  testWidgets('landing today light', (tester) async {
    await tester.runAsync(loadFonts);
    await shoot(tester, 'today-light', dark: false, sharedApi: landingBackend().api(), pixelRatio: 3, dir: landingDir);
  });
  testWidgets('landing today dark', (tester) async {
    await tester.runAsync(loadFonts);
    await shoot(tester, 'today-dark', dark: true, sharedApi: landingBackend().api(), pixelRatio: 3, dir: landingDir);
  });
  testWidgets('landing week', (tester) async {
    await tester.runAsync(loadFonts);
    await shoot(tester, 'week-light', dark: false, sharedApi: landingBackend().api(), pixelRatio: 3, dir: landingDir, act: () async {
      await tester.tap(find.text('Неделя').last);
    });
  });
  testWidgets('landing homework', (tester) async {
    await tester.runAsync(loadFonts);
    await shoot(tester, 'homework-light', dark: false, sharedApi: landingBackend().api(), pixelRatio: 3, dir: landingDir, act: () async {
      await tester.tap(find.text('ДЗ').last);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Староста'));
      await tester.pumpAndSettle();
    });
  });
  testWidgets('landing search free rooms', (tester) async {
    await tester.runAsync(loadFonts);
    await shoot(tester, 'search-free-light', dark: false, sharedApi: landingBackend().api(), pixelRatio: 3, dir: landingDir, act: () async {
      await tester.tap(find.text('Поиск').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Свободные').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 пара'));
      await tester.pumpAndSettle();
    });
  });
  testWidgets('landing search teacher schedule', (tester) async {
    await tester.runAsync(loadFonts);
    await shoot(tester, 'search-teacher-light', dark: false, sharedApi: landingBackend().api(), pixelRatio: 3, dir: landingDir, act: () async {
      await tester.tap(find.text('Поиск').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Преподаватель').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Хасанова');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Хасанова З.С.').last);
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
    });
  });
  testWidgets('today large font', (tester) async {
    await tester.runAsync(loadFonts);
    await shoot(tester, '7-today-bigfont', dark: false, textScale: 1.6);
  });

  // Режим преподавателя (запуск: flutter test tool/screenshots_test.dart --plain-name teacher → /tmp/claude-shots/teacher/)
  group('teacher', () {
    const teacherDir = '/tmp/claude-shots/teacher';
    const teacherPrefs = {'role': 'teacher', 'teacherName': 'Халиев Магомед Сайд-Усманович'};
    const session = {'teacherToken': 'tok-teacher-TEACHCODE', 'teacherCodeName': 'Халиев М.С-У.', 'teacherCodeGroups': ['ofo-1-bi-25', 'ofo-2-bi-25']};

    FakeBackend sentBackend() {
      final b = FakeBackend();
      for (final g in ['ofo-1-bi-25', 'ofo-2-bi-25']) {
        b.teacherRows['b1/$g'] = {
          'id': 'b1/$g', 'group_id': g, 'batch_id': 'b1', 'author': 'Халиев М.С-У.', 'subject': 'Технологическое предпринимательство',
          'body': 'Подготовить доклад на 5 минут по бизнес-модели', 'due_date': '2026-10-14', 'kind': null, 'subgroup': null,
          'files': <Map<String, dynamic>>[], 'deleted': false, 'updated_at': '2026-10-09T12:00:00+00:00',
        };
      }
      b.teacherRows['b2/ofo-1-bi-25'] = {
        'id': 'b2/ofo-1-bi-25', 'group_id': 'ofo-1-bi-25', 'batch_id': 'b2', 'author': 'Халиев М.С-У.', 'subject': 'Технологическое предпринимательство',
        'body': 'Прочитать главу 3 учебника', 'due_date': '2026-10-21', 'kind': 'lecture', 'subgroup': null,
        'files': [{'id': 'f1', 'name': 'Глава 3.pdf', 'size': 1800000}], 'deleted': false, 'updated_at': '2026-10-09T12:00:01+00:00',
      };
      return b;
    }

    for (final dark in [false, true]) {
      final suffix = dark ? 'dark' : 'light';
      testWidgets('teacher today $suffix', (tester) async {
        await tester.runAsync(loadFonts);
        await shoot(tester, '1-today-$suffix', dark: dark, noProfile: true, prefs: teacherPrefs, dir: teacherDir);
      });
      testWidgets('teacher week $suffix', (tester) async {
        await tester.runAsync(loadFonts);
        await shoot(tester, '2-week-$suffix', dark: dark, noProfile: true, prefs: teacherPrefs, dir: teacherDir, act: () async {
          await tester.tap(find.text('Неделя').last);
        });
      });
      testWidgets('teacher homework $suffix', (tester) async {
        await tester.runAsync(loadFonts);
        await shoot(tester, '3-homework-$suffix', dark: dark, noProfile: true, prefs: {...teacherPrefs, ...session}, sharedApi: sentBackend().api(), dir: teacherDir, act: () async {
          await tester.tap(find.text('ДЗ').last);
        });
      });
    }

    for (final dark in [false, true]) {
      testWidgets('teacher web login ${dark ? 'dark' : 'light'}', (tester) async {
        await tester.runAsync(loadFonts);
        await shoot(tester, '8-web-login-${dark ? 'dark' : 'light'}', dark: dark, noProfile: true, prefs: {...teacherPrefs, ...session}, sharedApi: sentBackend().api(), dir: teacherDir, act: () async {
          await tester.tap(find.text('ДЗ').last);
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.text('Отправить ДЗ с компьютера'));
          await tester.pump(const Duration(milliseconds: 600));
        });
      });
    }

    for (final dark in [false, true]) {
      testWidgets('teacher send sheet full ${dark ? 'dark' : 'light'}', (tester) async {
        await tester.runAsync(loadFonts);
        await shoot(tester, '9-send-sheet-${dark ? 'dark' : 'light'}', dark: dark, noProfile: true, prefs: {...teacherPrefs, ...session}, size: const Size(1080, 3400), sharedApi: sentBackend().api(), dir: teacherDir, act: () async {
          await tester.tap(find.text('Сегодня').last);
          await tester.pump(const Duration(milliseconds: 400));
          await tester.ensureVisible(find.text('Технологическое предпринимательство').last);
          await tester.pump(const Duration(milliseconds: 300));
          await tester.longPress(find.text('Технологическое предпринимательство').last);
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.text('Отправить ДЗ студентам'));
          await tester.pump(const Duration(milliseconds: 700));
          await tester.enterText(find.byType(TextField).last, 'Подготовить доклад на 5 минут по бизнес-модели');
          await tester.pump(const Duration(milliseconds: 300));
        });
      });
    }

    testWidgets('teacher homework without code', (tester) async {
      await tester.runAsync(loadFonts);
      await shoot(tester, '4-homework-nocode', dark: false, noProfile: true, prefs: teacherPrefs, sharedApi: FakeBackend().api(), dir: teacherDir, act: () async {
        await tester.tap(find.text('ДЗ').last);
      });
    });

    testWidgets('teacher send sheet', (tester) async {
      await tester.runAsync(loadFonts);
      await shoot(tester, '5-send-sheet', dark: false, noProfile: true, prefs: {...teacherPrefs, ...session}, sharedApi: sentBackend().api(), dir: teacherDir, act: () async {
        await tester.ensureVisible(find.text('Технологическое предпринимательство').last);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.longPress(find.text('Технологическое предпринимательство').last);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Отправить ДЗ студентам'));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.enterText(find.byType(TextField).last, 'Подготовить доклад на 5 минут');
      });
    });

    testWidgets('teacher lesson menu', (tester) async {
      await tester.runAsync(loadFonts);
      await shoot(tester, '6-menu', dark: false, noProfile: true, prefs: teacherPrefs, dir: teacherDir, act: () async {
        await tester.ensureVisible(find.text('Технологическое предпринимательство').last);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.longPress(find.text('Технологическое предпринимательство').last);
        await tester.pump(const Duration(milliseconds: 400));
      });
    });

    testWidgets('teacher onboarding', (tester) async {
      await tester.runAsync(loadFonts);
      await shoot(tester, '7-onboarding', dark: false, noProfile: true, dir: teacherDir, act: () async {
        await tester.tap(find.text('Я преподаватель'));
      });
    });

    testWidgets('teacher settings', (tester) async {
      await tester.runAsync(loadFonts);
      await shoot(tester, '8-settings', dark: false, noProfile: true, prefs: {...teacherPrefs, ...session}, sharedApi: sentBackend().api(), dir: teacherDir, act: () async {
        await tester.tap(find.text('Настройки').last);
      });
    });

    testWidgets('student sees teacher homework', (tester) async {
      await tester.runAsync(loadFonts);
      await shoot(tester, '9-student-teacher-tab', dark: false, sharedApi: sentBackend().api(), dir: teacherDir, act: () async {
        await tester.tap(find.text('ДЗ').last);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.textContaining('Преподаватели'));
      });
    });
  });
}

