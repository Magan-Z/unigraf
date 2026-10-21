// Аттестация, зачёт, экзамен: тип в «замене», слияние правок, ближайшие занятия, тексты, уведомление о новом объявлении.

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unigraf/app_state.dart';
import 'package:unigraf/background/background_sync.dart';
import 'package:unigraf/core/clock.dart';
import 'package:unigraf/data/local/database.dart';
import 'package:unigraf/data/repositories/overrides_repository.dart';
import 'package:unigraf/data/repositories/schedule_repository.dart';
import 'package:unigraf/domain/assessments.dart';
import 'package:unigraf/domain/homework.dart';
import 'package:unigraf/domain/models.dart';
import 'package:unigraf/domain/notification_plan.dart';
import 'package:unigraf/domain/overrides_text.dart';
import 'package:unigraf/domain/schedule_resolver.dart';

import 'support/fakes.dart';

Map<String, dynamic> _fixture(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final index = ScheduleIndex.fromJson(_fixture('index.json'));
  final schedule = GroupSchedule.fromJson(_fixture('ofo-1-bi-25.json'));
  const profile = UserProfile(formCode: 'ofo', groupId: 'ofo-1-bi-25', subgroup: 1, pe: PeChoice.male);
  final wed = DateTime.utc(2026, 10, 7); // 2 неделя: ЧТК и этика, практика, 4 пара

  ResolvedLesson chtk(DateTime day, [List<Override> o = const []]) =>
      resolve(day, index, schedule, profile, overrides: o).firstWhere((l) => l.subject == 'ЧТК и этика');

  group('Тип занятия в правке «заменить»', () {
    test('аттестация меняет тип пары, предмет, преподаватель и аудитория остаются', () {
      final base = chtk(wed);
      final l = chtk(wed, [Override(date: wed, pair: 4, type: OverrideType.replace, kind: LessonKind.attestation, matchSubject: 'ЧТК и этика', note: 'Аттестация')]);
      expect(base.kind, LessonKind.practice);
      expect(l.kind, LessonKind.attestation);
      expect((l.subject, l.teacher, l.room, l.pair), (base.subject, base.teacher, base.room, base.pair));
      expect(l.startAt, base.startAt);
    });

    test('правка с названием предмета не задевает другой предмет на той же паре', () {
      final lessons = resolve(wed, index, schedule, profile,
          overrides: [Override(date: wed, pair: 3, type: OverrideType.replace, kind: LessonKind.exam, matchSubject: 'Другой предмет')]);
      expect(lessons.every((l) => !l.kind.isAssessment), isTrue);
    });

    test('групповая правка «заменить» с типом тоже применяется', () {
      final o = Override(date: wed, pair: 4, type: OverrideType.replace, kind: LessonKind.credit, fromGroup: true, matchSubject: 'ЧТК и этика');
      final l = chtk(wed, [o]);
      expect(l.kind, LessonKind.credit);
      expect(l.isGroup, isTrue);
    });

    test('«своя пара» с видом «экзамен» — экзамен', () {
      final l = resolve(wed, index, schedule, profile, overrides: [
        Override(date: wed, pair: 5, type: OverrideType.add, subject: 'Математика', kind: LessonKind.exam, room: '3-01'),
      ]).firstWhere((l) => l.subject == 'Математика');
      expect(l.kind, LessonKind.exam);
      expect(l.pair, 5);
    });

    test('название вида и буква, неизвестный вид читается как практика', () {
      expect([for (final k in announceKinds) (k.title, k.letter)], [('Аттестация', 'А'), ('Зачёт', 'З'), ('Экзамен', 'Э')]);
      expect(LessonKind.parse('exam'), LessonKind.exam);
      expect(LessonKind.parse('что-то новое'), LessonKind.practice);
      expect(LessonKind.lecture.isAssessment, isFalse);
    });
  });

  group('Правки складываются', () {
    test('mergedOver: новое поле главнее, пустое берётся из прежней правки', () {
      final old = Override(date: wed, pair: 4, type: OverrideType.replace, room: '3-33', note: 'Аттестация', kind: LessonKind.attestation, matchSubject: 'ЧТК и этика');
      final fresh = Override(date: wed, pair: 4, type: OverrideType.replace, teacher: 'Иванов И.И.');
      final m = fresh.mergedOver(old);
      expect((m.room, m.teacher, m.note, m.kind, m.matchSubject), ('3-33', 'Иванов И.И.', 'Аттестация', LessonKind.attestation, 'ЧТК и этика'));
      expect(Override(date: wed, pair: 4, type: OverrideType.replace, room: '1-01').mergedOver(old).room, '1-01');
    });

    test('личные: сменили аудиторию, потом объявили аттестацию — остались обе правки; и наоборот', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = OverridesRepository(db);
      await repo.save(Override(date: wed, pair: 4, type: OverrideType.replace, room: '3-33'));
      await repo.save(Override(date: wed, pair: 4, type: OverrideType.replace, kind: LessonKind.exam, note: 'Экзамен', matchSubject: 'ЧТК и этика'));
      var all = await repo.all();
      expect(all, hasLength(1));
      expect((all.single.room, all.single.kind, all.single.note), ('3-33', LessonKind.exam, 'Экзамен'));

      await repo.save(Override(date: wed, pair: 4, type: OverrideType.replace, room: '1-01'));
      all = await repo.all();
      expect(all, hasLength(1));
      expect((all.single.room, all.single.kind), ('1-01', LessonKind.exam));
    });

    test('замена не склеивается с «каждую неделю» и с отменой', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = OverridesRepository(db);
      await repo.save(Override(date: wed, pair: 4, type: OverrideType.replace, room: '3-33', repeatWeekly: true, matchSubject: 'ЧТК и этика'));
      await repo.save(Override(date: wed, pair: 4, type: OverrideType.replace, kind: LessonKind.credit)); // разовая
      final all = await repo.all();
      expect(all.single.room, isNull); // из правила «каждую неделю» ничего не взято
      expect(all.single.kind, LessonKind.credit);
    });
  });

  group('Ближайшие занятия', () {
    test('те же предмет и тип, по порядку, не больше четырёх', () {
      final from = chtk(wed);
      final ahead = sameLessonsAhead(from: from, index: index, schedule: schedule, profile: profile);
      expect(ahead, hasLength(4));
      expect(ahead.first.date, DateTime.utc(2026, 10, 21)); // практика ЧТК идёт на чётных неделях
      expect(ahead.every((l) => l.subject == 'ЧТК и этика' && l.kind == LessonKind.practice && l.date.isAfter(wed)), isTrue);
      expect([for (var i = 1; i < ahead.length; i++) ahead[i].date.isAfter(ahead[i - 1].date)], everyElement(isTrue));
    });

    test('у уже объявленной аттестации «следующего» нет; уже объявленные занятия не предлагаются', () {
      final announced = chtk(wed, [Override(date: wed, pair: 4, type: OverrideType.replace, kind: LessonKind.exam, matchSubject: 'ЧТК и этика')]);
      expect(sameLessonsAhead(from: announced, index: index, schedule: schedule, profile: profile), isEmpty);

      final next = DateTime.utc(2026, 10, 21);
      final skipped = sameLessonsAhead(
        from: chtk(wed),
        index: index,
        schedule: schedule,
        profile: profile,
        overrides: [Override(date: next, pair: 4, type: OverrideType.replace, kind: LessonKind.exam, matchSubject: 'ЧТК и этика')],
      );
      expect(skipped.first.date, DateTime.utc(2026, 11, 4));
    });
  });

  group('Тексты', () {
    test('заметка: название вида пишется всегда, на экране не повторяется', () {
      expect(assessmentNote(LessonKind.exam, ''), 'Экзамен');
      expect(assessmentNote(LessonKind.exam, '  темы 1–5 '), 'Экзамен: темы 1–5');
      expect(visibleNote(LessonKind.exam, 'Экзамен'), isNull);
      expect(visibleNote(LessonKind.exam, 'Экзамен: темы 1–5'), 'темы 1–5');
      expect(visibleNote(LessonKind.practice, 'перенесено'), 'перенесено');
      expect(visibleNote(LessonKind.exam, 'в 10:30'), 'в 10:30');
      expect(visibleNote(LessonKind.exam, null), isNull);
    });

    test('список правок: «Аттестация: 4 пара (ЧТК и этика)», экзамен как своя пара', () {
      expect(
        describeOverride(Override(date: wed, pair: 4, type: OverrideType.replace, kind: LessonKind.attestation, matchSubject: 'ЧТК и этика', note: 'Аттестация')),
        'Аттестация: 4 пара (ЧТК и этика)',
      );
      expect(
        describeOverride(Override(date: wed, pair: 4, type: OverrideType.replace, kind: LessonKind.credit, matchSubject: 'ЧТК и этика', room: '3-33', note: 'Зачёт: темы 1–5')),
        'Зачёт: 4 пара (ЧТК и этика) — аудитория: 3-33, заметка: темы 1–5',
      );
      expect(describeOverride(Override(date: wed, pair: 2, type: OverrideType.add, kind: LessonKind.exam, subject: 'Математика', room: '3-01')), 'Экзамен: 2 пара — Математика, 3-01');
      expect(describeOverride(Override(date: wed, pair: 2, type: OverrideType.add, subject: 'Консультация')), 'Своя пара: 2 пара — Консультация');
    });

    test('напоминание перед парой: «Аттестация: ЧТК и этика → 2-15»', () {
      final plan = planNotifications(
        now: DateTime.utc(2026, 10, 7, 5),
        index: index,
        schedule: schedule,
        profile: profile,
        homework: const <HomeworkItem>[],
        notifyBeforeMin: 10,
        eveningReminder: false,
        overrides: [Override(date: wed, pair: 4, type: OverrideType.replace, kind: LessonKind.attestation, matchSubject: 'ЧТК и этика')],
      );
      expect(plan.map((p) => p.title), contains('Аттестация: ЧТК и этика → 2-15'));
      expect(plan.where((p) => p.title.startsWith('Технолог')), isNotEmpty); // у обычной пары заголовок прежний, без приставки
      expect(plan.where((p) => p.title.startsWith('Технолог')).every((p) => !p.title.contains(':')), isTrue);
    });
  });

  test('фоновая проверка: староста объявил аттестацию — уведомление; свои и прошедшие не считаются', () async {
    final backend = FakeBackend(hash: _hashOf('ofo-1-bi-25'));
    SharedPreferences.setMockInitialValues({'form': 'ofo', 'groupId': 'ofo-1-bi-25', 'subgroup': 1, 'pe': 'male'});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final gateway = FakeGateway();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('home_widget'), (call) async => true);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('home_widget'), null));
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(FixedClock(DateTime.utc(2026, 10, 7, 5))),
      notificationGatewayProvider.overrideWithValue(gateway),
      sharedApiProvider.overrideWithValue(backend.api()),
      repositoryProvider.overrideWithValue(ScheduleRepository(db: db, assets: DiskAssets())),
    ]);
    addTearDown(container.dispose);

    // Первая проверка: уведомлений нет, телефон просто узнаёт текущее состояние
    await runBackgroundSync(container);
    expect(gateway.shown, isEmpty);

    // даты далеко от «сегодня»: проверка сравнивает с настоящими часами, а метки времени — позже ответа первой проверки
    backend.overrides['a1'] = {
      ...backend.override(id: 'a1', pair: 4, type: 'replace', room: null, date: '2099-01-14'),
      'updated_at': '2026-10-09T13:00:01+00:00',
      'kind': 'attestation',
      'match_subject': 'ЧТК и этика',
      'note': 'Аттестация',
    };
    backend.overrides['old'] = {
      ...backend.override(id: 'old', pair: 4, type: 'replace', room: null, date: '2000-01-01'),
      'updated_at': '2026-10-09T13:00:02+00:00',
      'kind': 'exam',
      'note': 'Экзамен',
    }; // уже прошла
    await runBackgroundSync(container);
    expect(gateway.shown, ['Староста объявил: аттестация']);

    await runBackgroundSync(container); // повторно о том же не говорим
    expect(gateway.shown, hasLength(1));
  });
}

String _hashOf(String groupId) {
  final index = jsonDecode(File('assets/schedule/index.json').readAsStringSync()) as Map<String, dynamic>;
  for (final form in index['forms'] as List) {
    for (final g in (form as Map)['groups'] as List) {
      if ((g as Map)['id'] == groupId) return g['hash'] as String;
    }
  }
  throw StateError('нет группы');
}
