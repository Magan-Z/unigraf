// Личные правки расписания: действия над парой (нажатие на пару) и список «Мои правки на этот день».
// Объявили небольшое изменение — аудитория другая, пару переставили, отменили — не нужно ждать нового
// файла расписания: можно поправить самому, на один день или на каждую неделю.
// Правки живут только на телефоне. Они учитываются в «Сегодня», «Неделе», виджетах и уведомлениях.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../core/formatting.dart';
import '../../domain/assessments.dart';
import '../../domain/group_shared.dart';
import '../../domain/models.dart';
import '../../domain/overrides_text.dart';
import '../../domain/pair_suggestions.dart';
import '../../domain/search.dart' show teacherFullName;
import '../../theme/tokens.dart';
import '../../data/remote/shared_api.dart';
import '../../group_actions.dart';
import '../common/suggest_field.dart';
import 'announce_dialog.dart';
import '../homework/add_homework_sheet.dart';
import '../settings/subject_style_editor.dart';

/// Подсказки для окон «Изменить пару» и «Своя пара»: из расписания группы и (если уже загружено) всего института.
PairSuggestions _suggestionsFrom(ProviderContainer container) {
  final data = container.read(myScheduleProvider).value;
  if (data == null) return PairSuggestions.empty;
  return PairSuggestions.build(
    own: data.schedule,
    others: container.read(allGroupsProvider).value ?? const [],
    directory: data.index.teachers,
  );
}

/// Окно «Объявить аттестацию / зачёт / экзамен» для нажатой пары. [forGroup] — староста объявляет всей своей подгруппе.
Future<Override?> _askAnnounce(BuildContext context, ProviderContainer container, ResolvedLesson lesson, {required bool forGroup}) {
  final data = container.read(myScheduleProvider).value;
  final ahead = data == null
      ? const <ResolvedLesson>[]
      : sameLessonsAhead(from: lesson, index: data.index, schedule: data.schedule, profile: data.profile, overrides: data.overrides, forcedWeek: data.forcedWeek);
  final options = [lesson, ...ahead];
  // нажали на сегодняшнюю или прошедшую пару — объявление, скорее всего, про следующую; на будущую — про неё саму
  final initial = lesson.date.isAfter(container.read(todayProvider)) || ahead.isEmpty ? 0 : 1;
  String? hint;
  if (forGroup && data != null && data.schedule.subgroups.isNotEmpty) {
    final mine = [for (final s in data.schedule.subgroups) if (s.n == data.profile.subgroup) s.label];
    hint = 'Объявление увидит ${mine.isEmpty ? 'ваша подгруппа' : 'ваша подгруппа (${mine.first})'}. '
        'Чтобы объявить для всей группы, добавьте экзамен через «Добавить пару».';
  }
  return showDialog<Override>(
    context: context,
    builder: (_) => AnnounceDialog(lesson: lesson, options: options, initial: initial, forGroup: forGroup, groupHint: hint),
  );
}

