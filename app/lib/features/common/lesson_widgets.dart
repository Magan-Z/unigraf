// Карточка пары: название, тип, преподаватель и «табличка» с аудиторией. Цвета — по предмету.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../core/bells.dart';
import '../../core/formatting.dart';
import '../../domain/assessments.dart';
import '../../domain/lesson_homework.dart';
import '../../domain/models.dart';
import '../../theme/next_design.dart';
import '../../theme/subject_palette.dart';
import '../../theme/tokens.dart';
import 'homework_badge.dart';
import 'press_scale.dart';
import 'room_plate.dart';
import 'word_fit_text.dart';

/// Подпись типа занятия («Лекция» / «Практика»). Смысл несёт слово, а не цвет.
class KindBadge extends StatelessWidget {
  const KindBadge(this.kind, {super.key, this.tone});
  final LessonKind kind;
  final SubjectTone? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Аттестация, зачёт и экзамен заметны сразу: яркая метка с значком, цвет предмета не нужен
    if (kind.isAssessment) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
        decoration: BoxDecoration(color: scheme.error, borderRadius: BorderRadius.circular(Radii.sm - 4)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.quiz_rounded, size: 15, color: scheme.onError),
          const SizedBox(width: Gap.xs),
          Text(kind.title, style: theme.textTheme.labelMedium?.copyWith(color: scheme.onError, fontWeight: FontWeight.w700)),
        ]),
      );
    }
    final (bg, fg) = tone != null
        ? (tone!.accent.withValues(alpha: 0.16), tone!.onContainer)
        : (scheme.secondaryContainer, scheme.onSecondaryContainer);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.sm - 4)),
      child: Text(kind.title, style: theme.textTheme.labelMedium?.copyWith(color: fg)),
    );
  }
}

/// Одна пара. [timeLabel] — подпись со временем (в списке «Неделя»); в ленте «Сегодня» время стоит слева, там null.
class LessonTile extends ConsumerWidget {
  const LessonTile({
    super.key,
    required this.subject,
    required this.kind,
    this.timeLabel,
    this.teacher,
    this.room,
    this.highlighted = false,
    this.dimmed = false,
    this.note,
    this.homework = LessonHomework.none,
    this.onHomework,
    this.footer,
    this.withGroups = const [],
    this.onLongPress,
    this.onTap,
    this.dense = false,
  });

  /// Компактная карточка (экран «Неделя»): предмет мельче и спокойнее, чтобы заголовок дня был главнее.
  final bool dense;

  final String? timeLabel;
  final String subject;
  final LessonKind kind;
  final String? teacher;
  final String? room;
  final bool highlighted;
  final bool dimmed;
  final String? note;
  /// ДЗ к этой паре (из трёх источников): на карточке рисуется значок-закладка.
  final LessonHomework homework;

  /// Нажатие на значок ДЗ (откроется окно со списком заданий).
  final VoidCallback? onHomework;
  final String? footer; // дополнительная строка внизу (например, список групп в поиске)
  final List<String> withGroups; // группы, с которыми объединена лекция (на карточке — значок с числом)
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Свои название и цвет предмета (если пользователь их задал в настройках)
    final styles = ref.watch(subjectStylesProvider);
    final tone = styles.tone(subject, theme.brightness);
    final textColor = scheme.onSurface;

