// Поиск по всему институту (АРХИТЕКТУРА.md, §8): преподаватель, аудитория, свободные аудитории.
// Работает по файлам всех групп, поэтому не зависит от выбранной вами группы.

import '../core/week.dart';
import 'models.dart';

/// Занятие «глазами института»: одна пара в одной аудитории; общая лекция — одна запись на несколько групп.
class CampusLesson {
  const CampusLesson({
    required this.pair,
    required this.subject,
    required this.teacher,
    required this.room,
    required this.kind,
    required this.groups,
    this.note,
  });

  final int pair;
  final String subject;
  final String? teacher;
  final String? room;
  final LessonKind kind;
  final List<String> groups; // названия групп, у которых это занятие

  /// Пометка вместо списка групп (режим «Группа»): подгруппа, юноши/девушки, «вместе с …».
  final String? note;
}

/// Аудитория в формате «этаж-номер»: 2-05, 3-120, 4-02а. («3 корпус», «читальный зал» — не считаем.)
final _roomPattern = RegExp(r'^\d-\d{2,3}[а-я]?$');

bool isNumberedRoom(String room) => _roomPattern.hasMatch(room);

/// Учебный день и номер недели; null — занятий нет (воскресенье, праздник, вне семестра).
(DateTime, int)? _teachingDay(DateTime date, ScheduleIndex index, int? forcedWeek) {
  final day = dayOnly(date);
  if (day.weekday == DateTime.sunday ||
      index.holidays.contains(day) ||
      day.isBefore(index.semesterStart) ||
      day.isAfter(index.semesterEnd)) {
    return null;
  }
  return (day, forcedWeek ?? weekNumber(day, index.weekAnchor));
}

/// Все занятия института в конкретный день. Общие лекции объединяются в одну запись.
List<CampusLesson> campusLessons(DateTime date, ScheduleIndex index, List<GroupSchedule> schedules, {int? forcedWeek}) {
  final teaching = _teachingDay(date, index, forcedWeek);
  if (teaching == null) return [];
  final (day, week) = teaching;

  // (пара, предмет, преподаватель, аудитория) → группы
  final merged = <String, (Lesson, Set<String>)>{};
  for (final schedule in schedules) {
    for (final lesson in schedule.lessons) {
      if (lesson.weekday != day.weekday) continue;
      if (lesson.week != 0 && lesson.week != week) continue;
      final key = '${lesson.pair}|${lesson.subject}|${lesson.teacher}|${lesson.room}';
      merged.putIfAbsent(key, () => (lesson, <String>{})).$2.add(schedule.title);
    }
  }

  final result = [
    for (final (lesson, groups) in merged.values)
      CampusLesson(
        pair: lesson.pair,
        subject: lesson.subject,
        teacher: lesson.teacher,
        room: lesson.room,
        kind: lesson.kind,
        groups: groups.toList()..sort(),
      ),
  ];
  result.sort((a, b) => a.pair != b.pair ? a.pair.compareTo(b.pair) : a.subject.compareTo(b.subject));
  return result;
}

// ---------- преподаватели ----------

/// Имя разобрано на части: фамилия и первые буквы имени и отчества (строчные).
/// Понимает и «Чураев И.Л.», и «Чураев Ибрагим Лечаевич». Если отчества нет — [second] пустой.
({String surname, String first, String second}) _splitName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  final surname = parts.first.replaceAll('.', '').toLowerCase();
  if (parts.length == 1) return (surname: surname, first: '', second: '');

  // Полное ФИО: «Имя» и «Отчество» — отдельные слова без точек
  if (parts.length >= 3 && !parts[1].contains('.') && parts[1].length > 2) {
    return (surname: surname, first: parts[1][0].toLowerCase(), second: parts[2][0].toLowerCase());
  }
  // Инициалы: «И.Л.», «С-М.», «И.»
  final rest = parts.sublist(1).join('').toLowerCase();
  final dot = rest.indexOf('.');
  return (
    surname: surname,
    first: rest.isEmpty ? '' : rest[0],
    second: dot >= 0 && dot + 1 < rest.length ? rest[dot + 1] : '',
  );
}

/// Один и тот же человек? Фамилия и первая буква имени совпадают; буква отчества сравнивается,
/// только если она есть в обоих написаниях («Алиева М.» подходит и к «Алиева М.В.»).
bool sameTeacher(String a, String b) {
  final x = _splitName(a), y = _splitName(b);
  if (x.surname != y.surname) return false;
  if (x.first.isNotEmpty && y.first.isNotEmpty && x.first != y.first) return false;
  if (x.second.isNotEmpty && y.second.isNotEmpty && x.second != y.second) return false;
  return true;
}

/// Ключ для сравнения имён: в таблице один человек бывает записан по-разному
/// («Батаева П.С», «Батаева П.С.», «Аюбов. С-М.»). Фамилия + буквы имени и отчества.
String teacherKey(String name) {
  final n = _splitName(name);
  return '${n.surname} ${n.first}${n.second}';
}

/// Полное ФИО из справочника [directory] (config.json → teachers) или само имя, если его там нет.
String teacherFullName(String name, List<String> directory) {
  for (final full in directory) {
    if (sameTeacher(name, full)) return full;
  }
  return name;
}

