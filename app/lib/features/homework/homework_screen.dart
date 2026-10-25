// Экран «ДЗ»: разделы «Просрочено / На сегодня / На завтра / На этой неделе / Позже / Выполнено».
// Свайп вправо — выполнено, влево — удалить (то же есть кнопками: флажок слева и меню действий).


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../core/formatting.dart';
import '../../domain/homework.dart';
import '../../domain/models.dart';
import '../../domain/search.dart' show teacherFullName;
import '../../theme/tokens.dart';
import '../common/word_fit_text.dart';
import '../common/reveal.dart';
import '../common/sliding_segments.dart';
import '../../data/remote/shared_api.dart';
import '../../domain/group_shared.dart';
import '../../group_actions.dart';
import 'attachment_widgets.dart';
import '../common/empty_state.dart';
import '../common/illustrations.dart';
import 'add_homework_sheet.dart';

/// Вкладки экрана «ДЗ» у студента.
enum _Tab { mine, group, teacher }

class HomeworkScreen extends ConsumerStatefulWidget {
  const HomeworkScreen({super.key});

  @override
  ConsumerState<HomeworkScreen> createState() => _HomeworkScreenState();
}

class _HomeworkScreenState extends ConsumerState<HomeworkScreen> {
  _Tab _tab = _Tab.mine;

