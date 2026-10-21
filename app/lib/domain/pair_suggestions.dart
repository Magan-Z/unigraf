// Подсказки при добавлении и изменении пары: названия предметов, аудитории и преподаватели из расписания.
// Сначала то, что есть в расписании своей группы (самое частое выше), потом остальные аудитории и преподаватели института.

import 'models.dart';
import 'search.dart';

class PairSuggestions {
  const PairSuggestions({this.subjects = const [], this.rooms = const [], this.teachers = const []});

  final List<String> subjects;
  final List<String> rooms;
  final List<String> teachers;

  static const empty = PairSuggestions();

  /// [own] — расписание своей группы, [others] — расписания всех групп (если уже загружены), [directory] — полные ФИО преподавателей.
  factory PairSuggestions.build({required GroupSchedule own, Iterable<GroupSchedule> others = const [], List<String> directory = const []}) {
    final subjects = _byFrequency([for (final l in own.lessons) l.subject]);

    final ownRooms = _byFrequency([for (final l in own.lessons) if (l.room != null) l.room!]);
    final rooms = [...ownRooms, for (final r in allRooms(others)) if (!ownRooms.contains(r)) r];

    // Один преподаватель бывает записан по-разному («Батаева П.С», «Батаева П.С.»): берём самое полное написание
    final longest = <String, String>{};
    final count = <String, int>{};
    for (final l in own.lessons) {
      final name = l.teacher;
      if (name == null) continue;
      final key = teacherKey(name);
      count[key] = (count[key] ?? 0) + 1;
      if (name.length > (longest[key]?.length ?? 0)) longest[key] = name;
    }
    final keys = count.keys.toList()..sort((a, b) => count[b]! != count[a]! ? count[b]!.compareTo(count[a]!) : a.compareTo(b));
    final ownTeachers = [for (final k in keys) teacherFullName(longest[k]!, directory)];
    final teachers = [
      ...ownTeachers,
      for (final t in teacherNames(others, directory: directory)) if (!ownTeachers.any((o) => sameTeacher(o, t))) t,
    ];

    return PairSuggestions(subjects: subjects, rooms: rooms, teachers: teachers);
  }

  /// Что показать под полем, в которое введено [query]: подходящие варианты (без точного совпадения), не больше [limit].
  /// Пустое поле — самые частые варианты.
  static List<String> matching(List<String> options, String query, {int limit = 6}) {
    final q = query.trim().toLowerCase();
    final result = <String>[];
    for (final o in options) {
      final lower = o.toLowerCase();
      if (lower == q || (q.isNotEmpty && !lower.contains(q))) continue;
      result.add(o);
      if (result.length == limit) break;
    }
    return result;
  }
}

/// Самые частые значения выше, при равенстве — по алфавиту.
List<String> _byFrequency(Iterable<String> values) {
  final count = <String, int>{};
  for (final v in values) {
    count[v] = (count[v] ?? 0) + 1;
  }
  return count.keys.toList()..sort((a, b) => count[b]! != count[a]! ? count[b]!.compareTo(count[a]!) : a.compareTo(b));
}