/// Нажатие на пару: что с ней можно сделать.
Future<void> showLessonActions(BuildContext context, ResolvedLesson lesson) {
  // Меню закрывается раньше, чем заканчивается действие, поэтому всё нужное берём заранее у внешнего контекста
  final container = ProviderScope.containerOf(context);
  final repo = container.read(overridesRepositoryProvider);
  final overrides = container.read(overridesProvider).value ?? const <Override>[];
  final rulesForThisPair = [for (final o in overrides) if (o.appliesOn(lesson.date) && o.pair == lesson.pair) o];
  final hasRepeatingRule = rulesForThisPair.any((o) => o.repeatWeekly);
  // Полное ФИО преподавателя из справочника института (если там есть), иначе как в расписании
  final directory = container.read(indexProvider).value?.teachers ?? const <String>[];
  final teacherName = lesson.teacher == null ? null : teacherFullName(lesson.teacher!, directory);

  Future<void> save(List<Override> items) async {
    for (final o in items) {
      await repo.save(o);
    }
    container.invalidate(overridesProvider);
  }

  // Староста: те же действия, но для всей группы (уходят на сервер и видны всем)
  final isEditor = container.read(isGroupEditorProvider);
  // Преподаватель: пары приходят из расписания групп, личные правки в версии 1 не поддерживаются
  final isTeacher = container.read(isTeacherModeProvider);
  Future<void> saveForGroup(List<Override> items) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await GroupEditorActions(container).saveOverrides(items);
      messenger.showSnackBar(const SnackBar(content: Text('Сохранено для всей группы')));
    } on SharedApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> removeGroupEdits() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await GroupEditorActions(container).removeLessonEdits(lesson);
      messenger.showSnackBar(const SnackBar(content: Text('Правка старосты убрана для всей группы')));
    } on SharedApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      void close() => Navigator.of(sheetContext).pop();
      final theme = Theme.of(sheetContext);

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: Text(lesson.subject, style: theme.textTheme.titleMedium),
              subtitle: Text('${dayTitle(lesson.date)}, ${lesson.pair} пара'),
            ),
            if (teacherName != null)
              ListTile(
                leading: Icon(isTeacher ? Icons.groups_rounded : Icons.person_rounded),
                title: Text(teacherName),
                subtitle: Text(isTeacher ? 'Группы' : 'Преподаватель'),
              ),
            if (lesson.withGroups.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.groups_rounded),
                title: Text(lesson.kind == LessonKind.lecture ? 'Лекция вместе с группами' : 'Пара вместе с группами'),
                subtitle: Text(lesson.withGroups.join(', ')),
              ),
            ListTile(
              leading: Icon(isTeacher ? Icons.send_rounded : Icons.assignment_add),
              title: Text(isTeacher ? 'Отправить ДЗ студентам' : 'Добавить ДЗ'),
              onTap: () {
                close();
                showAddHomework(context, subject: lesson.subject);
              },
            ),
            ListTile(
              leading: const Icon(Icons.color_lens_rounded),
              title: const Text('Название и цвет'),
              subtitle: const Text('Своё короткое название и цвет предмета'),
              onTap: () {
                close();
                showSubjectStyleEditor(context, lesson.subject);
              },
            ),
            if (!isTeacher) ...[
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Изменить'),
              subtitle: const Text('Другая аудитория, преподаватель или заметка'),
              onTap: () async {
                close();
                final suggestions = _suggestionsFrom(container);
                final changed = await showDialog<Override>(context: context, builder: (_) => _ReplaceDialog(lesson: lesson, suggestions: suggestions));
                if (changed != null) await save([changed]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_rounded),
              title: const Text('Перенести'),
              subtitle: const Text('На другую пару или в другой день'),
              onTap: () async {
                close();
                final move = await showDialog<_Move>(context: context, builder: (_) => _MoveDialog(lesson: lesson));
                if (move == null) return;
                // Если пара уже была изменена вами, сначала убираем эти правки (новое место получит её текущие данные)
                await repo.clearPair(lesson.date, lesson.pair);
                await save([
                  Override(
                    date: lesson.date,
                    pair: lesson.pair,
                    type: OverrideType.cancel,
                    repeatWeekly: move.repeat,
                    matchSubject: move.repeat ? lesson.subject : null,
                  ),
                  Override(
                    date: move.date,
                    pair: move.pair,
                    type: OverrideType.add,
                    subject: lesson.subject,
                    teacher: lesson.teacher,
                    room: lesson.room,
                    kind: lesson.kind,
                    note: 'перенесено',
                    repeatWeekly: move.repeat,
                  ),
                ]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_busy_rounded),
              title: const Text('Отменить пару'),
              subtitle: const Text('Только у вас, на этот день'),
              onTap: () async {
                close();
                await save([Override(date: lesson.date, pair: lesson.pair, type: OverrideType.cancel)]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_repeat_rounded),
              title: const Text('Отменить каждую неделю'),
              subtitle: Text('С ${dateText(lesson.date)} и далее по каждому дню недели «${weekdayNames[lesson.date.weekday]}»'),
              onTap: () async {
                close();
                await save([
                  Override(date: lesson.date, pair: lesson.pair, type: OverrideType.cancel, repeatWeekly: true, matchSubject: lesson.subject),
                ]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.quiz_rounded),
              title: const Text('Отметить аттестацию или экзамен'),
              subtitle: const Text('Аттестация, зачёт, экзамен — только у вас'),
              onTap: () async {
                close();
                final announced = await _askAnnounce(context, container, lesson, forGroup: false);
                if (announced != null) await save([announced]);
              },
            ),
            if (lesson.isPersonal || rulesForThisPair.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.undo_rounded),
                title: const Text('Вернуть как было'),
                subtitle: hasRepeatingRule ? const Text('Правка действует каждую неделю — она будет убрана для всех недель') : null,
                onTap: () async {
                  close();
                  await repo.clearPair(lesson.date, lesson.pair);
                  for (final rule in rulesForThisPair.where((o) => o.repeatWeekly)) {
                    await repo.delete(rule.id!);
                  }
                  container.invalidate(overridesProvider);
                },
              ),
            if (isEditor) ...[
              const Divider(),
              ListTile(
                dense: true,
                leading: Icon(Icons.groups_rounded, color: theme.colorScheme.primary),
                title: Text('Для всей группы (вы староста)', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
              ),
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('Изменить для группы'),
                subtitle: const Text('Аудитория, преподаватель или заметка — у всех'),
                onTap: () async {
                  close();
                  final suggestions = _suggestionsFrom(container);
                final changed = await showDialog<Override>(context: context, builder: (_) => _ReplaceDialog(lesson: lesson, suggestions: suggestions));
                  if (changed != null) await saveForGroup([changed]);
                },
              ),
              ListTile(
                leading: const Icon(Icons.quiz_rounded),
                title: const Text('Объявить аттестацию, зачёт или экзамен'),
                subtitle: const Text('Для вашей подгруппы — у всех, кто в ней'),
                onTap: () async {
                  close();
                  final announced = await _askAnnounce(context, container, lesson, forGroup: true);
                  if (announced != null) await saveForGroup([announced]);
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_rounded),
                title: const Text('Перенести для группы'),
                onTap: () async {
                  close();
                  final move = await showDialog<_Move>(context: context, builder: (_) => _MoveDialog(lesson: lesson));
                  if (move == null) return;
                  await saveForGroup([
                    Override(
                      date: lesson.date,
                      pair: lesson.pair,
                      type: OverrideType.cancel,
                      repeatWeekly: move.repeat,
                      matchSubject: move.repeat ? lesson.subject : null,
                      // метка связывает отмену с новым местом пары: «убрать правку» возвращает пару на прежнее место
                      note: moveMark(move.date, move.pair),
                    ),
                    Override(
                      date: move.date,
                      pair: move.pair,
                      type: OverrideType.add,
                      subject: lesson.subject,
                      teacher: lesson.teacher,
                      room: lesson.room,
                      kind: lesson.kind,
                      note: movedNote,
                      repeatWeekly: move.repeat,
                    ),
                  ]);
                },
              ),
              ListTile(
                leading: const Icon(Icons.event_busy_rounded),
                title: const Text('Отменить пару для группы'),
                subtitle: const Text('На этот день, у всех'),
                onTap: () async {
                  close();
                  await saveForGroup([Override(date: lesson.date, pair: lesson.pair, type: OverrideType.cancel)]);
                },
              ),
              ListTile(
                leading: const Icon(Icons.event_repeat_rounded),
                title: const Text('Отменить для группы каждую неделю'),
                onTap: () async {
                  close();
                  await saveForGroup([
                    Override(date: lesson.date, pair: lesson.pair, type: OverrideType.cancel, repeatWeekly: true, matchSubject: lesson.subject),
                  ]);
                },
              ),
              if (lesson.isGroup)
                ListTile(
                  leading: const Icon(Icons.undo_rounded),
                  title: const Text('Убрать правку старосты'),
                  subtitle: const Text('Пара вернётся к расписанию — у всей группы'),
                  onTap: () async {
                    close();
                    await removeGroupEdits();
                  },
                ),
            ],
            ],
            const SizedBox(height: Gap.sm),
          ]),
        ),
      );
    },
  );
}

