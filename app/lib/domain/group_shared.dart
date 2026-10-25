// Общие данные группы, которые ведёт староста: правки расписания и ДЗ (приходят с сервера).
// Хранятся у каждого студента в телефоне (чтобы работать без интернета) и обновляются «дельтами»:
// с сервера скачивается только то, что изменилось с прошлого раза.

import 'dart:convert';

import 'attachment.dart';
import 'models.dart';

/// Заметка у пары, перенесённой старостой (показывается студентам).
const movedNote = 'перенесено';

const _moveMarkPrefix = 'moved:';

/// Метка в отмене на старом месте: куда перенесена пара. По ней отмена и новая пара находят друг друга.
String moveMark(DateTime date, int pair) => '$_moveMarkPrefix${dayText(date)}:$pair';

/// Правка расписания, сделанная старостой.
class GroupOverrideRow {
  const GroupOverrideRow({
    required this.id,
    required this.baseHash,
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
    this.updatedAt,
  });

  final String id;

  /// Хеш расписания группы, к которому относится правка. Когда приходит новое расписание, хеш меняется,
  /// и такие правки перестают действовать (новое расписание точнее).
  final String baseHash;
  final DateTime date;
  final int pair;
  final OverrideType type;
  final String? subject;
  final String? room;
  final String? teacher;
  final String? note;
  final LessonKind? kind;
  final bool repeatWeekly;
  final String? matchSubject;

  /// Когда сервер сохранил правку (UTC). У только что созданной на телефоне правки ещё нет.
  final DateTime? updatedAt;

  factory GroupOverrideRow.fromJson(Map<String, dynamic> j) => GroupOverrideRow(
        id: j['id'] as String,
        baseHash: j['base_hash'] as String,
        date: parseDay(j['date'] as String),
        pair: j['pair'] as int,
        type: OverrideType.values.byName(j['type'] as String),
        subject: j['subject'] as String?,
        room: j['room'] as String?,
        teacher: j['teacher'] as String?,
        note: j['note'] as String?,
        kind: j['kind'] == null ? null : LessonKind.parse(j['kind'] as String),
        repeatWeekly: j['repeat_weekly'] as bool? ?? false,
        matchSubject: j['match_subject'] as String?,
        updatedAt: j['updated_at'] == null ? null : DateTime.tryParse(j['updated_at'] as String)?.toUtc(),
      );

  /// В том виде, в каком хранится на сервере (без служебных полей).
  Map<String, dynamic> toJson() => {
        'id': id,
        'base_hash': baseHash,
        'date': dayText(date),
        'pair': pair,
        'type': type.name,
        'subject': subject,
        'room': room,
        'teacher': teacher,
        'note': note,
        'kind': kind?.name,
        'repeat_weekly': repeatWeekly,
        'match_subject': matchSubject,
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(), // для кэша; сервер это поле игнорирует
      };

  Override toOverride() => Override(
        date: date,
        pair: pair,
        type: type,
        subject: subject,
        room: room,
        teacher: teacher,
        note: note,
        kind: kind,
        repeatWeekly: repeatWeekly,
        matchSubject: matchSubject,
        fromGroup: true,
        remoteId: id,
        changedAt: updatedAt,
      );
}

/// Файл или фото, прикреплённое старостой к ДЗ: на сервере лежит содержимое, в ДЗ — только это описание.
class GroupFileRef {
  const GroupFileRef({required this.id, required this.name, required this.size});

  final String id;
  final String name;
  final int size;

  factory GroupFileRef.fromJson(Map<String, dynamic> j) =>
      GroupFileRef(id: j['id'] as String, name: cleanFileName(j['name'] as String), size: (j['size'] as num?)?.toInt() ?? 0);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'size': size};

  /// Для показа: те же значки и «1,4 МБ», что у личных вложений.
  Attachment get asAttachment => Attachment(name: name, path: '', sizeBytes: size);
}

/// ДЗ, которое задал староста для всей группы.
class GroupHomeworkRow {
  const GroupHomeworkRow({
    required this.id,
    required this.subject,
    required this.text,
    required this.dueDate,
    this.kind,
    this.subgroup,
    this.files = const [],
    this.author,
  });

  final String id;
  final String subject;
  final String text;
  final DateTime dueDate; // «только день», UTC
  final LessonKind? kind;

  /// Номер подгруппы, для которой задано ДЗ (иностранный язык и т.п.). null — всей группе.
  final int? subgroup;
  final List<GroupFileRef> files;

  /// Кто задал: имя преподавателя (его проставляет сервер по коду). null — задал староста.
  final String? author;

