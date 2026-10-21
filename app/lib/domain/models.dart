// Модели данных приложения. Формат JSON описан в АРХИТЕКТУРА.md, §5.2–5.3.

/// Тип занятия.
enum LessonKind {
  lecture('Лекция', 'Л'),
  practice('Практика', 'П'),
  pe('Физ-ра', 'Ф'),
  curator('Куратор', 'К'),
  // Объявляются старостой (или вами у себя): аттестация вместо лекции, зачёт, экзамен
  attestation('Аттестация', 'А'),
  credit('Зачёт', 'З'),
  exam('Экзамен', 'Э');

  const LessonKind(this.title, this.letter);
  final String title;
  final String letter;

  /// Аттестация, зачёт или экзамен.
  bool get isAssessment => this == attestation || this == credit || this == exam;

  static LessonKind parse(String value) =>
      LessonKind.values.firstWhere((k) => k.name == value, orElse: () => LessonKind.practice);
}

/// Выбор физ-ры в профиле.
enum PeChoice {
  male('Юноши'),
  female('Девушки'),
  both('Показывать обе');

  const PeChoice(this.title);
  final String title;

  static PeChoice parse(String? value) =>
      PeChoice.values.firstWhere((p) => p.name == value, orElse: () => PeChoice.both);
}

/// Занятие из расписания (одна запись из файла группы).
class Lesson {
  const Lesson({
    required this.weekday,
    required this.pair,
    required this.week,
    required this.subgroups,
    required this.kind,
    required this.subject,
    required this.teacher,
    required this.room,
    required this.tags,
    required this.raw,
    this.withGroups = const [],
  });

  final int weekday; // 1 = понедельник … 6 = суббота
  final int pair; // 1–5
  final int week; // 0 = каждая неделя, 1 или 2
  final List<int> subgroups;
  final LessonKind kind;
  final String subject;
  final String? teacher;
  final String? room;
  final List<String> tags; // male / female
  final String raw;
  final List<String> withGroups; // с какими группами объединена лекция («2 БИ-25»); пусто — только эта группа

  factory Lesson.fromJson(Map<String, dynamic> json) => Lesson(
        weekday: json['weekday'] as int,
        pair: json['pair'] as int,
        week: json['week'] as int,
        subgroups: (json['subgroups'] as List).cast<int>(),
        kind: LessonKind.parse(json['kind'] as String),
        subject: json['subject'] as String,
        teacher: json['teacher'] as String?,
        room: json['room'] as String?,
        tags: (json['tags'] as List).cast<String>(),
        raw: json['raw'] as String,
        withGroups: [for (final g in (json['withGroups'] as List? ?? const [])) g as String],
      );
}

class SubgroupInfo {
  const SubgroupInfo(this.n, this.label);
  final int n;
  final String label;

  factory SubgroupInfo.fromJson(Map<String, dynamic> json) =>
      SubgroupInfo(json['n'] as int, json['label'] as String);
}

/// Группа в списке index.json.
class GroupInfo {
  const GroupInfo({
    required this.id,
    required this.title,
    required this.course,
    required this.subgroups,
    required this.hasGenderedPe,
    required this.hash,
  });

  final String id;
  final String title;
  final int course;
  final List<SubgroupInfo> subgroups;
  final bool hasGenderedPe;
  final String hash;

  factory GroupInfo.fromJson(Map<String, dynamic> json) => GroupInfo(
        id: json['id'] as String,
        title: json['title'] as String,
        course: json['course'] as int,
        subgroups: [for (final s in json['subgroups'] as List) SubgroupInfo.fromJson(s as Map<String, dynamic>)],
        hasGenderedPe: json['hasGenderedPe'] as bool? ?? false,
        hash: json['hash'] as String? ?? '',
      );
}

/// Форма обучения (лист Excel): очная, очно-заочная, магистратура.
class FormInfo {
  const FormInfo({required this.code, required this.title, required this.groups});
  final String code;
  final String title;
  final List<GroupInfo> groups;

  factory FormInfo.fromJson(Map<String, dynamic> json) => FormInfo(
        code: json['code'] as String,
        title: json['title'] as String,
        groups: [for (final g in json['groups'] as List) GroupInfo.fromJson(g as Map<String, dynamic>)],
      );
}