/// «Мои правки на этот день»: список правок (чтобы вернуть отменённую пару) и добавление своей пары.
Future<void> showDayEdits(BuildContext context, DateTime day) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _DayEditsSheet(day: day),
  );
}

class _DayEditsSheet extends ConsumerWidget {
  const _DayEditsSheet({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(overridesProvider).value ?? const [];
    final mine = [for (final o in all) if (o.appliesOn(day)) o];
    // Правки старосты для всей группы: видны всем, убрать их может староста
    final group = [for (final o in ref.watch(myScheduleProvider).value?.overrides ?? const <Override>[]) if (o.fromGroup && o.appliesOn(day)) o];
    final isEditor = ref.watch(isGroupEditorProvider);
    final repo = ref.read(overridesRepositoryProvider);
    final theme = Theme.of(context);

    Future<void> removeGroupEdit(Override o) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await GroupEditorActions.of(context).removeEdit(o.remoteId!);
      } on SharedApiException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Мои правки · ${dayTitle(day)}', style: theme.textTheme.titleLarge),
          const SizedBox(height: Gap.sm),
          if (mine.isEmpty && group.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.md),
              child: Text(
                'На этот день правок нет. Изменить, перенести или отменить пару можно нажатием на неё.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          for (final o in group)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(describeOverride(o)),
              subtitle: Text(o.repeatWeekly ? 'Правка старосты для всей группы · каждую неделю' : 'Правка старосты для всей группы'),
              trailing: isEditor
                  ? IconButton(
                      tooltip: 'Убрать правку для всей группы',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => removeGroupEdit(o),
                    )
                  : null,
            ),
          for (final o in mine)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(describeOverride(o)),
              subtitle: o.repeatWeekly ? const Text('Действует каждую неделю — при удалении уберётся для всех недель') : null,
              trailing: IconButton(
                tooltip: 'Убрать правку',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  await repo.delete(o.id!);
                  ref.invalidate(overridesProvider);
                },
              ),
            ),
          const SizedBox(height: Gap.md),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.add_rounded),
            label: Text(isEditor ? 'Добавить пару' : 'Добавить свою пару'),
            onPressed: () async {
              final suggestions = _suggestionsFrom(ProviderScope.containerOf(context));
              final messenger = ScaffoldMessenger.of(context);
              final actions = GroupEditorActions.of(context);
              final added = await showDialog<_NewPair>(context: context, builder: (_) => _AddPairDialog(day: day, suggestions: suggestions, canShareWithGroup: isEditor));
              if (added == null) return;
              if (!added.forGroup) {
                await repo.save(added.override);
                ref.invalidate(overridesProvider);
                return;
              }
              try {
                await actions.saveOverrides([added.override]);
                messenger.showSnackBar(const SnackBar(content: Text('Сохранено для всей группы')));
              } on SharedApiException catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(e.message)));
              }
            },
          ),
        ]),
      ),
    );
  }
}

