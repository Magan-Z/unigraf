// Правки старосты: перенос пары (две связанные правки), мгновенные изменения кэша и подсказки при добавлении пары.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unigraf/domain/group_shared.dart';
import 'package:unigraf/domain/models.dart';
import 'package:unigraf/domain/pair_suggestions.dart';

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