/// Время пары по звонку: часы и минуты начала и конца.
class Bell {
  const Bell(this.startHour, this.startMinute, this.endHour, this.endMinute);
  final int startHour, startMinute, endHour, endMinute;

  /// ["09:00", "10:30"] → Bell
  factory Bell.fromJson(List<dynamic> pair) {
    final start = (pair[0] as String).split(':');
    final end = (pair[1] as String).split(':');
    return Bell(int.parse(start[0]), int.parse(start[1]), int.parse(end[0]), int.parse(end[1]));
  }

  String get startText => '${_two(startHour)}:${_two(startMinute)}';
  String get endText => '${_two(endHour)}:${_two(endMinute)}';
  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// index.json — общий список групп и настройки календаря.
class ScheduleIndex {
  const ScheduleIndex({
    required this.version,
    required this.semesterId,
    required this.semesterStart,
    required this.semesterEnd,
    required this.weekAnchor,
    required this.timezone,
    required this.bells,
    required this.holidays,
    required this.forms,
    this.teachers = const [],
  });

  final String version;
  final String semesterId;
  final DateTime semesterStart; // даты — «только день», в UTC (см. core/week.dart)
  final DateTime semesterEnd;
  final DateTime weekAnchor;
  final String timezone;
  final List<Bell> bells;
  final Set<DateTime> holidays;
  final List<FormInfo> forms;
  final List<String> teachers; // полные ФИО преподавателей (необязательное поле index.json)

  factory ScheduleIndex.fromJson(Map<String, dynamic> json) {
    final semester = json['semester'] as Map<String, dynamic>;
    return ScheduleIndex(
      version: json['version'] as String,
      semesterId: semester['id'] as String,
      semesterStart: parseDay(semester['start'] as String),
      semesterEnd: parseDay(semester['end'] as String),
      weekAnchor: parseDay(json['weekAnchor'] as String),
      timezone: json['timezone'] as String,
      bells: [for (final b in json['bells'] as List) Bell.fromJson(b as List)],
      holidays: {for (final h in json['holidays'] as List) parseDay(h as String)},
      forms: [for (final f in json['forms'] as List) FormInfo.fromJson(f as Map<String, dynamic>)],
      teachers: [for (final t in (json['teachers'] as List? ?? const [])) t as String],
    );
  }

  GroupInfo? findGroup(String id) {
    for (final form in forms) {
      for (final group in form.groups) {
        if (group.id == id) return group;
      }
    }
    return null;
  }
}

/// Файл группы (groups/ID.json) — расписание одной группы.
class GroupSchedule {
  const GroupSchedule({
    required this.version,
    required this.groupId,
    required this.title,
    required this.form,
    required this.subgroups,
    required this.lessons,
  });

  final String version;
  final String groupId;
  final String title;
  final String form;
  final List<SubgroupInfo> subgroups;
  final List<Lesson> lessons;

  factory GroupSchedule.fromJson(Map<String, dynamic> json) {
    final group = json['group'] as Map<String, dynamic>;
    return GroupSchedule(
      version: json['version'] as String,
      groupId: group['id'] as String,
      title: group['title'] as String,
      form: group['form'] as String,
      subgroups: [for (final s in group['subgroups'] as List) SubgroupInfo.fromJson(s as Map<String, dynamic>)],
      lessons: [for (final l in json['lessons'] as List) Lesson.fromJson(l as Map<String, dynamic>)],
    );
  }
}

/// Профиль пользователя: кто он и как ему показывать расписание.
class UserProfile {
  const UserProfile({
    required this.formCode,
    required this.groupId,
    required this.subgroup,
    this.pe = PeChoice.both,
  });

  final String formCode;
  final String groupId;
  final int subgroup;
  final PeChoice pe;

  UserProfile copyWith({String? formCode, String? groupId, int? subgroup, PeChoice? pe}) => UserProfile(
        formCode: formCode ?? this.formCode,
        groupId: groupId ?? this.groupId,
        subgroup: subgroup ?? this.subgroup,
        pe: pe ?? this.pe,
      );
}

/// Тип личной правки расписания.
enum OverrideType { cancel, replace, add }

/// Личная правка на конкретную дату: «пару отменили», «перенесли в другую аудиторию», «добавили пару».
class Override {
  const Override({
    this.id,
    required this.date,
    required this.pair,
    required this.type,
    this.subject,
    this.room,
    this.teacher,
    this.note,
    this.kind,
    this.repeatWeekly = false,
    this.matchSubject,
    this.fromGroup = false,
    this.remoteId,
    this.changedAt,
  });

