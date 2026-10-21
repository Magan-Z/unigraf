// План уведомлений на 7 дней вперёд (АРХИТЕКТУРА.md, §7.7).
// Здесь только расчёт «что и когда показать». Сами уведомления ставит платформенный слой
// (flutter_local_notifications) — он берёт этот список и перепланирует его после каждой синхронизации.

import '../core/bells.dart';
import 'homework.dart';
import 'models.dart';
import 'schedule_resolver.dart';

class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.fireAt,
    required this.title,
    required this.body,
    this.homework = false,
    this.payload,
  });

  /// Стабильный номер: одно и то же уведомление при перепланировании заменяется, а не дублируется.
  final int id;
  final DateTime fireAt; // момент показа (UTC)
  final String title;
  final String body;
  final bool homework; // вечернее напоминание о ДЗ (другой канал уведомлений)

  /// Что открыть по нажатию: «day:2026-10-07» — этот день на экране «Сегодня», «homework» — вкладку «ДЗ».
  final String? payload;
}

const planDays = 7;
const homeworkPayload = 'homework';

String dayPayload(DateTime day) =>
    'day:${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// Разбор «day:2026-10-07». Не наш формат — null.
DateTime? parseDayPayload(String? payload) {
  if (payload == null || !payload.startsWith('day:')) return null;
  final d = DateTime.tryParse(payload.substring(4));
  return d == null ? null : DateTime.utc(d.year, d.month, d.day);
}
const eveningReminderHour = 19; // по Москве

/// [notifyBeforeMin] = 0 — уведомления перед парой выключены.
List<PlannedNotification> planNotifications({
  required DateTime now,
  required ScheduleIndex index,
  required GroupSchedule schedule,
  required UserProfile profile,
  required List<HomeworkItem> homework,
  required int notifyBeforeMin,
  required bool eveningReminder,
  List<Override> overrides = const [],
  int? forcedWeek,
  String Function(String subject)? nameOf, // свои названия предметов (null — настоящие)
}) {
  final name = nameOf ?? (String s) => s;
  final today = moscowToday(now);
  final result = <PlannedNotification>[];

  for (var i = 0; i < planDays; i++) {
    final day = today.add(Duration(days: i));

    // 1. Перед парой: «Философия → 3-01 · Кутаев А.Х.»
    if (notifyBeforeMin > 0) {
      for (final l in resolve(day, index, schedule, profile, overrides: overrides, forcedWeek: forcedWeek)) {
        final fireAt = l.startAt.subtract(Duration(minutes: notifyBeforeMin));
        if (!fireAt.isAfter(now)) continue;
        result.add(PlannedNotification(
          id: _id(day, l.pair, 0),
          payload: dayPayload(day),
          fireAt: fireAt,
          title: [if (l.kind.isAssessment) '${l.kind.title}: ', name(l.subject), if (l.room != null) ' → ${l.room}'].join(),
          body: [if (l.teacher != null) l.teacher!, 'через $notifyBeforeMin мин'].join(' · '),
        ));
      }
    }

    // 2. Вечером в 19:00: «На завтра 2 ДЗ: …» — если на завтра есть невыполненные
    if (eveningReminder) {
      final fireAt = DateTime.utc(day.year, day.month, day.day, eveningReminderHour).subtract(moscowOffset);
      final due = dueOn(homework, day.add(const Duration(days: 1)));
      if (due.isNotEmpty && fireAt.isAfter(now)) {
        final subjects = {for (final h in due) name(h.subject)}.toList();
        result.add(PlannedNotification(
          id: _id(day, 0, 1),
          fireAt: fireAt,
          title: 'На завтра ${due.length} ДЗ',
          body: subjects.join(', '),
          homework: true,
          payload: homeworkPayload,
        ));
      }
    }
  }

  result.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return result;
}

/// Номер вида ГГГГММДД·100 + пара·10 + тип (0 — пара, 1 — вечернее ДЗ). Помещается в 32 бита.
int _id(DateTime day, int pair, int type) => (day.year % 100) * 1000000 + day.month * 10000 + day.day * 100 + pair * 10 + type;
