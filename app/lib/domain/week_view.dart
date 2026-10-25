// Расписание «по шаблону недели» — для экрана «Неделя» (без конкретных дат).

import 'group_shared.dart' show moveMark;
import 'models.dart';

/// Подходит ли занятие пользователю: своя подгруппа и нужная физ-ра.
bool lessonFitsProfile(Lesson lesson, UserProfile profile) {
  if (!lesson.subgroups.contains(profile.subgroup)) return false;
  if (profile.pe == PeChoice.male && lesson.tags.contains('female')) return false;
  if (profile.pe == PeChoice.female && lesson.tags.contains('male')) return false;
  return true;
}

/// Пары по дням недели (1–6) для недели [week] (1 или 2).
Map<int, List<Lesson>> weekTemplate(GroupSchedule schedule, UserProfile profile, int week) {
  final result = {for (var d = 1; d <= 6; d++) d: <Lesson>[]};
  for (final lesson in schedule.lessons) {
    if (lesson.week != 0 && lesson.week != week) continue;
    if (!lessonFitsProfile(lesson, profile)) continue;
    result[lesson.weekday]!.add(lesson);
  }
  for (final list in result.values) {
    list.sort((a, b) => a.pair.compareTo(b.pair));
  }
  return result;
}

/// Названия предметов группы (для выбора при добавлении ДЗ), по алфавиту. Без кураторского часа и физ-ры.
List<String> subjectsOf(GroupSchedule schedule, UserProfile profile) {
  final names = {
    for (final l in schedule.lessons)
      if (lessonFitsProfile(l, profile) && l.kind != LessonKind.curator && l.kind != LessonKind.pe) l.subject,
  };
  return names.toList()..sort();
}

/// Делится ли предмет по подгруппам (иностранный язык, лабораторные): хотя бы одно занятие только для части подгрупп.
/// Тогда староста может задать ДЗ одной подгруппе.
bool subjectSplitsBySubgroup(GroupSchedule schedule, String subject) =>
    schedule.subgroups.length > 1 && schedule.lessons.any((l) => l.subject == subject && l.subgroups.length < schedule.subgroups.length);

/// Названия всех предметов в расписании пользователя (в его подгруппе).
Set<String> subjectsOfProfile(GroupSchedule schedule, UserProfile profile) => {
      for (final l in schedule.lessons)
        if (lessonFitsProfile(l, profile)) l.subject,
    };

/// Кому видна правка старосты: всей группе, подгруппе пользователя или другой подгруппе.
enum EditAudience { group, mine, other }

/// Правка с названием предмета действует только на пары с этим названием, то есть адресована подгруппе, у которой эта пара.
/// Смотрим на пару в расписании в это время: если её ведут у всех подгрупп, правка для всей группы, иначе она ваша или чужая.
/// Перенесённая пара (новое место) определяется по своей отмене на старом месте — она в списке [all].
/// Если пары в расписании нет, судим по предмету: ведётся не у всех подгрупп и есть у вас — ваша, иначе чужая.
EditAudience audienceOf(Override o, GroupSchedule schedule, UserProfile profile, {List<Override> all = const []}) {
  final subject = o.matchSubject;
  if (subject == null) return EditAudience.group;
  if (o.type == OverrideType.add) {
    final mark = moveMark(o.date, o.pair);
    for (final c in all) {
      if (c.type == OverrideType.cancel && c.note == mark && c.matchSubject == subject) return audienceOf(c, schedule, profile);
    }
  } else {
    final atSlot = [
      for (final l in schedule.lessons)
        if (l.weekday == o.date.weekday && l.pair == o.pair && l.subject == subject) l,
    ];
    if (atSlot.isNotEmpty) {
      final covered = {for (final l in atSlot) ...l.subgroups};
      if (schedule.subgroups.every((g) => covered.contains(g.n))) return EditAudience.group;
      return atSlot.any((l) => lessonFitsProfile(l, profile)) ? EditAudience.mine : EditAudience.other;
    }
  }
  if (!subjectSplitsBySubgroup(schedule, subject)) return EditAudience.group;
  return subjectsOfProfile(schedule, profile).contains(subject) ? EditAudience.mine : EditAudience.other;
}
