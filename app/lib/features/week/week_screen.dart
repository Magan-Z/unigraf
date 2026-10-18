// Экран «Неделя»: сверху закреплён переключатель 1 / 2 неделя (по умолчанию текущая), а каждый день — отдельный
// блок с закреплённой полосой-заголовком: число, день, сколько пар и в каких парах (точки), «сегодня» выделен.
// Полоса дня прилипает к верху при прокрутке, поэтому всегда видно, какой это день и какая неделя.
// Показываются настоящие даты, поэтому здесь видны и ваши личные правки (отмены, переносы, свои пары).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../core/bells.dart';
import '../../core/formatting.dart';
import '../../domain/homework.dart';
import '../../domain/schedule_resolver.dart';
import '../../theme/tokens.dart';
import '../common/skeleton.dart';
import '../common/lesson_widgets.dart';
import '../common/reveal.dart';
import '../common/sliding_segments.dart';
import '../overrides/day_edits.dart';

const _monthsShort = ['', 'янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сент', 'окт', 'нояб', 'дек'];

/// «12–17 октября» (в одном месяце) или «28 сент – 3 окт» (на стыке месяцев).
String weekRangeText(DateTime monday, DateTime saturday) {
  if (monday.month == saturday.month) return '${monday.day}–${dateText(saturday)}';
  return '${monday.day} ${_monthsShort[monday.month]} – ${saturday.day} ${_monthsShort[saturday.month]}';
}

class WeekScreen extends ConsumerStatefulWidget {
  const WeekScreen({super.key});