  @override
  Widget build(BuildContext context) {
    // Со значка ДЗ на паре: открыть раздел нужного источника (если такого раздела нет, ниже останется «Мои»)
    ref.listen(requestedHomeworkSourceProvider, (_, source) {
      if (source == null) return;
      setState(() => _tab = switch (source) {
            HomeworkSource.mine => _Tab.mine,
            HomeworkSource.headman => _Tab.group,
            HomeworkSource.teacher => _Tab.teacher,
          });
      ref.read(requestedHomeworkSourceProvider.notifier).clear();
    });
    final homework = ref.watch(homeworkProvider);
    final today = ref.watch(todayProvider);
    final theme = Theme.of(context);

    // Вкладка «Староста» есть, если староста что-то задал или это сам староста
    final isEditor = ref.watch(isGroupEditorProvider);
    // Студент видит ДЗ для всей группы и для своей подгруппы; староста — все, чтобы мог управлять любым
    final groupRows = ref.watch(isEditor ? groupHomeworkAllProvider : groupHomeworkProvider);
    final hasGroupTab = ref.watch(sharedApiProvider) != null && ref.watch(settingsProvider.select((s) => s.showGroupData)) && (groupRows.isNotEmpty || isEditor);
    // Вкладка «Преподаватели» есть, если преподаватели что-то задали (видно ДЗ для всей группы и для своей подгруппы)
    final teacherRows = ref.watch(teacherHomeworkProvider);
    final hasTeacherTab = ref.watch(sharedApiProvider) != null && ref.watch(settingsProvider.select((s) => s.showGroupData)) && teacherRows.isNotEmpty;
    final anyTab = hasGroupTab || hasTeacherTab;
    final tab = (_tab == _Tab.group && hasGroupTab) || (_tab == _Tab.teacher && hasTeacherTab) ? _tab : _Tab.mine;
    final showGroup = tab == _Tab.group;
    final showTeacher = tab == _Tab.teacher;
    final showShared = showGroup || showTeacher; // ДЗ с сервера (староста или преподаватели)

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddHomework(context, forGroup: tab == _Tab.group), // из вкладки «Староста» — сразу для всей группы
        icon: const Icon(Icons.add_rounded),
        label: const Text('Добавить ДЗ'),
      ),
      body: homework.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Не удалось прочитать ДЗ', subtitle: '$e'),
        data: (items) {
          if (items.isEmpty && !anyTab) {
            return const EmptyState(
              illustration: IllustrationKind.noHomework,
              title: 'Домашки нет',
              subtitle: 'Задание можно добавить кнопкой «Добавить ДЗ» или нажатием на пару на экране «Сегодня».',
            );
          }

          // Список для выбранной вкладки: личные ДЗ или ДЗ старосты (приведены к одному виду для разбивки по срокам)
          final done = ref.watch(groupHomeworkDoneProvider);
          final shownItems = <HomeworkItem>[];
          final rowOf = Map<HomeworkItem, GroupHomeworkRow>.identity();
          if (showShared) {
            for (final g in (showTeacher ? teacherRows : groupRows)) {
              final item = HomeworkItem(subject: g.subject, text: g.text, dueDate: g.dueDate, kind: g.kind, done: done.contains(g.id), createdAt: g.dueDate);
              shownItems.add(item);
              rowOf[item] = g;
            }
          } else {
            shownItems.addAll(items);
          }
          final groups = groupHomework(shownItems, today);
          final open = shownItems.where((i) => !i.done).length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 104),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                child: Text('Домашка', style: theme.textTheme.headlineMedium),
              ),
              if (anyTab) ...[
                const SizedBox(height: Gap.sm),
                SlidingSegments<_Tab>(
                  proportional: true,
                  segments: [
                    Segment(_Tab.mine, 'Мои (${items.where((i) => !i.done).length})'),
                    if (hasGroupTab) Segment(_Tab.group, 'Староста (${groupRows.where((g) => !done.contains(g.id)).length})', icon: Icons.groups_rounded),
                    if (hasTeacherTab) Segment(_Tab.teacher, 'Преподаватели (${teacherRows.where((g) => !done.contains(g.id)).length})', icon: Icons.school_rounded),
                  ],
                  selected: tab,
                  onChanged: (v) => setState(() => _tab = v),
                ),
              ],
              const SizedBox(height: Gap.sm),
              // Ключ по вкладке: при переключении «Мои / Староста» карточки появляются заново волной
              KeyedSubtree(
                key: ValueKey(tab),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                      child: Text(
                        shownItems.isEmpty ? '' : (open == 0 ? 'Всё сделано' : 'Не сделано: $open'),
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    if (shownItems.isEmpty)
                      // как пустой день на «Сегодня»: рисунок, заголовок и пояснение по центру свободного места
                      SizedBox(
                        height: (MediaQuery.sizeOf(context).height - 330).clamp(300.0, 640.0),
                        child: EmptyState(
                          illustration: showShared ? IllustrationKind.groupHomework : IllustrationKind.noHomework,
                          title: showTeacher ? 'Преподаватели пока ничего не задали' : showGroup ? 'Староста пока ничего не задал' : 'Домашки нет',
                          subtitle: showTeacher
                              ? 'Когда преподаватель отправит задание, оно появится здесь.'
                              : showGroup
                                  ? 'Когда староста добавит задание, оно появится здесь.'
                                  : 'Задание можно добавить кнопкой «Добавить ДЗ» или нажатием на пару на экране «Сегодня».',
                        ),
                      ),
                    for (final (n, entry) in groups.entries.indexed) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.xl, Gap.xs, Gap.sm),
                        child: Row(children: [
                          if (entry.key == HomeworkBucket.overdue) ...[
                            Icon(Icons.error_rounded, size: 18, color: theme.colorScheme.error),
                            const SizedBox(width: Gap.xs),
                          ],
                          Text(
                            entry.key.title,
                            style: theme.textTheme.titleSmall?.copyWith(color: entry.key == HomeworkBucket.overdue ? theme.colorScheme.error : null),
                          ),
                          const SizedBox(width: Gap.sm),
                          // число — в маленькой плашке: сразу видно, сколько заданий в разделе
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 1),
                            decoration: BoxDecoration(
                              color: entry.key == HomeworkBucket.overdue ? theme.colorScheme.errorContainer : theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${entry.value.length}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: entry.key == HomeworkBucket.overdue ? theme.colorScheme.onErrorContainer : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ]),
                      ),
                      for (final (k, item) in entry.value.indexed)
                        Reveal(
                          key: ValueKey('rv-${showShared ? rowOf[item]!.id : item.id}'),
                          index: n + k,
                          child: showShared ? _GroupHomeworkTile(row: rowOf[item]!, done: item.done, canEdit: isEditor && showGroup, fromTeacher: showTeacher) : _HomeworkTile(item: item),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// ДЗ, которое задал староста: отметить «сделано» можно у себя, удалить для всех — только староста.
class _GroupHomeworkTile extends ConsumerWidget {
  const _GroupHomeworkTile({required this.row, required this.done, required this.canEdit, this.fromTeacher = false});
  final GroupHomeworkRow row;
  final bool done;
  final bool canEdit;
  final bool fromTeacher; // ДЗ задал преподаватель (а не староста)

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final styles = ref.watch(subjectStylesProvider);
    final tone = styles.tone(row.subject, theme.brightness);

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Material(
        color: done ? scheme.surfaceContainerLow : tone.container,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
        clipBehavior: Clip.antiAlias,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.base),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: done ? scheme.outlineVariant : tone.accent, width: 6))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(left: Gap.xs),
              child: Semantics(
                label: done ? 'Выполнено. Нажмите, чтобы вернуть' : 'Отметить выполненным',
                child: _CheckPop(
                  done: done,
                  child: Checkbox(
                  value: done,
                  shape: const CircleBorder(),
                  side: BorderSide(color: tone.accent, width: 2),
                  activeColor: tone.accent,
                  onChanged: (_) {
                    done ? HapticFeedback.selectionClick() : HapticFeedback.lightImpact();
                    ref.read(groupHomeworkDoneProvider.notifier).toggle(row.id);
                  },
                ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, Gap.md, Gap.xs, Gap.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  WordFitText(
                    styles.name(row.subject),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: done ? scheme.onSurfaceVariant : tone.onContainer,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(row.text, style: theme.textTheme.bodyLarge?.copyWith(color: done ? scheme.onSurfaceVariant : scheme.onSurface)),
                  const SizedBox(height: Gap.sm),
                  Wrap(spacing: Gap.sm, runSpacing: Gap.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Icon(Icons.event_rounded, size: 16, color: scheme.onSurfaceVariant),
                    Text(
                      'к ${dateText(row.dueDate)}${row.kind == null ? '' : ' · ${row.kind!.title.toLowerCase()}'}',
                      style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 2),
                      decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        fromTeacher ? 'от преподавателя${row.author == null ? '' : ': ${teacherFullName(row.author!, ref.watch(indexProvider).value?.teachers ?? const [])}'}' : 'от старосты',
                        style: theme.textTheme.labelSmall?.copyWith(color: scheme.onTertiaryContainer),
                      ),
                    ),
                    if (row.subgroup != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 2),
                        decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          'для ${_subgroupLabel(ref, row.subgroup!)}',
                          style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSecondaryContainer),
                        ),
                      ),
                  ]),
                  GroupAttachmentStrip(files: row.files, color: tone.accent),
                ]),
              ),
            ),
            if (canEdit)
              IconButton(
                tooltip: 'Удалить для всей группы',
                icon: Icon(Icons.delete_outline_rounded, color: scheme.onSurfaceVariant),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await GroupEditorActions.of(context).deleteHomework(row.id);
                  } on SharedApiException catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text(e.message)));
                  }
                },
              ),
          ]),
        ),
      ),
    );
  }
}

