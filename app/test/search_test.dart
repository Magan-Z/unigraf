// Поиск: преподаватель, аудитория, свободные аудитории — на реальных данных всех 50 групп.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unigraf/domain/models.dart';
import 'package:unigraf/domain/search.dart';

Map<String, dynamic> _json(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final index = ScheduleIndex.fromJson(_json('test/fixtures/index.json'));
  final schedules = [
    for (final f in Directory('test/fixtures/all').listSync().whereType<File>().where((f) => f.path.endsWith('.json')))
      GroupSchedule.fromJson(_json(f.path)),
  ];
  final wednesday = DateTime.utc(2026, 10, 7); // 2 неделя
  final lessons = campusLessons(wednesday, index, schedules);

  test('загружены все 50 групп', () => expect(schedules, hasLength(50)));

  test('воскресенье, праздник и вне семестра — пусто', () {
    expect(campusLessons(DateTime.utc(2026, 10, 11), index, schedules), isEmpty);
    final withHoliday = ScheduleIndex.fromJson({..._json('test/fixtures/index.json'), 'holidays': ['2026-11-04']});
    expect(campusLessons(DateTime.utc(2026, 11, 4), withHoliday, schedules), isEmpty);
    expect(campusLessons(DateTime.utc(2026, 8, 31), index, schedules), isEmpty);
  });

  test('общая лекция — одна запись на несколько групп', () {
    // В среду 13:00 (3 пара) в 2-05 лекция «Технологическое предпринимательство» у обеих групп БИ-25
    final lecture = lessons.where((l) => l.pair == 3 && l.room == '2-05' && l.subject == 'Технологическое предпринимательство');
    expect(lecture, hasLength(1));
    expect(lecture.single.groups, containsAll(['1 БИ-25', '2 БИ-25']));
  });

  group('Преподаватели', () {
    final names = teacherNames(schedules);

    test('Батаева П.С. — одно имя, а не два (с точкой и без)', () {
      expect(names.where((n) => n.startsWith('Батаева П')).toList(), ['Батаева П.С.']);
    });
    test('список по алфавиту, без пустых', () {
      expect(names, isNotEmpty);
      expect(names, orderedEquals([...names]..sort()));
    });
    test('занятия преподавателя находятся при любом написании', () {
      final a = lessonsOfTeacher('Халиев М.С-У.', lessons);
      final b = lessonsOfTeacher('Халиев М.С', lessons);
      expect(a, isNotEmpty);
      expect(a.length, b.length);
      expect(a.every((l) => l.teacher!.startsWith('Халиев')), isTrue);
    });
  });

  group('Полные ФИО преподавателей', () {
    const directory = [
      'Чураев Ибрагим Лечаевич',
      'Халиев Магомед Сайд-Усманович',
      'Юсупова Элина Ахмадовна', // в расписании такой нет
      'Юсупова Малика Доккаевна',
    ];
    final names = teacherNames(schedules, directory: directory);

    test('короткая запись заменяется полным ФИО', () {
      expect(names, contains('Чураев Ибрагим Лечаевич'));
      expect(names, isNot(contains('Чураев И.Л.')));
      expect(names, contains('Халиев Магомед Сайд-Усманович'));
    });
    test('однофамилицы не путаются: Юсупова М.Д. — это Малика, а не Элина', () {
      expect(teacherFullName('Юсупова М.Д.', directory), 'Юсупова Малика Доккаевна');
      expect(sameTeacher('Юсупова М.Д.', 'Юсупова Элина Ахмадовна'), isFalse);
    });
    test('преподаватель из справочника без пар в расписании тоже находится', () {
      expect(names, contains('Юсупова Элина Ахмадовна'));
    });
    test('занятия находятся и по полному ФИО', () {
      final byFull = lessonsOfTeacher('Халиев Магомед Сайд-Усманович', lessons);
      expect(byFull.length, lessonsOfTeacher('Халиев М.С-У.', lessons).length);
      expect(byFull, isNotEmpty);
    });
    test('без справочника всё работает как раньше', () {
      expect(teacherFullName('Лабазанов И.Л.', const []), 'Лабазанов И.Л.');
    });
  });

  group('Аудитории', () {
    final rooms = allRooms(schedules);

    test('в списке только настоящие номера', () {
      expect(rooms, contains('2-05'));
      expect(rooms, contains('3-01'));
      expect(rooms.any((r) => r.contains('корпус') || r.contains('зал')), isFalse);
    });

    test('кто занимается в 2-15 в среду 7 октября: 14:40 «ЧТК и этика» у 1 БИ-25', () {
      final inRoom = lessonsInRoom('2-15', lessons).where((l) => l.pair == 4);
      expect(inRoom.map((l) => l.subject), contains('ЧТК и этика'));
    });

    test('свободные аудитории: занятая не попадает в список, свободная попадает', () {
      final free = freeRooms(4, lessons, rooms);
      expect(free, isNot(contains('2-15')));
      expect(free.length, lessThan(rooms.length));
      // Любая аудитория, занятая в 4 пару, исключена
      final busy = lessons.where((l) => l.pair == 4 && l.room != null).map((l) => l.room!).toSet();
      expect(free.toSet().intersection(busy), isEmpty);
      expect(free.toSet().union(busy.intersection(rooms.toSet())), rooms.toSet());
    });
  });

  group('Группы', () {
    final bi25 = schedules.firstWhere((s) => s.title == '1 БИ-25');
    final monday = DateTime.utc(2026, 10, 5); // 2 неделя

    test('название находится при любом написании', () {
      for (final q in ['би25', '1 би 25', '1 БИ-25', 'Би-25', ' 1би-25 ']) {
        expect(groupMatches('1 БИ-25', q), isTrue, reason: q);
      }
      expect(groupMatches('1 ИТиСС-25', 'итиcc25'), isTrue); // «c» латинская
      expect(groupMatches('ОЗ-1 ИТиСС-26', 'оз1'), isTrue);
      expect(groupMatches('1 БИ-25', 'пи25'), isFalse);
      expect(groupMatches('1 БИ-25', ''), isFalse);
      expect(groupMatches('1 БИ-25', ' - '), isFalse);
    });

    test('по запросу «би25» находятся обе группы БИ-25', () {
      final titles = [for (final f in index.forms) for (final g in f.groups) g.title];
      expect(titles.where((t) => groupMatches(t, 'би25')), containsAll(['1 БИ-25', '2 БИ-25']));
    });

    test('все названия групп разные', () {
      final titles = [for (final f in index.forms) for (final g in f.groups) g.title];
      expect(titles.toSet(), hasLength(titles.length));
    });

    test('общая лекция помечена «вместе с …»', () {
      final lesson = bi25.lessons.firstWhere((l) => l.weekday == 3 && l.pair == 3);
      final joint = GroupSchedule(
        version: bi25.version,
        groupId: bi25.groupId,
        title: bi25.title,
        form: bi25.form,
        subgroups: bi25.subgroups,
        lessons: [
          Lesson(
            weekday: lesson.weekday, pair: lesson.pair, week: lesson.week, subgroups: lesson.subgroups, kind: lesson.kind,
            subject: lesson.subject, teacher: lesson.teacher, room: lesson.room, tags: lesson.tags, raw: lesson.raw,
            withGroups: const ['2 БИ-25'],
          ),
        ],
      );
      expect(groupLessons(wednesday, index, joint).single.note, 'вместе с 2 БИ-25');
    });

    test('среда 7 октября: лекция, практика 2 недели есть, кураторский час 1 недели нет', () {
      final day = groupLessons(wednesday, index, bi25);
      final lecture = day.singleWhere((l) => l.subject == 'Технологическое предпринимательство');
      expect(lecture.pair, 3);
      expect(lecture.room, '2-05');
      expect(day.map((l) => l.subject), contains('ЧТК и этика'));
      expect(day.map((l) => l.subject), isNot(contains('Кураторский час')));
      expect(day.map((l) => l.pair), orderedEquals([...day.map((l) => l.pair)]..sort()));
    });

    test('обе подгруппы: пары одной подгруппы помечены «п/г N»', () {
      final both = groupLessons(monday, index, bi25);
      expect(both, hasLength(6));
      final english = both.where((l) => l.subject == 'Иностранный язык').toList();
      expect(english.map((l) => l.note), unorderedEquals(['п/г 1', 'п/г 2']));
      final shared = both.firstWhere((l) => l.subject == 'Философия');
      expect(shared.note, isNull); // у всей группы пометки нет
    });

    test('одна подгруппа: чужих пар нет и пометок «п/г» нет', () {
      final first = groupLessons(monday, index, bi25, subgroup: 1);
      final second = groupLessons(monday, index, bi25, subgroup: 2);
      expect(first.any((l) => l.note?.contains('п/г') ?? false), isFalse);
      expect([for (final l in first) (l.pair, l.subject)], [
        (1, 'Философия'), (2, 'Философия'), (3, 'Иностранный язык'), (4, 'Технологии бизнес-коммуникаций'),
      ]);
      expect([for (final l in second) (l.pair, l.subject)], [
        (1, 'Философия'), (2, 'Философия'), (3, 'Технологии бизнес-коммуникаций'), (4, 'Иностранный язык'),
      ]);
    });

    test('воскресенье и вне семестра — пусто', () {
      expect(groupLessons(DateTime.utc(2026, 10, 11), index, bi25), isEmpty);
      expect(groupLessons(DateTime.utc(2027, 1, 15), index, bi25), isEmpty);
    });

    test('физ-ра: у групп с делением на юношей и девушек пары помечены', () {
      final friday = groupLessons(DateTime.utc(2026, 10, 9), index, bi25);
      final pe = friday.where((l) => l.subject.startsWith('Физическая культура'));
      expect(pe, isNotEmpty);
      expect(pe.every((l) => l.note?.contains('девушки') ?? false), isTrue);
    });
  });
}