/// Список преподавателей института (по алфавиту). Из нескольких написаний выбирается самое полное;
/// если человек есть в справочнике [directory], показывается его полное ФИО.
/// Преподаватели из справочника, которых нет в расписании, тоже попадают в список — их можно найти по имени.
List<String> teacherNames(Iterable<GroupSchedule> schedules, {List<String> directory = const []}) {
  final best = <String, String>{};
  for (final schedule in schedules) {
    for (final lesson in schedule.lessons) {
      final name = lesson.teacher;
      if (name == null) continue;
      final key = teacherKey(name);
      final current = best[key];
      if (current == null || name.length > current.length) best[key] = name;
    }
  }

  // «Алиева М.» лишняя, если есть «Алиева М.В.»
  final names = best.values.toList();
  final result = <String>{
    for (final name in names)
      if (_splitName(name).second.isNotEmpty ||
          !names.any((o) => o != name && _splitName(o).second.isNotEmpty && sameTeacher(name, o)))
        teacherFullName(name, directory),
    ...directory,
  };
  return result.toList()..sort();
}

/// Занятия преподавателя в день [lessons] (результат [campusLessons]).
List<CampusLesson> lessonsOfTeacher(String teacher, List<CampusLesson> lessons) =>
    [for (final l in lessons) if (l.teacher != null && sameTeacher(teacher, l.teacher!)) l];

// ---------- аудитории ----------

/// Все аудитории института с номером в формате «этаж-номер», по порядку.
List<String> allRooms(Iterable<GroupSchedule> schedules) {
  final rooms = {
    for (final s in schedules)
      for (final l in s.lessons)
        if (l.room != null && isNumberedRoom(l.room!)) l.room!,
  };
  return rooms.toList()..sort();
}

/// Занятия в аудитории [room] в день [lessons].
List<CampusLesson> lessonsInRoom(String room, List<CampusLesson> lessons) =>
    [for (final l in lessons) if (l.room == room) l];

/// Аудитории, где в эту пару никто не занимается. Список «всех аудиторий» — те, что встречаются в расписании.
List<String> freeRooms(int pair, List<CampusLesson> dayLessons, List<String> rooms) {
  final busy = {for (final l in dayLessons) if (l.pair == pair && l.room != null) l.room!};
  return [for (final r in rooms) if (!busy.contains(r)) r];
}

// ---------- группы ----------

/// Двойники русских букв, которые легко набрать латиницей («bи-25», «Bи25»).
const _latinTwins = {
  'a': 'а', 'b': 'в', 'c': 'с', 'e': 'е', 'h': 'н', 'k': 'к', 'm': 'м', 'o': 'о', 'p': 'р', 't': 'т', 'x': 'х', 'y': 'у',
};

/// Название группы для сравнения: без регистра, пробелов, дефисов и точек; «ё» как «е», латинские двойники как русские.
String groupKey(String name) {
  final out = StringBuffer();
  for (final ch in name.toLowerCase().split('')) {
    if (RegExp(r'[\s\-–—.,_]').hasMatch(ch)) continue;
    out.write(_latinTwins[ch] ?? (ch == 'ё' ? 'е' : ch));
  }
  return out.toString();
}

/// Подходит ли [title] («1 БИ-25») под запрос: «би25», «1 би 25», «БИ-2» найдут группу.
bool groupMatches(String title, String query) {
  final q = groupKey(query);
  return q.isNotEmpty && groupKey(title).contains(q);
}

/// Занятия одной группы в день [date] по официальному расписанию (без личных правок и правок старосты).
/// [subgroup] — только эта подгруппа; null — обе, с пометкой «п/г N» там, где занятие не у всей группы.
List<CampusLesson> groupLessons(
  DateTime date,
  ScheduleIndex index,
  GroupSchedule schedule, {
  int? subgroup,
  int? forcedWeek,
}) {
  final teaching = _teachingDay(date, index, forcedWeek);
  if (teaching == null) return [];
  final (day, week) = teaching;
  final subgroupCount = schedule.subgroups.length;

  final result = <CampusLesson>[];
  for (final lesson in schedule.lessons) {
    if (lesson.weekday != day.weekday) continue;
    if (lesson.week != 0 && lesson.week != week) continue;
    if (subgroup != null && !lesson.subgroups.contains(subgroup)) continue;
    final notes = <String>[
      if (subgroup == null && subgroupCount > 1 && lesson.subgroups.length < subgroupCount)
        'п/г ${lesson.subgroups.join(', ')}',
      if (lesson.tags.contains('male')) 'юноши',
      if (lesson.tags.contains('female')) 'девушки',
      if (lesson.withGroups.isNotEmpty) 'вместе с ${lesson.withGroups.join(', ')}',
    ];
    result.add(CampusLesson(
      pair: lesson.pair,
      subject: lesson.subject,
      teacher: lesson.teacher,
      room: lesson.room,
      kind: lesson.kind,
      groups: [schedule.title],
      note: notes.isEmpty ? null : notes.join(' · '),
    ));
  }
  result.sort((a, b) => a.pair != b.pair ? a.pair.compareTo(b.pair) : a.subject.compareTo(b.subject));
  return result;
}
