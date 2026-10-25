// Занятия вне семестра: расписание кончилось, но то, что добавлено на конкретную дату (экзамен, зачёт), видно.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unigraf/domain/models.dart';
import 'package:unigraf/domain/schedule_resolver.dart';

void main() {
  final index = ScheduleIndex.fromJson(jsonDecode(File('test/fixtures/index.json').readAsStringSync()) as Map<String, dynamic>);
  final schedule = GroupSchedule.fromJson(jsonDecode(File('test/fixtures/ofo-1-bi-25.json').readAsStringSync()) as Map<String, dynamic>);
  const profile = UserProfile(formCode: 'ofo', groupId: 'ofo-1-bi-25', subgroup: 1, pe: PeChoice.male);

  Override exam(String date, {bool group = true, bool repeat = false, OverrideType type = OverrideType.add}) => Override(
        date: parseDay(date),
        pair: 2,
        type: type,
        subject: 'Философия',
        kind: LessonKind.exam,
        repeatWeekly: repeat,
        fromGroup: group,
      );

  test('после конца семестра пар по расписанию нет', () {
    expect(index.semesterEnd, parseDay('2026-12-26'));
    for (final d in ['2026-12-28', '2027-01-12', '2027-01-15']) {
      expect(resolve(parseDay(d), index, schedule, profile), isEmpty, reason: d);
    }
  });

  test('экзамен, добавленный на конкретную дату после семестра, виден', () {
    final r = resolve(parseDay('2027-01-13'), index, schedule, profile, overrides: [exam('2027-01-13')]);
    expect(r.map((l) => l.subject), ['Философия']);
    expect(r.single.kind, LessonKind.exam);
    expect(r.single.isGroup, isTrue);
    // личная правка студента тоже видна, но помечена личной
    final mine = resolve(parseDay('2027-01-13'), index, schedule, profile, overrides: [exam('2027-01-13', group: false)]);
    expect(mine.single.isPersonal, isTrue);
  });

  test('«каждую неделю» за пределы семестра не уходит, чужие дни не затронуты, воскресенье пусто', () {
    final weekly = exam('2026-12-14', repeat: true); // понедельник внутри семестра
    expect(resolve(parseDay('2027-01-11'), index, schedule, profile, overrides: [weekly]), isEmpty);
    expect(resolve(parseDay('2027-01-14'), index, schedule, profile, overrides: [exam('2027-01-13')]), isEmpty);
    expect(resolve(parseDay('2027-01-17'), index, schedule, profile, overrides: [exam('2027-01-17')]), isEmpty); // воскресенье
  });

  test('отмена и замена вне семестра ничего не создают', () {
    expect(resolve(parseDay('2027-01-13'), index, schedule, profile, overrides: [exam('2027-01-13', type: OverrideType.replace)]), isEmpty);
    expect(resolve(parseDay('2027-01-13'), index, schedule, profile, overrides: [exam('2027-01-13', type: OverrideType.cancel)]), isEmpty);
  });
}