/// Переключатель «Каждую неделю» с пояснением.
class _RepeatSwitch extends StatelessWidget {
  const _RepeatSwitch({required this.day, required this.value, required this.onChanged});
  final DateTime day;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Каждую неделю'),
      subtitle: Text('С ${dateText(day)} и далее по каждому дню недели «${weekdayNames[day.weekday]}», пока идёт семестр'),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _ReplaceDialog extends StatefulWidget {
  const _ReplaceDialog({required this.lesson, this.suggestions = PairSuggestions.empty});
  final ResolvedLesson lesson;
  final PairSuggestions suggestions;

  @override
  State<_ReplaceDialog> createState() => _ReplaceDialogState();
}

class _ReplaceDialogState extends State<_ReplaceDialog> {
  late final _room = TextEditingController(text: widget.lesson.room ?? '');
  late final _teacher = TextEditingController(text: widget.lesson.teacher ?? '');
  late final _note = TextEditingController(text: widget.lesson.isPersonal ? (widget.lesson.note ?? '') : '');
  bool _repeat = false;

  @override
  void dispose() {
    _room.dispose();
    _teacher.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.lesson;
    return AlertDialog(
      title: const Text('Изменить пару'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SuggestField(controller: _room, label: 'Аудитория', options: widget.suggestions.rooms),
          const SizedBox(height: Gap.md),
          SuggestField(controller: _teacher, label: 'Преподаватель', options: widget.suggestions.teachers),
          const SizedBox(height: Gap.md),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Заметка (например, «объявили в чате»)')),
          const SizedBox(height: Gap.sm),
          _RepeatSwitch(day: l.date, value: _repeat, onChanged: (v) => setState(() => _repeat = v)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            Override(
              date: l.date,
              pair: l.pair,
              type: OverrideType.replace,
              // Сохраняем только то, что действительно изменено
              room: _room.text.trim() == (l.room ?? '') ? null : blankToNull(_room.text),
              teacher: _teacher.text.trim() == (l.teacher ?? '') ? null : blankToNull(_teacher.text),
              note: blankToNull(_note.text),
              repeatWeekly: _repeat,
              matchSubject: _repeat ? l.subject : null,
            ),
          ),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

/// Куда перенести пару.
class _Move {
  const _Move({required this.date, required this.pair, required this.repeat});
  final DateTime date;
  final int pair;
  final bool repeat;
}

class _MoveDialog extends StatefulWidget {
  const _MoveDialog({required this.lesson});
  final ResolvedLesson lesson;

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  late DateTime _date = widget.lesson.date;
  late int _pair = widget.lesson.pair;
  bool _repeat = false;

  bool get _unchanged => _date == widget.lesson.date && _pair == widget.lesson.pair;

  @override
  Widget build(BuildContext context) {
    final l = widget.lesson;
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Перенести пару'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.subject, style: theme.textTheme.titleSmall),
          Text('Сейчас: ${dayTitle(l.date)}, ${l.pair} пара', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: Gap.lg),
          Text('Куда', style: theme.textTheme.labelLarge),
          const SizedBox(height: Gap.sm),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_rounded),
            label: Text(dayTitle(_date)),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: l.date.subtract(const Duration(days: 60)),
                lastDate: l.date.add(const Duration(days: 180)),
              );
              if (picked != null) setState(() => _date = DateTime.utc(picked.year, picked.month, picked.day));
            },
          ),
          const SizedBox(height: Gap.md),
          Wrap(spacing: Gap.sm, children: [
            for (var p = 1; p <= 5; p++) ChoiceChip(label: Text('$p пара'), selected: _pair == p, onSelected: (_) => setState(() => _pair = p)),
          ]),
          const SizedBox(height: Gap.sm),
          _RepeatSwitch(day: _date, value: _repeat, onChanged: (v) => setState(() => _repeat = v)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: _unchanged ? null : () => Navigator.pop(context, _Move(date: _date, pair: _pair, repeat: _repeat)),
          child: const Text('Перенести'),
        ),
      ],
    );
  }
}

