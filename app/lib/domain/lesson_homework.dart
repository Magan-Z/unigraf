// ДЗ, относящиеся к одной паре: из трёх источников (преподаватель, староста, ваше) собираются по предмету и сроку.
// Тексты не сравниваются и не склеиваются: похожие задания остаются отдельными пунктами, каждый со своей меткой.

import '../core/week.dart';
import 'homework.dart';
import 'models.dart';

/// Подходит ли ДЗ с типом [itemKind] к занятию типа [lessonKind] (null — «любое занятие»).
bool _kindFits(LessonKind? itemKind, LessonKind? lessonKind) => itemKind == null || lessonKind == null || itemKind == lessonKind;

/// ДЗ к паре: тот же предмет, срок на день пары, тип занятия подходит.
/// Сверху преподаватель, потом староста, потом ваше; внутри — по времени создания. Выполненные тоже входят.
List<HomeworkItem> homeworkForLesson(List<HomeworkItem> all, {required String subject, required DateTime day, LessonKind? kind}) {
  final d = dayOnly(day);
  final result = [
    for (final h in all)
      if (h.subject == subject && dayOnly(h.dueDate) == d && _kindFits(h.kind, kind)) h,
  ];
  result.sort((a, b) {
    final bySource = a.source.index.compareTo(b.source.index);
    return bySource != 0 ? bySource : a.createdAt.compareTo(b.createdAt);
  });
  return result;
}

/// Что показать на значке: сколько заданий не сделано и всё ли сделано.
class LessonHomework {
  const LessonHomework(this.items);
  final List<HomeworkItem> items;

  static const none = LessonHomework([]);

  bool get isEmpty => items.isEmpty;
  int get open => items.where((i) => !i.done).length;
  bool get allDone => items.isNotEmpty && open == 0;
}

/// Уже заданное на тот же предмет и срок (для подсказки «староста уже добавила…» при создании нового ДЗ).
/// Выполненные не учитываются: напоминать о них незачем.
List<HomeworkItem> alreadyAssigned(List<HomeworkItem> all, {required String subject, required DateTime due, LessonKind? kind}) =>
    [for (final h in homeworkForLesson(all, subject: subject, day: due, kind: kind)) if (!h.done) h];
