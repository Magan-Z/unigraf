// Аттестация, зачёт, экзамен: объявляются старостой для группы (или студентом у себя) на конкретное занятие.
// Это обычная правка «заменить» с типом занятия: пара остаётся на месте (предмет, преподаватель, аудитория), но подписана иначе.

import 'schedule_resolver.dart';
import 'models.dart';

/// Виды, которые можно объявить.
const announceKinds = [LessonKind.attestation, LessonKind.credit, LessonKind.exam];

/// Ближайшие занятия того же предмета и того же типа после [from] (по расписанию с уже внесёнными правками).
/// Нужны, чтобы объявить аттестацию «на следующую лекцию» одним касанием, не листая календарь.
List<ResolvedLesson> sameLessonsAhead({
  required ResolvedLesson from,
  required ScheduleIndex index,
  required GroupSchedule schedule,
  required UserProfile profile,
  List<Override> overrides = const [],
  int? forcedWeek,
  int count = 4,
}) {
  // у уже объявленной аттестации «следующего такого же занятия» нет: её можно только поменять на другой вид
  if (from.kind.isAssessment) return const [];
  final result = <ResolvedLesson>[];
  var day = from.date.add(const Duration(days: 1));
  // до конца семестра, но не дальше 20 недель
  final last = from.date.add(const Duration(days: 140));
  while (result.length < count && !day.isAfter(index.semesterEnd) && !day.isAfter(last)) {
    for (final l in resolve(day, index, schedule, profile, overrides: overrides, forcedWeek: forcedWeek)) {
      if (l.subject == from.subject && l.kind == from.kind && result.length < count) result.add(l);
    }
    day = day.add(const Duration(days: 1));
  }
  return result;
}

/// Текст заметки у объявленного занятия. Название вида пишется всегда: старые версии приложения,
/// которые не знают про аттестации, покажут его как обычную заметку.
String assessmentNote(LessonKind kind, String typed) {
  final t = typed.trim();
  return t.isEmpty ? kind.title : '${kind.title}: $t';
}

/// Заметка для показа: у аттестации название уже написано на метке, повторять его не нужно.
String? visibleNote(LessonKind kind, String? note) {
  if (note == null || !kind.isAssessment) return note;
  if (note == kind.title) return null;
  final prefix = '${kind.title}: ';
  return note.startsWith(prefix) ? note.substring(prefix.length) : note;
}
