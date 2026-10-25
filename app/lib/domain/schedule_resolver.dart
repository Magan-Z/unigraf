// ЯДРО приложения: «какие у меня пары в этот день?» (АРХИТЕКТУРА.md, §7.3).
// Чистая функция: не ходит в сеть, не трогает экран и не смотрит на часы —
// всё нужное передаётся параметрами. Поэтому её легко проверять тестами.

import '../core/bells.dart';
import '../core/week.dart';
import 'models.dart';
import 'week_view.dart';

List<ResolvedLesson> resolve(
  DateTime date,
  ScheduleIndex index,
  GroupSchedule schedule,
  UserProfile profile, {
  List<Override> overrides = const [],
  int? forcedWeek, // ручной переключатель недели из настроек (на случай сбоя чередования)
}) {
  final day = dayOnly(date);

  // 1. Воскресенье или праздник — пар нет
  if (day.weekday == DateTime.sunday || index.holidays.contains(day)) return [];

  // Вне семестра (сессия, каникулы) расписания нет, но видны занятия, добавленные на конкретную дату:
  // например, экзамен или зачёт, который объявил староста. Повторы «каждую неделю» за пределы семестра не уходят.
  if (day.isBefore(index.semesterStart) || day.isAfter(index.semesterEnd)) {
    final result = <ResolvedLesson>[];
    final week = forcedWeek ?? weekNumber(day, index.weekAnchor);
    for (final group in [true, false]) {
      final layer = [for (final o in overrides) if (o.fromGroup == group && o.type == OverrideType.add && !o.repeatWeekly) o];
      _applyOverrides(result, layer, day, index, week, group: group, schedule: schedule, profile: profile, all: overrides);
    }
    result.sort((a, b) => a.pair.compareTo(b.pair));
    return result;
  }

  final week = forcedWeek ?? weekNumber(day, index.weekAnchor);
  final result = <ResolvedLesson>[];

  for (final lesson in schedule.lessons) {
    // 2. Нужный день недели и неделя (0 = каждая неделя)
    if (lesson.weekday != day.weekday) continue;
    if (lesson.week != 0 && lesson.week != week) continue;
    // 3–4. Своя подгруппа; физ-ра «чужого» пола убирается
    if (!lessonFitsProfile(lesson, profile)) continue;

    result.add(_toResolved(day, lesson.pair, index.bells, week,
        subject: lesson.subject, teacher: lesson.teacher, room: lesson.room, kind: lesson.kind, tags: lesson.tags, withGroups: lesson.withGroups));
  }

  // 5. Правки: сначала старосты (для всей группы), поверх них — личные.
  _applyOverrides(result, [for (final o in overrides) if (o.fromGroup) o], day, index, week, group: true, schedule: schedule, profile: profile, all: overrides);
  _applyOverrides(result, [for (final o in overrides) if (!o.fromGroup) o], day, index, week, group: false, schedule: schedule, profile: profile, all: overrides);

  // 6. По порядку пар (время уже проставлено в _toResolved)
  result.sort((a, b) => a.pair.compareTo(b.pair));
  return result;
}

/// Применяет один «слой» правок к списку пар дня. Сначала правила «каждую неделю», потом правки на конкретный день —
/// они главнее. Отмены и замены применяются раньше добавлений: перенесённая пара не должна отмениться собственной отменой.
void _applyOverrides(List<ResolvedLesson> result, List<Override> layer, DateTime day, ScheduleIndex index, int week,
    {required bool group, required GroupSchedule schedule, required UserProfile profile, required List<Override> all}) {
  final applicable = layer.where((o) => o.appliesOn(day)).toList()
    ..sort((a, b) => a.repeatWeekly == b.repeatWeekly ? 0 : (a.repeatWeekly ? -1 : 1));
  bool matches(Override o, ResolvedLesson l) => l.pair == o.pair && (o.matchSubject == null || l.subject == o.matchSubject);

  for (final o in applicable.where((o) => o.type != OverrideType.add)) {
    if (o.type == OverrideType.cancel) {
      result.removeWhere((l) => matches(o, l));
    } else {
      for (var i = 0; i < result.length; i++) {
        if (matches(o, result[i])) {
          result[i] = result[i].copyWith(
            subject: o.subject,
            teacher: o.teacher,
            room: o.room,
            note: o.note,
            kind: o.kind, // аттестация, зачёт или экзамен вместо обычного занятия
            isPersonal: group ? null : true,
            isGroup: group ? true : null,
            groupChangedAt: group ? o.changedAt : null,
          );
        }
      }
    }
  }
  for (final o in applicable.where((o) => o.type == OverrideType.add)) {
    // пара, перенесённая старостой для другой подгруппы, у вас не появляется
    if (group && o.matchSubject != null && audienceOf(o, schedule, profile, all: all) == EditAudience.other) continue;
    result.add(_toResolved(day, o.pair, index.bells, week,
        subject: o.subject ?? 'Занятие',
        teacher: o.teacher,
        room: o.room,
        kind: o.kind ?? LessonKind.practice,
        tags: const [],
        note: o.note,
        isPersonal: !group,
        groupChangedAt: group ? o.changedAt : null,
        isGroup: group));
  }
}

ResolvedLesson _toResolved(
  DateTime day,
  int pair,
  List<Bell> bells,
  int week, {
  required String subject,
  required String? teacher,
  required String? room,
  required LessonKind kind,
  required List<String> tags,
  String? note,
  bool isPersonal = false,
  bool isGroup = false,
  List<String> withGroups = const [],
  DateTime? groupChangedAt,
}) {
  final (start, end) = pairTimes(day, pair, bells);
  return ResolvedLesson(
    date: day,
    pair: pair,
    startAt: start,
    endAt: end,
    subject: subject,
    teacher: teacher,
    room: room,
    kind: kind,
    tags: tags,
    week: week,
    note: note,
    isPersonal: isPersonal,
    isGroup: isGroup,
    withGroups: withGroups,
    groupChangedAt: groupChangedAt,
  );
}

/// Ближайший учебный день начиная с [from] (включительно), в который есть пары. Не дальше 14 дней.
DateTime? nextStudyDay(
  DateTime from,
  ScheduleIndex index,
  GroupSchedule schedule,
  UserProfile profile, {
  List<Override> overrides = const [],
  int? forcedWeek,
}) {
  var day = dayOnly(from);
  for (var i = 0; i < 14; i++) {
    if (resolve(day, index, schedule, profile, overrides: overrides, forcedWeek: forcedWeek).isNotEmpty) return day;
    day = day.add(const Duration(days: 1));
  }
  return null;
}
