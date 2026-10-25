// Правки старосты: перенос пары (две связанные правки), мгновенные изменения кэша и подсказки при добавлении пары.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unigraf/domain/group_shared.dart';
import 'package:unigraf/domain/models.dart';
import 'package:unigraf/domain/pair_suggestions.dart';
import 'package:unigraf/domain/schedule_resolver.dart';
import 'package:unigraf/domain/week_view.dart';

GroupOverrideRow _row(
  String id, {
  OverrideType type = OverrideType.cancel,
  String date = '2026-10-07',
  int pair = 4,
  String? subject,
  String? note,
  bool repeat = false,
  String? matchSubject,
  DateTime? at,
}) =>
    GroupOverrideRow(
      id: id,
      baseHash: 'h',
      date: parseDay(date),
      pair: pair,
      type: type,
      subject: subject,
      note: note,
      repeatWeekly: repeat,
      matchSubject: matchSubject,
      updatedAt: at,
    );

GroupSharedState _state(List<GroupOverrideRow> rows) => GroupSharedState(overrides: {for (final r in rows) r.id: r});

void main() {
  group('Перенос пары у старосты: отмена и новое место убираются вместе', () {
    test('с меткой в отмене: убрать новое место — уходит и отмена, и наоборот', () {
      final cancel = _row('c', note: moveMark(parseDay('2026-10-07'), 5));
      final added = _row('a', type: OverrideType.add, pair: 5, subject: 'ЧТК и этика', note: movedNote);
      final other = _row('x', pair: 2); // чужая отмена другой пары
      final state = _state([cancel, added, other]);

      expect(state.withMovePartner(added).map((o) => o.id).toSet(), {'a', 'c'});
      expect(state.withMovePartner(cancel).map((o) => o.id).toSet(), {'a', 'c'});
      expect(state.withMovePartner(other).map((o) => o.id), ['x']);
    });

    test('метка указывает на конкретное место: чужой перенос не задевается', () {
      final c1 = _row('c1', note: moveMark(parseDay('2026-10-07'), 5));
      final a1 = _row('a1', type: OverrideType.add, pair: 5, note: movedNote);
      final c2 = _row('c2', pair: 1, note: moveMark(parseDay('2026-10-08'), 3));
      final a2 = _row('a2', type: OverrideType.add, date: '2026-10-08', pair: 3, note: movedNote);
      final state = _state([c1, a1, c2, a2]);

      expect(state.withMovePartner(a2).map((o) => o.id).toSet(), {'a2', 'c2'});
    });

    test('перенос старой версии (без метки): отмена находится по времени и не путается с другими', () {
      final t = DateTime.utc(2026, 10, 9, 12, 0, 0);
      final early = _row('old', pair: 1, at: t.subtract(const Duration(minutes: 30))); // давняя отмена другой пары
      final cancel = _row('c', at: t.add(const Duration(seconds: 2)));
      final added = _row('a', type: OverrideType.add, pair: 5, note: movedNote, at: t.add(const Duration(seconds: 4)));
      final state = _state([early, cancel, added]);

      expect(state.withMovePartner(added).map((o) => o.id).toSet(), {'a', 'c'});
    });

    test('перенос «каждую неделю» без метки: парная отмена — с тем же названием', () {
      final t = DateTime.utc(2026, 10, 9, 12);
      final mine = _row('mine', repeat: true, matchSubject: 'ЧТК и этика', at: t);
      final foreign = _row('foreign', repeat: true, matchSubject: 'Философия', at: t.add(const Duration(seconds: 1)));
      final added = _row('a', type: OverrideType.add, pair: 5, subject: 'ЧТК и этика', note: movedNote, repeat: true, at: t.add(const Duration(seconds: 2)));

      expect(_state([mine, foreign, added]).withMovePartner(added).map((o) => o.id).toSet(), {'a', 'mine'});
    });

    test('обычная своя пара без пометки «перенесено» уходит одна', () {
      final added = _row('a', type: OverrideType.add, pair: 5, subject: 'Консультация');
      final cancel = _row('c');
      expect(_state([added, cancel]).withMovePartner(added).map((o) => o.id), ['a']);
    });

    test('слишком давняя отмена не считается парой', () {
      final t = DateTime.utc(2026, 10, 9, 12);
      final cancel = _row('c', at: t.subtract(const Duration(minutes: 10)));
      final added = _row('a', type: OverrideType.add, pair: 5, note: movedNote, at: t);
      expect(_state([cancel, added]).withMovePartner(added).map((o) => o.id), ['a']);
    });
  });

  group('Новая правка старосты заменяет только свою пару', () {
    Override announce(String subject, {int pair = 2, String date = '2026-10-26'}) => Override(
          date: parseDay(date),
          pair: pair,
          type: OverrideType.replace,
          kind: LessonKind.attestation,
          matchSubject: subject,
          fromGroup: true,
        );

    test('аттестация второй подгруппы в то же время не стирает аттестацию первой', () {
      final first = _row('first', type: OverrideType.replace, date: '2026-10-26', pair: 2, matchSubject: 'Математика');
      final state = _state([first]);

      expect(state.overridesReplacedBy(announce('Английский')), isEmpty);
    });

    test('повторное объявление по тому же предмету заменяет прежнее', () {
      final first = _row('first', type: OverrideType.replace, date: '2026-10-26', pair: 2, matchSubject: 'Математика');
      expect(_state([first]).overridesReplacedBy(announce('Математика')).map((o) => o.id), ['first']);
    });

    test('в разное время правки друг друга не задевают', () {
      final first = _row('first', type: OverrideType.replace, date: '2026-10-26', pair: 2, matchSubject: 'Математика');
      final state = _state([first]);

      expect(state.overridesReplacedBy(announce('Английский', pair: 3)), isEmpty);
      expect(state.overridesReplacedBy(announce('Математика', date: '2026-10-27')), isEmpty);
    });

    test('правка на всю пару (без названия) по-прежнему заменяется и заменяет', () {
      final whole = _row('whole', date: '2026-10-26', pair: 2); // отмена пары для всех
      final named = _row('named', type: OverrideType.replace, date: '2026-10-26', pair: 2, matchSubject: 'Математика');

      expect(_state([whole]).overridesReplacedBy(announce('Математика')).map((o) => o.id), ['whole']);
      final cancelAll = Override(date: parseDay('2026-10-26'), pair: 2, type: OverrideType.cancel, fromGroup: true);
      expect(_state([named]).overridesReplacedBy(cancelAll).map((o) => o.id), ['named']);
    });

    test('своя пара «add» заменяет только свои пары, а не отмены и замены', () {
      final named = _row('named', type: OverrideType.replace, date: '2026-10-26', pair: 2, matchSubject: 'Математика');
      final added = _row('added', type: OverrideType.add, date: '2026-10-26', pair: 2, subject: 'Консультация');
      final add = Override(date: parseDay('2026-10-26'), pair: 2, type: OverrideType.add, subject: 'Экзамен', fromGroup: true);

      expect(_state([named, added]).overridesReplacedBy(add).map((o) => o.id), ['added']);
    });
  });

  group('Подгруппы: правка старосты видна только своей подгруппе', () {
    Map<String, dynamic> fixture(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;
    final index = ScheduleIndex.fromJson(fixture('index.json'));
    final schedule = GroupSchedule.fromJson(fixture('ofo-1-bi-25.json'));
    const first = UserProfile(formCode: 'ofo', groupId: 'ofo-1-bi-25', subgroup: 1, pe: PeChoice.male);
    const second = UserProfile(formCode: 'ofo', groupId: 'ofo-1-bi-25', subgroup: 2, pe: PeChoice.male);
    final monday = DateTime.utc(2026, 10, 26); // 3 пара: у 1-й подгруппы иностранный язык, у 2-й технологии бизнес-коммуникаций

    List<ResolvedLesson> day(UserProfile p, List<Override> o) => resolve(monday, index, schedule, p, overrides: o);
    Override announce(String subject, {LessonKind kind = LessonKind.attestation}) =>
        Override(date: monday, pair: 3, type: OverrideType.replace, kind: kind, matchSubject: subject, fromGroup: true);

    test('аттестации двух подгрупп в одно время живут вместе: каждая видна своей подгруппе', () {
      final both = [announce('Иностранный язык'), announce('Технологии бизнес-коммуникаций', kind: LessonKind.credit)];

      final a = day(first, both).singleWhere((l) => l.pair == 3);
      final b = day(second, both).singleWhere((l) => l.pair == 3);
      expect((a.subject, a.kind), ('Иностранный язык', LessonKind.attestation));
      expect((b.subject, b.kind), ('Технологии бизнес-коммуникаций', LessonKind.credit));
    });

    test('отмена «для подгруппы» не трогает пару другой подгруппы, отмена «для всей группы» убирает обе', () {
      final mine = Override(date: monday, pair: 3, type: OverrideType.cancel, matchSubject: 'Иностранный язык', fromGroup: true);
      expect(day(first, [mine]).where((l) => l.pair == 3), isEmpty);
      expect(day(second, [mine]).where((l) => l.pair == 3), hasLength(1));

      final all = Override(date: monday, pair: 3, type: OverrideType.cancel, fromGroup: true);
      expect(day(first, [all]).where((l) => l.pair == 3), isEmpty);
      expect(day(second, [all]).where((l) => l.pair == 3), isEmpty);
    });

    test('перенесённая пара подгруппы появляется только у неё, пара «для всей группы» — у обеих', () {
      // иностранный язык 1-й подгруппы с 3 пары перенесли на 5; у 2-й подгруппы иностранный язык в другое время (4 пара)
      final cancel = Override(date: monday, pair: 3, type: OverrideType.cancel, matchSubject: 'Иностранный язык', note: moveMark(monday, 5), fromGroup: true);
      Override added(String? match) =>
          Override(date: monday, pair: 5, type: OverrideType.add, subject: 'Иностранный язык', note: movedNote, matchSubject: match, fromGroup: true);

      expect(day(first, [cancel, added('Иностранный язык')]).where((l) => l.pair == 5), hasLength(1));
      expect(day(second, [cancel, added('Иностранный язык')]).where((l) => l.pair == 5), isEmpty);
      expect(day(second, [cancel, added('Иностранный язык')]).where((l) => l.pair == 4), hasLength(1)); // своя пара у второй подгруппы на месте
      expect(day(first, [added(null)]).where((l) => l.pair == 5), hasLength(1));
      expect(day(second, [added(null)]).where((l) => l.pair == 5), hasLength(1));
    });

    test('кому адресована правка: пара своей подгруппы, пара другой подгруппы, общая пара, без названия', () {
      EditAudience of(String? subject, UserProfile p, {int pair = 3}) =>
          audienceOf(Override(date: monday, pair: pair, type: OverrideType.cancel, matchSubject: subject, fromGroup: true), schedule, p);

      expect(of('Иностранный язык', first), EditAudience.mine);
      expect(of('Иностранный язык', second), EditAudience.other);
      expect(of('Технологии бизнес-коммуникаций', first), EditAudience.other);
      expect(of('Технологии бизнес-коммуникаций', second), EditAudience.mine);
      expect(of('Философия', first, pair: 1), EditAudience.group); // ведётся у всей группы
      expect(of(null, first), EditAudience.group);
    });

    test('два переноса в одно место от разных подгрупп: убрать один не убирает другой', () {
      final mark = moveMark(parseDay('2026-10-26'), 5);
      final cancelA = _row('ca', date: '2026-10-26', pair: 3, matchSubject: 'Иностранный язык', note: mark);
      final addA = _row('aa', type: OverrideType.add, date: '2026-10-26', pair: 5, subject: 'Иностранный язык', matchSubject: 'Иностранный язык', note: movedNote);
      final cancelB = _row('cb', date: '2026-10-26', pair: 3, matchSubject: 'Технологии бизнес-коммуникаций', note: mark);
      final addB = _row('ab', type: OverrideType.add, date: '2026-10-26', pair: 5, subject: 'Технологии бизнес-коммуникаций', matchSubject: 'Технологии бизнес-коммуникаций', note: movedNote);
      final state = _state([cancelA, addA, cancelB, addB]);

      expect(state.withMovePartner(addA).map((o) => o.id).toSet(), {'aa', 'ca'});
      expect(state.withMovePartner(addB).map((o) => o.id).toSet(), {'ab', 'cb'});
      expect(state.withMovePartner(cancelB).map((o) => o.id).toSet(), {'cb', 'ab'});
    });
  });

  group('Мгновенные изменения кэша', () {
    test('ДЗ убирается и возвращается; остальное не трогается', () {
      final hw = GroupHomeworkRow(id: 'h', subject: 'Философия', text: 'Читать', dueDate: DateTime.utc(2026, 10, 14));
      final base = GroupSharedState(homework: {'h': hw}, overrides: {'o': _row('o')}, since: 't1');
      final removed = base.withoutHomework('h');
      expect(removed.homework, isEmpty);
      expect(removed.overrides.keys, ['o']);
      expect(removed.since, 't1');
      expect(removed.withHomework(hw).homework.keys, ['h']);
    });

    test('правки убираются пачкой и добавляются', () {
      final base = _state([_row('a'), _row('b', pair: 2), _row('c', pair: 3)]);
      expect(base.withoutOverrides(['a', 'c']).overrides.keys, ['b']);
      expect(base.withOverrides([_row('d', pair: 1)]).overrides.keys.toSet(), {'a', 'b', 'c', 'd'});
    });
  });

  group('Подсказки при добавлении пары', () {
    GroupSchedule schedule(String name) =>
        GroupSchedule.fromJson(jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>);

    test('из расписания группы: предметы, аудитории, преподаватели, без повторов', () {
      final own = schedule('ofo-1-bi-25');
      final s = PairSuggestions.build(own: own);
      expect(s.subjects, containsAll(['ЧТК и этика', 'Философия']));
      expect(s.subjects.toSet().length, s.subjects.length);
      expect(s.rooms, isNotEmpty);
      expect(s.rooms.toSet().length, s.rooms.length);
      expect(s.teachers, isNotEmpty);
    });

    test('чужие аудитории и преподаватели института идут после своих; полное ФИО берётся из справочника', () {
      final own = schedule('ofo-1-bi-25');
      final others = [own, schedule('all/ofo-1-bi-24'), schedule('all/ofo-1-bi-23')];
      final ownOnly = PairSuggestions.build(own: own);
      final all = PairSuggestions.build(own: own, others: others);
      expect(all.rooms.take(ownOnly.rooms.length), ownOnly.rooms); // свои аудитории первыми
      expect(all.teachers.length, greaterThanOrEqualTo(ownOnly.teachers.length));
      expect(all.teachers.take(ownOnly.teachers.length), ownOnly.teachers);

      final someone = own.lessons.firstWhere((l) => l.teacher != null).teacher!;
      final surname = someone.split(' ').first;
      final withDirectory = PairSuggestions.build(own: own, directory: ['$surname Полное Отчество']);
      expect(withDirectory.teachers.any((t) => t.contains('Полное Отчество')), isTrue);
    });

    test('показ: по набранному тексту, без регистра, без точного совпадения, не больше шести', () {
      const options = ['Философия', 'Физика', 'Иностранный язык', 'ЧТК и этика', 'Физкультура', 'Фитнес', 'Фиксация', 'Финансы'];
      expect(PairSuggestions.matching(options, 'фи'), ['Философия', 'Физика', 'Физкультура', 'Фитнес', 'Фиксация', 'Финансы']);
      expect(PairSuggestions.matching(options, 'ФИЗИК'), ['Физика']);
      expect(PairSuggestions.matching(options, 'физика'), isEmpty); // уже введено полностью
      expect(PairSuggestions.matching(options, 'язык'), ['Иностранный язык']); // совпадение в середине слова
      expect(PairSuggestions.matching(options, ''), hasLength(6)); // пустое поле: самые частые
      expect(PairSuggestions.matching(options, 'яблоко'), isEmpty);
    });
  });
}