  @override
  ConsumerState<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends ConsumerState<WeekScreen> {
  int? _week; // null — показывать текущую

  /// Понедельник недели с нужным номером: текущая неделя, если номер совпадает, иначе следующая.
  DateTime _mondayOf(int week, DateTime today, MySchedule data) {
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    return data.weekFor(thisMonday) == week ? thisMonday : thisMonday.add(const Duration(days: 7));
  }

  @override
  Widget build(BuildContext context) {
    final my = ref.watch(myScheduleProvider);
    final today = ref.watch(todayProvider);
    final now = ref.watch(nowProvider).value ?? ref.read(clockProvider).now();
    final homework = ref.watch(homeworkWithGroupProvider).value ?? const <HomeworkItem>[];

    return my.when(
      loading: () => const ScheduleSkeleton(),
      error: (e, _) => Center(child: Text('Не удалось прочитать расписание:\n$e', textAlign: TextAlign.center)),
      data: (data) {
        if (data == null) return const SizedBox();
        final currentWeek = data.weekFor(today);
        final week = _week ?? currentWeek;
        final monday = _mondayOf(week, today, data);
        final saturday = monday.add(const Duration(days: 5));
        final thisMonday = today.subtract(Duration(days: today.weekday - 1));
        final isCurrentWeek = monday == thisMonday;

        // Дни недели с парами; воскресенье показываем, только если там есть ваша своя пара
        final days = [
          for (var i = 0; i < 7; i++)
            (
              day: monday.add(Duration(days: i)),
              lessons: resolve(monday.add(Duration(days: i)), data.index, data.schedule, data.profile,
                  overrides: data.overrides, forcedWeek: _week ?? data.forcedWeek),
            ),
        ].where((d) => d.day.weekday != DateTime.sunday || d.lessons.isNotEmpty).toList();

        // Сколько точек-номеров пар рисовать в полосе дня: не меньше 5, больше — если есть поздние пары
        final pairSlots = math.max(5, days.fold<int>(0, (m, d) => math.max(m, d.lessons.fold<int>(0, (a, l) => math.max(a, l.pair)))));
        final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
        final headerHeight = 64.0 * textScale;

        return Column(
          children: [
            _WeekBar(
              range: weekRangeText(monday, saturday),
              currentWeek: currentWeek,
              selected: week,
              onChanged: (w) => setState(() => _week = w),
            ),
            Expanded(
              child: CustomScrollView(
                // Ключ по неделе: при переключении «1 / 2 неделя» список возвращается наверх, а пары появляются заново
                key: ValueKey(week),
                slivers: [
                  for (final entry in days)
                    SliverMainAxisGroup(slivers: [
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _DayHeaderDelegate(
                          height: headerHeight,
                          day: entry.day,
                          isToday: entry.day == today,
                          isPast: isCurrentWeek && entry.day.isBefore(today),
                          pairs: {for (final l in entry.lessons) l.pair},
                          pairSlots: pairSlots,
                          holiday: data.index.holidays.contains(entry.day),
                          lessonCount: entry.lessons.length,
                        ),
                      ),
                      if (entry.lessons.isEmpty)
                        const SliverToBoxAdapter(child: SizedBox(height: Gap.lg))
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.xl),
                          sliver: SliverList.builder(
                            itemCount: entry.lessons.length,
                            itemBuilder: (context, i) {
                              final l = entry.lessons[i];
                              final past = isCurrentWeek && entry.day.isBefore(today);
                              return Reveal(
                                index: i,
                                child: Padding(
                                  padding: EdgeInsets.only(bottom: i == entry.lessons.length - 1 ? 0 : Gap.sm),
                                  child: LessonTile(
                                    timeLabel: '${moscowTimeText(l.startAt)}–${moscowTimeText(l.endAt)} · ${l.pair} пара',
                                    subject: l.subject,
                                    kind: l.kind,
                                    teacher: l.teacher,
                                    room: l.room,
                                    highlighted: entry.day == today && !now.isBefore(l.startAt) && now.isBefore(l.endAt),
                                    dimmed: past || (entry.day == today && !now.isBefore(l.endAt)),
                                    note: lessonNote(l, now),
                                    hasHomework: dueOn(homework, entry.day).any((h) => h.subject == l.subject),
                                    withGroups: l.withGroups,
                                    onLongPress: () => showLessonActions(context, l),
                                    onTap: () => showLessonActions(context, l),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ]),
                  SliverToBoxAdapter(child: SizedBox(height: Gap.xl + MediaQuery.paddingOf(context).bottom)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Верхняя панель, которая не прокручивается: название, даты недели и переключатель «1 / 2 неделя».
class _WeekBar extends StatelessWidget {
  const _WeekBar({required this.range, required this.currentWeek, required this.selected, required this.onChanged});

  final String range;
  final int currentWeek;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.md),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Неделя', style: theme.textTheme.headlineSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(range, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          flex: 5,
          child: SlidingSegments<int>(
            proportional: true,
            segments: [
              Segment(1, currentWeek == 1 ? '1 неделя · сейчас' : '1 неделя'),
              Segment(2, currentWeek == 2 ? '2 неделя · сейчас' : '2 неделя'),
            ],
            selected: selected,
            onChanged: onChanged,
          ),
        ),
      ]),
    );
  }
}

/// Закреплённая полоса дня. Занимает всю ширину, чтобы дни чётко отделялись друг от друга.
class _DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _DayHeaderDelegate({
    required this.height,
    required this.day,
    required this.isToday,
    required this.isPast,
    required this.pairs,
    required this.pairSlots,
    required this.holiday,
    required this.lessonCount,
  });

  final double height;
  final DateTime day;
  final bool isToday;
  final bool isPast;
  final Set<int> pairs;
  final int pairSlots;
  final bool holiday;
  final int lessonCount;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  bool shouldRebuild(covariant _DayHeaderDelegate old) =>
      old.height != height ||
      old.day != day ||
      old.isToday != isToday ||
      old.isPast != isPast ||
      old.pairSlots != pairSlots ||
      old.holiday != holiday ||
      old.lessonCount != lessonCount ||
      old.pairs.length != pairs.length ||
      !old.pairs.containsAll(pairs);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Цвета: сегодня — яркая полоса цвета темы; прошедшие дни — те же, но приглушённые; остальные — спокойный тон
    final band = isToday ? scheme.primaryContainer : Color.alphaBlend(scheme.onSurface.withValues(alpha: 0.055), scheme.surface);
    final fg = isToday ? scheme.onPrimaryContainer : (isPast ? scheme.onSurfaceVariant : scheme.onSurface);
    final soft = isToday ? scheme.onPrimaryContainer.withValues(alpha: 0.78) : scheme.onSurfaceVariant;

    final empty = lessonCount == 0;
    final subtitle = empty
        ? '${dateText(day)} · ${holiday ? 'праздничный день' : 'пар нет'}'
        : '${dateText(day)} · $lessonCount ${plural(lessonCount, 'пара', 'пары', 'пар')}';

    return Semantics(
      header: true,
      container: true,
      label: '${weekdayTitles[day.weekday]}, ${dateText(day)}${isToday ? ', сегодня' : ''}. ${empty ? (holiday ? 'Праздничный день' : 'Пар нет') : '$lessonCount ${plural(lessonCount, 'пара', 'пары', 'пар')}: ${(pairs.toList()..sort()).join(', ')}'}',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: band,
            border: Border(bottom: BorderSide(color: isToday ? Colors.transparent : scheme.outlineVariant.withValues(alpha: 0.7))),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
            child: Row(children: [
              _DateTile(day: day, isToday: isToday, isPast: isPast),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(weekdayTitles[day.weekday],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w700)),
                    ),
                    if (isToday) ...[
                      const SizedBox(width: Gap.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 2),
                        decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(999)),
                        child: Text('сегодня', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onPrimary)),
                      ),
                    ],
                  ]),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: soft)),
                ]),
              ),
              if (!empty) ...[
                const SizedBox(width: Gap.sm),
                _PairDots(pairs: pairs, slots: pairSlots, color: isToday ? scheme.primary : (isPast ? scheme.onSurfaceVariant : scheme.primary), free: soft),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Плитка с числом: «сегодня» — залитая цветом темы, остальные — спокойные.
class _DateTile extends StatelessWidget {
  const _DateTile({required this.day, required this.isToday, required this.isPast});
  final DateTime day;
  final bool isToday;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = isToday ? scheme.primary : scheme.surface;
    final fg = isToday ? scheme.onPrimary : (isPast ? scheme.onSurfaceVariant : scheme.onSurface);
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: isToday ? null : Border.all(color: scheme.outlineVariant),
      ),
      child: Text('${day.day}', style: theme.textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w800, height: 1)),
    );
  }
}

/// Точки по номерам пар: закрашена — пара есть, пустая — окно. Видно структуру дня без чтения карточек.
class _PairDots extends StatelessWidget {
  const _PairDots({required this.pairs, required this.slots, required this.color, required this.free});
  final Set<int> pairs;
  final int slots;
  final Color color;
  final Color free;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var n = 1; n <= slots; n++)
        Padding(
          padding: EdgeInsets.only(left: n == 1 ? 0 : 5),
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pairs.contains(n) ? color : Colors.transparent,
              border: pairs.contains(n) ? null : Border.all(color: free.withValues(alpha: 0.55), width: 1.5),
            ),
          ),
        ),
    ]);
  }
}