/// Новая пара из окна «Своя пара»: сама правка и кому она видна.
class _NewPair {
  const _NewPair(this.override, {required this.forGroup});
  final Override override;
  final bool forGroup;
}

class _AddPairDialog extends StatefulWidget {
  const _AddPairDialog({required this.day, this.suggestions = PairSuggestions.empty, this.canShareWithGroup = false});
  final DateTime day;
  final PairSuggestions suggestions;

  /// Староста может добавить пару всей группе.
  final bool canShareWithGroup;

  @override
  State<_AddPairDialog> createState() => _AddPairDialogState();
}

class _AddPairDialogState extends State<_AddPairDialog> {
  final _subject = TextEditingController();
  final _room = TextEditingController();
  final _teacher = TextEditingController();
  final _note = TextEditingController();
  int _pair = 1;
  LessonKind _kind = LessonKind.practice;
  bool _repeat = false;
  late bool _forGroup = widget.canShareWithGroup;

  @override
  void dispose() {
    _subject.dispose();
    _room.dispose();
    _teacher.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Один раз в неделю повторять экзамен или аттестацию незачем
    final canRepeat = !_kind.isAssessment;
    return AlertDialog(
      title: Text(widget.canShareWithGroup ? 'Новая пара' : 'Своя пара'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Номер пары'),
          const SizedBox(height: Gap.sm),
          Wrap(spacing: Gap.sm, children: [
            for (var p = 1; p <= 5; p++) ChoiceChip(label: Text('$p'), selected: _pair == p, onSelected: (_) => setState(() => _pair = p)),
          ]),
          const SizedBox(height: Gap.md),
          Wrap(spacing: Gap.sm, runSpacing: Gap.xs, children: [
            for (final k in [LessonKind.lecture, LessonKind.practice, ...announceKinds])
              ChoiceChip(label: Text(k.title), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
          ]),
          const SizedBox(height: Gap.md),
          SuggestField(controller: _subject, label: 'Название', options: widget.suggestions.subjects, onChanged: () => setState(() {})),
          const SizedBox(height: Gap.md),
          SuggestField(controller: _room, label: 'Аудитория', options: widget.suggestions.rooms),
          const SizedBox(height: Gap.md),
          SuggestField(controller: _teacher, label: 'Преподаватель', options: widget.suggestions.teachers),
          const SizedBox(height: Gap.md),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Заметка')),
          if (canRepeat) ...[
            const SizedBox(height: Gap.sm),
            _RepeatSwitch(day: widget.day, value: _repeat, onChanged: (v) => setState(() => _repeat = v)),
          ],
          if (widget.canShareWithGroup)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Для всей группы'),
              subtitle: Text(_forGroup ? 'Увидят все студенты группы, обе подгруппы' : 'Только у вас на телефоне'),
              value: _forGroup,
              onChanged: (v) => setState(() => _forGroup = v),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: _subject.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _NewPair(
                      Override(
                        date: widget.day,
                        pair: _pair,
                        type: OverrideType.add,
                        subject: _subject.text.trim(),
                        room: blankToNull(_room.text),
                        teacher: blankToNull(_teacher.text),
                        note: blankToNull(_note.text),
                        kind: _kind,
                        repeatWeekly: canRepeat && _repeat,
                      ),
                      forGroup: widget.canShareWithGroup && _forGroup,
                    ),
                  ),
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}