  /// Видно ли это ДЗ студенту из подгруппы [mine]: общее — всем, подгрупповое — только своей подгруппе.
  bool visibleTo(int mine) => subgroup == null || subgroup == mine;

  factory GroupHomeworkRow.fromJson(Map<String, dynamic> j) => GroupHomeworkRow(
        id: j['id'] as String,
        subject: j['subject'] as String,
        text: j['body'] as String,
        dueDate: parseDay(j['due_date'] as String),
        kind: j['kind'] == null ? null : LessonKind.parse(j['kind'] as String),
        subgroup: (j['subgroup'] as num?)?.toInt(),
        files: [for (final f in (j['files'] as List? ?? const [])) GroupFileRef.fromJson(f as Map<String, dynamic>)],
        author: j['author'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'body': text,
        'due_date': dayText(dueDate),
        'kind': kind?.name,
        'subgroup': subgroup,
        'files': [for (final f in files) f.toJson()],
        if (author != null) 'author': author,
      };
}

/// Всё, что известно телефону об общих данных группы.
class GroupSharedState {
  const GroupSharedState({this.overrides = const {}, this.homework = const {}, this.teacherHomework = const {}, this.since, this.syncedAt});

  final Map<String, GroupOverrideRow> overrides;
  final Map<String, GroupHomeworkRow> homework; // ДЗ старосты
  final Map<String, GroupHomeworkRow> teacherHomework; // ДЗ преподавателей (с именем автора)

  /// Время сервера, с которого нужно просить следующие изменения.
  final String? since;

  /// Когда телефон последний раз успешно говорил с сервером.
  final DateTime? syncedAt;

  static const empty = GroupSharedState();

  /// Правки, которые действуют сейчас: относящиеся к текущему расписанию группы ([currentHash]).
  List<GroupOverrideRow> activeOverrides(String? currentHash) =>
      [for (final o in overrides.values) if (currentHash == null || o.baseHash == currentHash) o];

  /// Правки к уже устаревшему расписанию (после загрузки нового xlsx) — староста их стирает с сервера.
  List<GroupOverrideRow> staleOverrides(String currentHash) => [for (final o in overrides.values) if (o.baseHash != currentHash) o];

  /// Номера всех файлов, прикреплённых к ДЗ группы (старосты и преподавателей).
  Set<String> get fileIds => {
        for (final h in [...homework.values, ...teacherHomework.values]) for (final f in h.files) f.id,
      };

  /// Копии состояния с одной изменённой строкой: староста видит свои действия сразу, не дожидаясь ответа сервера.
  GroupSharedState withoutHomework(String id) =>
      GroupSharedState(overrides: overrides, homework: {...homework}..remove(id), teacherHomework: teacherHomework, since: since, syncedAt: syncedAt);

  GroupSharedState withHomework(GroupHomeworkRow row) =>
      GroupSharedState(overrides: overrides, homework: {...homework, row.id: row}, teacherHomework: teacherHomework, since: since, syncedAt: syncedAt);

  GroupSharedState withoutOverrides(Iterable<String> ids) => GroupSharedState(
        overrides: {...overrides}..removeWhere((id, _) => ids.contains(id)),
        homework: homework,
        teacherHomework: teacherHomework,
        since: since,
        syncedAt: syncedAt,
      );

  GroupSharedState withOverrides(Iterable<GroupOverrideRow> rows) => GroupSharedState(
        overrides: {...overrides, for (final o in rows) o.id: o},
        homework: homework,
        teacherHomework: teacherHomework,
        since: since,
        syncedAt: syncedAt,
      );

  /// Правки, которые новая правка [o] заменяет: на ту же пару в тот же день (своя пара «add» — только среди своих пар).
  /// У двух подгрупп в одно время идут разные предметы: правка с названием предмета (например, аттестация) заменяет только правку
  /// того же предмета или правку без названия (на всю пару). Правка другого предмета остаётся — это пара другой подгруппы.
  List<GroupOverrideRow> overridesReplacedBy(Override o) => [
        for (final e in overrides.values)
          if (e.date == o.date &&
              e.pair == o.pair &&
              (o.type == OverrideType.add ? e.type == OverrideType.add : e.type != OverrideType.add) &&
              (o.type == OverrideType.add || e.matchSubject == null || o.matchSubject == null || e.matchSubject == o.matchSubject))
            e,
      ];