    final card = Material(
      color: tone.container,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kNextDesign ? Radii.lg + 2 : Radii.lg),
        side: highlighted ? BorderSide(color: tone.accent, width: 2.5) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: DecoratedBox(
          // цветная полоса слева — граница, а не отдельный блок: так карточка не зависит от IntrinsicHeight
          // Новый вид: без толстой полосы слева (цвет предмета уже есть на точке ленты и на табличке аудитории)
          decoration: kNextDesign ? const BoxDecoration() : BoxDecoration(border: Border(left: BorderSide(color: tone.accent, width: 6))),
          child: Stack(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(kNextDesign ? Gap.lg + 2 : Gap.lg, dense ? 10 : Gap.md, Gap.md, dense ? 10 : Gap.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  // Название и время не заезжают под значок ДЗ; блок не ниже значка, чтобы нижняя строка не упиралась в его «хвост»
                  ConstrainedBox(
                    constraints: BoxConstraints(minHeight: homework.isEmpty ? 0 : HomeworkBadge.top + HomeworkBadge.size - Gap.md),
                    child: Padding(
                      padding: EdgeInsets.only(right: homework.isEmpty ? 0 : HomeworkBadge.reserved - Gap.md),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (timeLabel != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Gap.xs),
                            child: Text(timeLabel!, style: theme.textTheme.labelMedium?.copyWith(color: tone.onContainer)),
                          ),
                        WordFitText(
                          styles.name(subject),
                          style: dense
                              ? theme.textTheme.titleMedium?.copyWith(color: textColor, fontSize: 15, fontWeight: FontWeight.w600)
                              : theme.textTheme.titleMedium?.copyWith(color: textColor),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                  // Нижняя строка: тип и преподаватель слева, «табличка» с аудиторией справа
                  LayoutBuilder(builder: (context, box) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: Wrap(spacing: Gap.sm, runSpacing: Gap.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        KindBadge(kind, tone: tone),
                        if (teacher != null) Text(teacher!, style: (dense ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)?.copyWith(color: scheme.onSurfaceVariant)),
                        if (withGroups.isNotEmpty)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.groups_rounded, size: 16, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 2),
                            Text('+${withGroups.length}', style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                          ]),
                      ]),
                    ),
                    if (room != null) ...[
                      const SizedBox(width: Gap.sm),
                      // Крупная табличка при крупном системном шрифте сжимается, но не занимает больше 62 % строки
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: box.maxWidth * 0.62),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: RoomPlate(room: room!, tone: tone, size: 23, pop: kNextDesign && note != null),
                        ),
                      ),
                    ],
                  ])),
                  if (note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Gap.sm),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.edit_note_rounded, size: 16, color: tone.onContainer),
                        const SizedBox(width: Gap.xs),
                        Flexible(child: Text(note!, style: theme.textTheme.bodySmall?.copyWith(color: tone.onContainer))),
                      ]),
                    ),
                  if (footer != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Gap.sm),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.groups_rounded, size: 16, color: scheme.onSurfaceVariant),
                        const SizedBox(width: Gap.xs),
                        Flexible(child: Text(footer!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
                      ]),
                    ),
                ]),
              ),
            ),
            ]),
          ]),
        ),
      ),
    );

    final tile = Semantics(
      container: true,
      label: joinSentences(
        '${timeLabel != null ? '$timeLabel, ' : ''}$subject, ${kind.title}'
        '${room != null ? ', аудитория $room' : ''}${teacher != null ? ', $teacher' : ''}',
        [
          if (withGroups.isNotEmpty) 'Вместе с группами: ${withGroups.join(', ')}',
          if (!homework.isEmpty) homework.allDone ? 'Домашнее задание выполнено' : 'Есть домашнее задание: ${homework.open}',
          ?note,
          ?footer,
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressHint: onLongPress == null ? null : 'Действия с парой',
      child: ExcludeSemantics(
        child: AnimatedOpacity(
          opacity: dimmed ? 0.55 : 1,
          duration: Motion.of(context, Motion.base),
          child: kNextDesign
              ? PressScale(child: note != null ? _AttentionGlow(color: scheme.tertiary, radius: Radii.lg + 2, child: card) : card)
              : card,
        ),
      ),
    );

    // Значок ДЗ лежит поверх карточки отдельным слоем (не внутри неё): у него своё нажатие и своя подпись для читалки,
    // а в веб-версии с включённой доступностью нажатие не уходит в саму карточку.
    if (homework.isEmpty || onHomework == null) return tile;
    return Stack(fit: StackFit.passthrough, children: [
      tile,
      Positioned(
        top: HomeworkBadge.top,
        right: HomeworkBadge.right,
        child: HomeworkBadge(homework: homework, onPressed: onHomework!),
      ),
    ]);
  }
}

/// Подпись под парой: заметка из правки или «изменено вами» / «изменено старостой в 14:20».
/// Время показывается по Москве; если правка сделана не сегодня — с датой («9 октября в 14:20»).
String? lessonNote(ResolvedLesson l, DateTime now) {
  final note = visibleNote(l.kind, l.note);
  if (note != null) return note;
  if (l.isPersonal) return 'изменено вами';
  if (!l.isGroup) return null;
  final at = l.groupChangedAt;
  if (at == null) return 'изменено старостой';
  final sameDay = moscowToday(at) == moscowToday(now);
  return 'изменено старостой ${sameDay ? '' : '${dateText(moscowToday(at))} '}в ${moscowTimeText(at)}';
}

/// Изменённая пара (староста или вы) при появлении на секунду «вспыхивает» янтарным и затихает:
/// взгляд сам находит, что в расписании не как обычно. Дальше остаётся только подпись «изменено…».
class _AttentionGlow extends StatelessWidget {
  const _AttentionGlow({required this.color, required this.radius, required this.child});
  final Color color;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = Motion.of(context, const Duration(milliseconds: 1600));
    if (duration == Duration.zero) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: duration,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, v, child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          // тень со смещением и размытием (не «ореол»): светится снизу, как подсвеченная плитка
          boxShadow: v < 0.01 ? null : [BoxShadow(color: color.withValues(alpha: 0.55 * v), blurRadius: 22 * v, offset: Offset(0, 6 * v), spreadRadius: 1.5 * v)],
        ),
        child: child,
      ),
    );
  }
}
