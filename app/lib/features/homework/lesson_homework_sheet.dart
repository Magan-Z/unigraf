// Окно «Домашнее задание к паре»: все задания по этому предмету на этот день из трёх источников
// (преподаватель, староста, ваше), у каждого своя метка. Можно отметить выполненным по одному или сразу всё.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../core/formatting.dart';
import '../../domain/homework.dart';
import '../../domain/lesson_homework.dart';
import '../../domain/models.dart';
import '../../theme/tokens.dart';

Future<void> showLessonHomework(BuildContext context, ResolvedLesson lesson) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _LessonHomeworkSheet(lesson: lesson),
  );
}

class _LessonHomeworkSheet extends ConsumerWidget {
  const _LessonHomeworkSheet({required this.lesson});
  final ResolvedLesson lesson;

  Future<void> _setDone(WidgetRef ref, HomeworkItem item, bool done) async {
    if (item.done == done) return;
    if (item.sharedId != null) {
      await ref.read(groupHomeworkDoneProvider.notifier).toggle(item.sharedId!);
    } else if (item.id != null) {
      await ref.read(homeworkRepositoryProvider).setDone(item.id!, done);
      ref.invalidate(homeworkProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final all = ref.watch(homeworkWithGroupProvider).value ?? const <HomeworkItem>[];
    final items = homeworkForLesson(all, subject: lesson.subject, day: lesson.date, kind: lesson.kind);
    final styles = ref.watch(subjectStylesProvider);
    final summary = LessonHomework(items);

    // Всё удалили (например, староста убрал задание): окну нечего показывать
    if (items.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox(height: 120);
    }

    void openInHomework() {
      final first = items.firstWhere((i) => !i.done, orElse: () => items.first);
      Navigator.of(context).pop();
      ref.read(requestedHomeworkSourceProvider.notifier).request(first.source);
      ref.read(requestedTabProvider.notifier).request(2);
    }

    Future<void> setAll(bool done) async {
      done ? HapticFeedback.lightImpact() : HapticFeedback.selectionClick();
      for (final i in items) {
        await _setDone(ref, i, done);
      }
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(styles.name(lesson.subject), style: theme.textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                'ДЗ на ${dateText(lesson.date)}'
                '${items.length > 1 ? ' · ${items.length} ${plural(items.length, 'задание', 'задания', 'заданий')}' : ''}',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ]),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
              itemCount: items.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: scheme.outlineVariant),
              itemBuilder: (context, i) => _ItemRow(item: items[i], onChanged: (v) {
                v ? HapticFeedback.lightImpact() : HapticFeedback.selectionClick();
                _setDone(ref, items[i], v);
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.md, Gap.lg, Gap.md),
            // Wrap, а не Row: на узком экране или при крупном шрифте кнопки переходят на вторую строку, а не вылезают за край
            child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: Gap.sm, runSpacing: Gap.xs, children: [
              FilledButton.tonalIcon(
                onPressed: () => setAll(!summary.allDone),
                icon: Icon(summary.allDone ? Icons.undo_rounded : Icons.done_all_rounded, size: 20),
                label: Text(summary.allDone ? 'Снять отметки' : (items.length > 1 ? 'Всё выполнено' : 'Выполнено')),
              ),
              TextButton(onPressed: openInHomework, child: const Text('Открыть в «ДЗ»')),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onChanged});
  final HomeworkItem item;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (bg, fg, icon) = switch (item.source) {
      HomeworkSource.teacher => (scheme.primaryContainer, scheme.onPrimaryContainer, Icons.school_rounded),
      HomeworkSource.headman => (scheme.tertiaryContainer, scheme.onTertiaryContainer, Icons.groups_rounded),
      HomeworkSource.mine => (scheme.secondaryContainer, scheme.onSecondaryContainer, Icons.person_rounded),
    };
    final author = item.author;
    return Semantics(
      container: true,
      label: '${item.source.title}${author != null ? ', $author' : ''}. ${item.text}. ${item.done ? 'Выполнено' : 'Не выполнено'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: Gap.xs),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: Gap.sm, runSpacing: Gap.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.sm - 4)),
                    // при самом крупном шрифте метка слегка сжимается, а не вылезает за край
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(icon, size: 15, color: fg),
                        const SizedBox(width: Gap.xs),
                        Text(item.source.title, style: theme.textTheme.labelMedium?.copyWith(color: fg)),
                      ]),
                    ),
                  ),
                  if (author != null) Text(author, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ]),
                const SizedBox(height: Gap.sm),
                Text(
                  item.text,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: item.done ? scheme.onSurfaceVariant : scheme.onSurface,
                    decoration: item.done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ]),
            ),
          ),
          Checkbox(
            value: item.done,
            shape: const CircleBorder(),
            onChanged: (v) => onChanged(v ?? !item.done),
          ),
        ]),
      ),
    );
  }
}