  /// Правки, которые убираются вместе с [row]: перенос пары — это две правки (отмена на старом месте и своя пара на новом),
  /// и «вернуть как было» должно убрать обе. Для переносов, сделанных до появления метки в отмене, пару ищем по времени.
  List<GroupOverrideRow> withMovePartner(GroupOverrideRow row) {
    final partners = <GroupOverrideRow>[];
    if (row.type == OverrideType.add && row.note == movedNote) {
      final mark = moveMark(row.date, row.pair);
      final marked = [for (final o in overrides.values) if (o.type == OverrideType.cancel && o.note == mark) o];
      if (marked.isNotEmpty) {
        partners.addAll(marked);
      } else {
        // перенос сделан старой версией: отмена записана на сервере раньше добавления, обычно в те же секунды
        final at = row.updatedAt;
        final near = [
          for (final o in overrides.values)
            if (at != null &&
                o.type == OverrideType.cancel &&
                o.note == null &&
                o.repeatWeekly == row.repeatWeekly &&
                (!row.repeatWeekly || o.matchSubject == row.subject) &&
                o.updatedAt != null &&
                !o.updatedAt!.isAfter(at) &&
                at.difference(o.updatedAt!) < const Duration(seconds: 60))
              o,
        ]..sort((a, b) => b.updatedAt!.compareTo(a.updatedAt!));
        if (near.isNotEmpty) partners.add(near.first);
      }
    } else if (row.type == OverrideType.cancel && row.note != null && row.note!.startsWith(_moveMarkPrefix)) {
      partners.addAll([for (final o in overrides.values) if (o.type == OverrideType.add && o.note == movedNote && moveMark(o.date, o.pair) == row.note) o]);
    }
    return [row, ...partners];
  }

  List<GroupHomeworkRow> get homeworkList => homework.values.toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  List<GroupHomeworkRow> get teacherHomeworkList => teacherHomework.values.toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  /// Применяет «дельту» с сервера: новые и изменённые строки добавляются, удалённые (deleted = true) убираются.
  GroupSharedState merge(Map<String, dynamic> delta, {DateTime? now}) {
    final newOverrides = {...overrides};
    for (final raw in (delta['overrides'] as List? ?? const [])) {
      final j = raw as Map<String, dynamic>;
      if (j['deleted'] == true) {
        newOverrides.remove(j['id']);
      } else {
        newOverrides[j['id'] as String] = GroupOverrideRow.fromJson(j);
      }
    }
    final newHomework = {...homework};
    for (final raw in (delta['homework'] as List? ?? const [])) {
      final j = raw as Map<String, dynamic>;
      if (j['deleted'] == true) {
        newHomework.remove(j['id']);
      } else {
        newHomework[j['id'] as String] = GroupHomeworkRow.fromJson(j);
      }
    }
    final newTeacher = {...teacherHomework};
    for (final raw in (delta['teacher_homework'] as List? ?? const [])) {
      final j = raw as Map<String, dynamic>;
      if (j['deleted'] == true) {
        newTeacher.remove(j['id']);
      } else {
        newTeacher[j['id'] as String] = GroupHomeworkRow.fromJson(j);
      }
    }
    return GroupSharedState(
      overrides: newOverrides,
      homework: newHomework,
      teacherHomework: newTeacher,
      since: delta['server_time'] as String? ?? since,
      syncedAt: now ?? syncedAt,
    );
  }

  /// Полная загрузка: прежнее содержимое заменяется.
  GroupSharedState replaceWith(Map<String, dynamic> full, {DateTime? now}) => const GroupSharedState().merge(full, now: now);

  String encode() => jsonEncode({
        'since': since,
        'syncedAt': syncedAt?.toUtc().toIso8601String(),
        'overrides': [for (final o in overrides.values) o.toJson()],
        'homework': [for (final h in homework.values) h.toJson()],
        'teacherHomework': [for (final h in teacherHomework.values) h.toJson()],
      });

  factory GroupSharedState.decode(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    return GroupSharedState(
      since: j['since'] as String?,
      syncedAt: j['syncedAt'] == null ? null : DateTime.parse(j['syncedAt'] as String),
      overrides: {for (final o in (j['overrides'] as List)) (o as Map<String, dynamic>)['id'] as String: GroupOverrideRow.fromJson(o)},
      homework: {for (final h in (j['homework'] as List)) (h as Map<String, dynamic>)['id'] as String: GroupHomeworkRow.fromJson(h)},
      // в кэше прежних версий этого поля нет — тогда ДЗ преподавателей просто ещё не загружены
      teacherHomework: {for (final h in (j['teacherHomework'] as List? ?? const [])) (h as Map<String, dynamic>)['id'] as String: GroupHomeworkRow.fromJson(h)},
    );
  }
}

/// Староста: токен на этом телефоне и группа, которой он управляет.
class EditorSession {
  const EditorSession({required this.token, required this.groupId});
  final String token;
  final String groupId;
}