  final int? id; // null — ещё не сохранено в базу
  final DateTime date; // «только день», UTC
  final int pair;
  final OverrideType type;
  final String? subject;
  final String? room;
  final String? teacher;
  final String? note;

  /// Тип для своей пары (чтобы перенесённая лекция осталась лекцией). null — «практика».
  final LessonKind? kind;

  /// true — правка действует не один день, а каждую неделю: с [date] и далее в тот же день недели.
  final bool repeatWeekly;

  /// Для «каждую неделю»: менять/отменять только пару с таким названием (на этом же номере пары
  /// в другие недели может идти другой предмет).
  final String? matchSubject;

  /// true — это правка старосты для всей группы (приходит с сервера), а не личная.
  final bool fromGroup;

  /// Номер правки на сервере (только для правок старосты).
  final String? remoteId;

  /// Когда староста внёс правку (время сервера, UTC). Только для правок старосты.
  final DateTime? changedAt;

  /// Действует ли правка в этот день.
  bool appliesOn(DateTime day) => date == day || (repeatWeekly && !day.isBefore(date) && day.weekday == date.weekday);

  /// Правка «заменить» поверх прежней правки той же пары: что здесь не задано, берётся из [old].
  /// Так аудитория, преподаватель, заметка и тип (аттестация) не пропадают, когда пару правят второй раз.
  Override mergedOver(Override old) => Override(
        id: id,
        date: date,
        pair: pair,
        type: type,
        subject: subject ?? old.subject,
        room: room ?? old.room,
        teacher: teacher ?? old.teacher,
        note: note ?? old.note,
        kind: kind ?? old.kind,
        repeatWeekly: repeatWeekly,
        matchSubject: matchSubject ?? old.matchSubject,
        fromGroup: fromGroup,
        remoteId: remoteId,
        changedAt: changedAt,
      );
}

/// Занятие на конкретную дату — то, что показывается на экране.
class ResolvedLesson {
  const ResolvedLesson({
    required this.date,
    required this.pair,
    required this.startAt,
    required this.endAt,
    required this.subject,
    required this.teacher,
    required this.room,
    required this.kind,
    required this.tags,
    required this.week,
    this.note,
    this.isPersonal = false,
    this.isGroup = false,
    this.withGroups = const [],
    this.groupChangedAt,
  });

  final DateTime date;
  final int pair;
  final DateTime startAt; // момент времени (UTC внутри), показывать через toLocal()/часовой пояс
  final DateTime endAt;
  final String subject;
  final String? teacher;
  final String? room;
  final LessonKind kind;
  final List<String> tags;
  final int week;
  final String? note;
  final bool isPersonal; // изменено личной правкой
  final bool isGroup; // изменено старостой для всей группы
  final List<String> withGroups; // с какими группами объединена лекция (пусто — только эта группа)
  final DateTime? groupChangedAt; // когда староста изменил эту пару (для подписи «изменено старостой в 14:20»)

  ResolvedLesson copyWith({String? subject, String? teacher, String? room, String? note, LessonKind? kind, bool? isPersonal, bool? isGroup, DateTime? groupChangedAt}) =>
      ResolvedLesson(
        date: date,
        pair: pair,
        startAt: startAt,
        endAt: endAt,
        subject: subject ?? this.subject,
        teacher: teacher ?? this.teacher,
        room: room ?? this.room,
        kind: kind ?? this.kind,
        tags: tags,
        week: week,
        note: note ?? this.note,
        isPersonal: isPersonal ?? this.isPersonal,
        isGroup: isGroup ?? this.isGroup,
        // если пару заменили другим предметом, прежний «поток» к ней уже не относится
        withGroups: subject != null && subject != this.subject ? const [] : withGroups,
        groupChangedAt: groupChangedAt ?? this.groupChangedAt,
      );
}

/// «2026-10-08» → DateTime.utc(2026, 10, 8). Все «даты без времени» храним так.
DateTime parseDay(String text) {
  final parts = text.split('-').map(int.parse).toList();
  return DateTime.utc(parts[0], parts[1], parts[2]);
}

/// «2026-10-07» — день в виде, который понимают сервер и файлы расписания.
String dayText(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
