// Домашние задания: модель, разбивка по срокам, экспорт/импорт в JSON.
// Всё хранится только на телефоне (АРХИТЕКТУРА.md, §0, §10).

import 'dart:convert';

import '../core/week.dart';
import 'attachment.dart';
import 'models.dart';

/// Кто задал ДЗ. Порядок — важность при показе: преподаватель, потом староста, потом личное.
enum HomeworkSource {
  teacher('Преподаватель'),
  headman('Староста'),
  mine('Мои');

  const HomeworkSource(this.title);
  final String title;
}

class HomeworkItem {
  const HomeworkItem({
    this.id,
    required this.subject,
    required this.text,
    required this.dueDate,
    this.kind,
    this.done = false,
    required this.createdAt,
    this.attachments = const [],
    this.source = HomeworkSource.mine,
    this.sharedId,
    this.author,
  });

  final int? id; // null — ещё не сохранено в базу
  final String subject;
  final String text;
  final DateTime dueDate; // «только день», UTC
  final LessonKind? kind; // к лекции / к практике (null — любое занятие)
  final bool done;
  final DateTime createdAt;
  final List<Attachment> attachments; // фото и файлы к заданию
  final HomeworkSource source; // чьё это ДЗ
  final String? sharedId; // номер строки на сервере (ДЗ старосты и преподавателей); у личного null
  final String? author; // имя преподавателя, если ДЗ от него

  HomeworkItem copyWith({bool? done, List<Attachment>? attachments}) => HomeworkItem(
        id: id,
        subject: subject,
        text: text,
        dueDate: dueDate,
        kind: kind,
        done: done ?? this.done,
        createdAt: createdAt,
        attachments: attachments ?? this.attachments,
        source: source,
        sharedId: sharedId,
        author: author,
      );

  /// Одинаковое ДЗ (предмет, текст, срок) — нужно, чтобы импорт не плодил дубликаты.
  String get fingerprint => '$subject|$text|${dueDate.toIso8601String()}';
}

/// Раздел списка ДЗ.
enum HomeworkBucket {
  overdue('Просрочено'),
  today('На сегодня'),
  tomorrow('На завтра'),
  thisWeek('На этой неделе'),
  later('Позже'),
  done('Выполнено');

  const HomeworkBucket(this.title);
  final String title;
}

/// Раскладывает ДЗ по разделам. [today] — сегодняшний день (UTC, без времени).
/// Внутри раздела: по сроку, потом по времени создания. Пустые разделы не возвращаются.
Map<HomeworkBucket, List<HomeworkItem>> groupHomework(List<HomeworkItem> items, DateTime today) {
  final day = dayOnly(today);
  final tomorrow = day.add(const Duration(days: 1));
  // Конец текущей учебной недели — ближайшее воскресенье (включительно)
  final endOfWeek = day.add(Duration(days: DateTime.sunday - day.weekday));

  HomeworkBucket bucketOf(HomeworkItem item) {
    if (item.done) return HomeworkBucket.done;
    final due = dayOnly(item.dueDate);
    if (due.isBefore(day)) return HomeworkBucket.overdue;
    if (due == day) return HomeworkBucket.today;
    if (due == tomorrow) return HomeworkBucket.tomorrow;
    if (!due.isAfter(endOfWeek)) return HomeworkBucket.thisWeek;
    return HomeworkBucket.later;
  }

  final result = <HomeworkBucket, List<HomeworkItem>>{};
  for (final item in items) {
    result.putIfAbsent(bucketOf(item), () => []).add(item);
  }
  for (final list in result.values) {
    list.sort((a, b) {
      final byDue = a.dueDate.compareTo(b.dueDate);
      return byDue != 0 ? byDue : a.createdAt.compareTo(b.createdAt);
    });
  }
  // Порядок разделов — как в enum
  return {for (final b in HomeworkBucket.values) if (result.containsKey(b)) b: result[b]!};
}

/// Невыполненные ДЗ со сроком на конкретный день (для значка на паре и вечернего напоминания).
List<HomeworkItem> dueOn(List<HomeworkItem> items, DateTime day) =>
    [for (final i in items) if (!i.done && dayOnly(i.dueDate) == dayOnly(day)) i];

// ---------- экспорт / импорт ----------

const _exportVersion = 1;

/// ДЗ → текст JSON (для переноса на другой телефон). Фото в экспорт не входят.
String exportHomework(List<HomeworkItem> items) => const JsonEncoder.withIndent(' ').convert({
      'app': 'unigraf',
      'version': _exportVersion,
      'homework': [
        for (final i in items)
          {
            'subject': i.subject,
            'text': i.text,
            'dueDate': i.dueDate.toIso8601String().substring(0, 10),
            'kind': i.kind?.name,
            'done': i.done,
            'createdAt': i.createdAt.toUtc().toIso8601String(),
          },
      ],
    });

/// Текст JSON → ДЗ. Бросает [FormatException], если текст не похож на экспорт приложения.
List<HomeworkItem> importHomework(String json) {
  final Object? data;
  try {
    data = jsonDecode(json);
  } on FormatException {
    throw const FormatException('Это не файл с домашними заданиями');
  }
  if (data is! Map || (data['app'] != 'unigraf' && data['app'] != 'raspisanie') || data['homework'] is! List) {
    throw const FormatException('Это не файл с домашними заданиями');
  }
  try {
    return [
      for (final raw in data['homework'] as List)
        HomeworkItem(
          subject: (raw as Map)['subject'] as String,
          text: raw['text'] as String,
          dueDate: parseDay(raw['dueDate'] as String),
          kind: raw['kind'] == null ? null : LessonKind.parse(raw['kind'] as String),
          done: raw['done'] as bool? ?? false,
          createdAt: DateTime.parse(raw['createdAt'] as String).toUtc(),
        ),
    ];
  } catch (_) {
    throw const FormatException('Файл с домашними заданиями повреждён');
  }
}
