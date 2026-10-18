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
import '../../domain/models.dart';
import '../../domain/schedule_resolver.dart';
import '../../theme/app_theme.dart' show roomTextStyle;
import '../../theme/subject_palette.dart';
import '../../theme/tokens.dart';
import '../common/skeleton.dart';
import '../common/lesson_widgets.dart';
import '../common/reveal.dart';
import '../common/word_fit_text.dart';
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
    final scheme = Theme.of(context).colorScheme;
    final colors = _WeekColors.of(scheme);

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

        // Сколько точек-номеров пар рисовать в шапке дня: не меньше 5, больше — если есть поздние пары
        final pairSlots = math.max(5, days.fold<int>(0, (m, d) => math.max(m, d.lessons.fold<int>(0, (a, l) => math.max(a, l.pair)))));
        final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);

        return Column(
          children: [
            _WeekBar(
              range: weekRangeText(monday, saturday),
              currentWeek: currentWeek,
              selected: week,
              onChanged: (w) => setState(() => _week = w),
            ),
            Expanded(
              child: ColoredBox(
                color: colors.page,
                child: CustomScrollView(
                  // Ключ по неделе: при переключении «1 / 2 неделя» список возвращается наверх, а пары появляются заново
                  key: ValueKey(week),
                  slivers: [
                    const SliverToBoxAdapter(child: SizedBox(height: 6)),
                    for (final entry in days)
                      SliverMainAxisGroup(slivers: [
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _DayHeaderDelegate(
                            height: (entry.lessons.isEmpty ? 68.0 : 80.0) * textScale,
                            colors: colors,
                            day: entry.day,
                            isToday: entry.day == today,
                            isPast: isCurrentWeek && entry.day.isBefore(today),
                            pairs: {for (final l in entry.lessons) l.pair},
                            pairSlots: pairSlots,
                            holiday: data.index.holidays.contains(entry.day),
                            lessonCount: entry.lessons.length,
                            span: entry.lessons.isEmpty
                                ? null
                                : '${moscowTimeText(entry.lessons.first.startAt)}–${moscowTimeText(entry.lessons.last.endAt)}',
                          ),
                        ),
                        if (entry.lessons.isNotEmpty)
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            sliver: SliverList.builder(
                              itemCount: entry.lessons.length,
                              itemBuilder: (context, i) {
                                final l = entry.lessons[i];
                                final past = isCurrentWeek && entry.day.isBefore(today);
                                return Reveal(
                                  index: i,
                                  child: _LessonRow(
                                    lesson: l,
                                    colors: colors,
                                    first: i == 0,
                                    last: i == entry.lessons.length - 1,
                                    highlighted: entry.day == today && !now.isBefore(l.startAt) && now.isBefore(l.endAt),
                                    dimmed: past || (entry.day == today && !now.isBefore(l.endAt)),
                                    note: lessonNote(l, now),
                                    hasHomework: dueOn(homework, entry.day).any((h) => h.subject == l.subject),
                                  ),
                                );
                              },
                            ),
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 12)),
                      ]),
                    SliverToBoxAdapter(child: SizedBox(height: Gap.xl + MediaQuery.paddingOf(context).bottom)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Цвета экрана: тонированный фон страницы и светлые карточки дней (в тёмной теме карточки светлее фона).
class _WeekColors {
  const _WeekColors({required this.page, required this.card, required this.divider});
  final Color page;
  final Color card;
  final Color divider;

  factory _WeekColors.of(ColorScheme s) {
    final light = s.brightness == Brightness.light;
    return _WeekColors(
      page: light ? Color.alphaBlend(s.onSurface.withValues(alpha: 0.055), s.surface) : s.surface,
      card: light ? s.surfaceContainerLowest : s.surfaceContainerHigh,
      divider: s.outlineVariant.withValues(alpha: 0.6),
    );
  }
}

const _cardRadius = 24.0;

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

/// Закрепляемая шапка карточки дня. Сверху небольшой отступ цвета страницы, чтобы пары под шапкой не просвечивали.
class _DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _DayHeaderDelegate({
    required this.height,
    required this.colors,
    required this.day,
    required this.isToday,
    required this.isPast,
    required this.pairs,
    required this.pairSlots,
    required this.holiday,
    required this.lessonCount,
    required this.span,
  });

  final double height;
  final _WeekColors colors;
  final DateTime day;
  final bool isToday;
  final bool isPast;
  final Set<int> pairs;
  final int pairSlots;
  final bool holiday;
  final int lessonCount;
  final String? span;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  bool shouldRebuild(covariant _DayHeaderDelegate old) =>
      old.height != height ||
      old.colors.page != colors.page ||
      old.colors.card != colors.card ||
      old.day != day ||
      old.isToday != isToday ||
      old.isPast != isPast ||
      old.pairSlots != pairSlots ||
      old.holiday != holiday ||
      old.lessonCount != lessonCount ||
      old.span != span ||
      old.pairs.length != pairs.length ||
      !old.pairs.containsAll(pairs);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final empty = lessonCount == 0;

    // Сегодня — шапка цвета темы; остальные — спокойные; прошедшие дни приглушены
    final bg = isToday ? scheme.primaryContainer : colors.card;
    final fg = isToday ? scheme.onPrimaryContainer : (isPast ? scheme.onSurfaceVariant : scheme.onSurface);
    final soft = isToday ? scheme.onPrimaryContainer.withValues(alpha: 0.8) : scheme.onSurfaceVariant;

    final subtitle = empty
        ? TextSpan(text: holiday ? 'праздничный день' : 'пар нет')
        : TextSpan(children: [
            TextSpan(text: '$lessonCount ${plural(lessonCount, 'пара', 'пары', 'пар')}', style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
            if (span != null) TextSpan(text: ' · $span'),
          ]);

    return Semantics(
      header: true,
      container: true,
      label: '${weekdayTitles[day.weekday]}, ${dateText(day)}${isToday ? ', сегодня' : ''}. '
          '${empty ? (holiday ? 'Праздничный день' : 'Пар нет') : '$lessonCount ${plural(lessonCount, 'пара', 'пары', 'пар')}: ${(pairs.toList()..sort()).join(', ')}'}',
      child: ExcludeSemantics(
        child: LayoutBuilder(builder: (context, box) {
          final narrow = box.maxWidth < 350; // телефон 320 dp: без надписи «сегодня» и с мелкой подписью
          return ColoredBox(
          color: colors.page,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: empty
                    ? BorderRadius.circular(_cardRadius)
                    : const BorderRadius.vertical(top: Radius.circular(_cardRadius)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                child: Row(children: [
                  _DateTile(day: day, isToday: isToday, isPast: isPast, colors: colors),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(
                          child: Text(weekdayTitles[day.weekday],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              // Название дня — главный заголовок карточки: крупнее и жирнее предметов внутри
                              style: theme.textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w800, letterSpacing: -0.2, height: 1.15)),
                        ),
                        if (isToday && !narrow) ...[
                          const SizedBox(width: Gap.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 2),
                            decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(999)),
                            child: Text('сегодня', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onPrimary)),
                          ),
                        ],
                      ]),
                      Text.rich(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: (narrow ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)?.copyWith(color: soft)),
                    ]),
                  ),
                  if (!empty) ...[
                    const SizedBox(width: Gap.sm),
                    _PairDots(pairs: pairs, slots: pairSlots, color: isToday || !isPast ? scheme.primary : scheme.onSurfaceVariant, free: soft, small: narrow),
                  ],
                ]),
              ),
            ),
          ),
        );
        }),
      ),
    );
  }
}