/// Название подгруппы из расписания («БИ-25-1»); если не нашлось — «подгруппы 2».
String _subgroupLabel(WidgetRef ref, int n) {
  final subgroups = ref.watch(myScheduleProvider).value?.schedule.subgroups ?? const <SubgroupInfo>[];
  for (final s in subgroups) {
    if (s.n == n) return s.label;
  }
  return 'подгруппы $n';
}

class _HomeworkTile extends ConsumerWidget {
  const _HomeworkTile({required this.item});
  final HomeworkItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final repo = ref.read(homeworkRepositoryProvider);
    final styles = ref.watch(subjectStylesProvider);
    final tone = styles.tone(item.subject, theme.brightness);

    Future<void> toggle() async {
      // лёгкая вибрация: при отметке «сделано» — щелчок, при возврате — слабее
      item.done ? HapticFeedback.selectionClick() : HapticFeedback.lightImpact();
      await repo.setDone(item.id!, !item.done);
      ref.invalidate(homeworkProvider);
    }

    Future<void> remove() async {
      await repo.delete(item.id!);
      ref.invalidate(homeworkProvider);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Dismissible(
        key: ValueKey('hw-${item.id}'),
        background: _swipeBackground(context, Icons.check_rounded, 'Выполнено', Alignment.centerLeft, scheme.primaryContainer, scheme.onPrimaryContainer),
        secondaryBackground: _swipeBackground(context, Icons.delete_outline_rounded, 'Удалить', Alignment.centerRight, scheme.errorContainer, scheme.onErrorContainer),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            await toggle();
          } else {
            await remove();
          }
          return false; // список перерисуется сам
        },
        child: Material(
          color: item.done ? scheme.surfaceContainerLow : tone.container,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
          clipBehavior: Clip.antiAlias,
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.base),
            // цветная полоса слева — граница карточки (без IntrinsicHeight, внутри есть LayoutBuilder)
            decoration: BoxDecoration(border: Border(left: BorderSide(color: item.done ? scheme.outlineVariant : tone.accent, width: 6))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(left: Gap.xs),
                child: Semantics(
                  label: item.done ? 'Выполнено. Нажмите, чтобы вернуть' : 'Отметить выполненным',
                  child: _CheckPop(
                    done: item.done,
                    child: Checkbox(
                      value: item.done,
                      shape: const CircleBorder(),
                      side: BorderSide(color: tone.accent, width: 2),
                      activeColor: tone.accent,
                      onChanged: (_) => toggle(),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, Gap.md, Gap.xs, Gap.md),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    WordFitText(
                      styles.name(item.subject),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: item.done ? scheme.onSurfaceVariant : tone.onContainer,
                        decoration: item.done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: Gap.xs),
                    Text(item.text, style: theme.textTheme.bodyLarge?.copyWith(color: item.done ? scheme.onSurfaceVariant : scheme.onSurface)),
                    const SizedBox(height: Gap.sm),
                    Row(children: [
                      Icon(Icons.event_rounded, size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: Gap.xs),
                      Flexible(
                        child: Text(
                          'к ${dateText(item.dueDate)}${item.kind == null ? '' : ' · ${item.kind!.title.toLowerCase()}'}',
                          style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ]),
                    AttachmentStrip(attachments: item.attachments, color: tone.accent),
                  ]),
                ),
              ),
              // Кнопка вместо скрытых свайпов: «Удалить» доступно и без жестов
              PopupMenuButton<String>(
                tooltip: 'Действия с заданием',
                icon: Icon(Icons.more_vert_rounded, color: scheme.onSurfaceVariant),
                onSelected: (v) => v == 'delete' ? remove() : toggle(),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'toggle', child: Text(item.done ? 'Вернуть в невыполненные' : 'Отметить выполненным')),
                  const PopupMenuItem(value: 'delete', child: Text('Удалить')),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _swipeBackground(BuildContext context, IconData icon, String label, Alignment alignment, Color color, Color onColor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
        alignment: alignment,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Radii.lg)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: onColor),
          const SizedBox(width: Gap.sm),
          Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: onColor)),
        ]),
      );
}

/// Когда задание отмечают выполненным, кружок на мгновение «хлопает» (чуть увеличивается и возвращается).
class _CheckPop extends StatefulWidget {
  const _CheckPop({required this.done, required this.child});
  final bool done;
  final Widget child;

  @override
  State<_CheckPop> createState() => _CheckPopState();
}

class _CheckPopState extends State<_CheckPop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(_CheckPop old) {
    super.didUpdateWidget(old);
    if (widget.done && !old.done && !MediaQuery.disableAnimationsOf(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        // 1 → 1,3 → 1: быстрый подъём и мягкий возврат
        scale: TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
          TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 70),
        ]).animate(_c),
        child: widget.child,
      );
}