/// Плитка с числом: «сегодня» — залитая цветом темы, остальные — спокойные.
class _DateTile extends StatelessWidget {
  const _DateTile({required this.day, required this.isToday, required this.isPast, required this.colors});
  final DateTime day;
  final bool isToday;
  final bool isPast;
  final _WeekColors colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = isToday ? scheme.primary : Color.alphaBlend(scheme.onSurface.withValues(alpha: 0.07), colors.card);
    final fg = isToday ? scheme.onPrimary : (isPast ? scheme.onSurfaceVariant : scheme.onSurface);
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Text('${day.day}', style: theme.textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w800, fontSize: 22, height: 1)),
    );
  }
}

/// Точки по номерам пар: закрашена — пара есть, пустая — окно. Видно структуру дня без чтения строк.
class _PairDots extends StatelessWidget {
  const _PairDots({required this.pairs, required this.slots, required this.color, required this.free, this.small = false});
  final bool small;
  final Set<int> pairs;
  final int slots;
  final Color color;
  final Color free;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var n = 1; n <= slots; n++)
        Padding(
          padding: EdgeInsets.only(left: n == 1 ? 0 : (small ? 3 : 5)),
          child: Container(
            width: small ? 7 : 9,
            height: small ? 7 : 9,
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

/// Строка пары внутри карточки дня: время слева, предмет, тип и преподаватель, табличка аудитории справа.
class _LessonRow extends ConsumerWidget {
  const _LessonRow({
    required this.lesson,
    required this.colors,
    required this.first,
    required this.last,
    required this.highlighted,
    required this.dimmed,
    required this.note,
    required this.hasHomework,
  });

  final ResolvedLesson lesson;
  final _WeekColors colors;
  final bool first;
  final bool last;
  final bool highlighted;
  final bool dimmed;
  final String? note;
  final bool hasHomework;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = lesson;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final styles = ref.watch(subjectStylesProvider);
    final tone = styles.tone(l.subject, theme.brightness);
    final room = l.room;
    final teacher = l.teacher;

    // Идущая сейчас пара подсвечена мягким цветом предмета
    final bg = highlighted ? Color.alphaBlend(tone.container.withValues(alpha: 0.6), colors.card) : colors.card;
    final radius = last ? const BorderRadius.vertical(bottom: Radius.circular(_cardRadius)) : BorderRadius.zero;

    final row = Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showLessonActions(context, l),
        onLongPress: () => showLessonActions(context, l),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!first) Divider(height: 1, thickness: 1, indent: Gap.lg, endIndent: Gap.lg, color: colors.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 12, Gap.lg, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              SizedBox(
                width: 50,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(moscowTimeText(l.startAt), style: theme.textTheme.titleSmall?.copyWith(color: tone.onContainer, fontWeight: FontWeight.w800)),
                  Text(moscowTimeText(l.endAt), style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ]),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  WordFitText(
                    styles.name(l.subject),
                    style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSurface, fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.25),
                    trailing: hasHomework
                        ? WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(left: Gap.sm),
                              child: Icon(Icons.assignment_late_rounded, size: 17, color: scheme.error, semanticLabel: 'Есть домашнее задание'),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 5),
                  Wrap(spacing: Gap.sm, runSpacing: Gap.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    KindBadge(l.kind, tone: tone),
                    if (teacher != null) Text(teacher, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    if (l.withGroups.isNotEmpty)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.groups_rounded, size: 15, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 2),
                        Text('+${l.withGroups.length}', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ]),
                  ]),
                  if (note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.edit_note_rounded, size: 15, color: tone.onContainer),
                        const SizedBox(width: Gap.xs),
                        Flexible(child: Text(note!, style: theme.textTheme.bodySmall?.copyWith(color: tone.onContainer))),
                      ]),
                    ),
                ]),
              ),
              if (room != null) ...[
                const SizedBox(width: Gap.sm),
                _RoomChip(room: room, tone: tone),
              ],
            ]),
          ),
        ]),
      ),
    );

    return Semantics(
      container: true,
      label: '${moscowTimeText(l.startAt)}–${moscowTimeText(l.endAt)}, ${l.pair} пара, ${l.subject}, ${l.kind.title}'
          '${room != null ? ', аудитория $room' : ''}${teacher != null ? ', $teacher' : ''}'
          '${l.withGroups.isNotEmpty ? '. Вместе с группами: ${l.withGroups.join(', ')}' : ''}'
          '${hasHomework ? '. Есть домашнее задание' : ''}${note != null ? '. $note' : ''}',
      onTap: () => showLessonActions(context, l),
      onLongPress: () => showLessonActions(context, l),
      onLongPressHint: 'Действия с парой',
      child: ExcludeSemantics(child: Opacity(opacity: dimmed ? 0.55 : 1, child: row)),
    );
  }
}

/// Аудитория: мягкая «табличка» цвета предмета (номер — главное в строке, поэтому крупный жирный шрифт).
class _RoomChip extends StatelessWidget {
  const _RoomChip({required this.room, required this.tone});
  final String room;
  final SubjectTone tone;

  @override
  Widget build(BuildContext context) {
    final plain = room.length <= 6;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: 56, maxWidth: plain ? double.infinity : 92),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: plain ? 12 : 8, vertical: 7),
        decoration: BoxDecoration(color: tone.container, borderRadius: BorderRadius.circular(12)),
        child: Text(
          room,
          textAlign: TextAlign.center,
          maxLines: plain ? 1 : 2,
          softWrap: !plain,
          style: roomTextStyle(plain ? 19 : 12, color: tone.onContainer),
        ),
      ),
    );
  }
}
