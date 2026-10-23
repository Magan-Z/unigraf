// Окно «Отправить ДЗ студентам» (преподаватель): предмет, группы, текст, срок, файлы.
// Группы для каждого предмета берутся из расписания преподавателя; сервер дополнительно проверяет, что они входят в его список.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../core/formatting.dart';
import '../../data/attachments/attachment_store.dart';
import '../../data/attachments/group_files.dart';
import '../../data/remote/shared_api.dart';
import '../../domain/attachment.dart';
import '../../domain/group_shared.dart';
import '../../domain/homework_due.dart';
import '../../domain/models.dart';
import '../../domain/teacher.dart';
import '../../domain/teacher_homework.dart';
import '../../teacher_actions.dart';
import '../../theme/tokens.dart';
import '../homework/attachment_widgets.dart';
import 'teacher_code_dialog.dart';

/// Открывает окно отправки. [subject] — предмет, если известен (нажатие на пару); [editing] — изменить прежнюю отправку.
/// Если кода преподавателя ещё нет, сначала просит его ввести.
Future<void> showTeacherHomeworkSheet(BuildContext context, {String? subject, TeacherHomeworkBatch? editing}) async {
  final container = ProviderScope.containerOf(context);
  if (container.read(teacherSessionProvider) == null) {
    final got = await showTeacherCodeDialog(context);
    if (got == null || !context.mounted) return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _TeacherHomeworkSheet(initialSubject: subject, editing: editing),
  );
}

class _TeacherHomeworkSheet extends ConsumerStatefulWidget {
  const _TeacherHomeworkSheet({this.initialSubject, this.editing});
  final String? initialSubject;
  final TeacherHomeworkBatch? editing;

  @override
  ConsumerState<_TeacherHomeworkSheet> createState() => _TeacherHomeworkSheetState();
}

class _TeacherHomeworkSheetState extends ConsumerState<_TeacherHomeworkSheet> {
  late final _text = TextEditingController(text: widget.editing?.text ?? '');
  String? _subject;
  LessonKind? _kind;
  DateTime? _manualDue;
  Set<TeacherTarget>? _selected; // null — ещё не выбирали руками: по умолчанию все группы предмета
  final List<Attachment> _newFiles = [];
  late final List<GroupFileRef> _keepFiles = [...?widget.editing?.files];
  bool _saved = false;
  bool _busy = false;
  late final AttachmentStore _store;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _subject = e?.subject ?? widget.initialSubject;
    _kind = e?.kind;
    _manualDue = e?.dueDate;
    _store = ref.read(attachmentStoreProvider);
  }

  @override
  void dispose() {
    if (!_saved) {
      for (final f in _newFiles) {
        _store.delete(f);
      }
    }
    _text.dispose();
    super.dispose();
  }

  void _say(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Группы предмета, которым преподавателю разрешено отправлять (по списку из кода).
  List<TeacherTarget> _allowed(TeacherView view, TeacherSession session, String subject, Map<String, String> titles) {
    final fromSchedule = [for (final t in view.targetsBySubject[subject] ?? const <TeacherTarget>[]) if (session.groups.contains(t.groupId)) t];
    // При изменении старой отправки показываем и те группы, куда она уже ушла
    final extra = [
      for (final t in widget.editing?.targets ?? const <TeacherSentTarget>[])
        if (widget.editing!.subject == subject && !fromSchedule.any((x) => x.groupId == t.groupId && x.subgroup == t.subgroup))
          TeacherTarget(groupId: t.groupId, title: titles[t.groupId] ?? t.groupId, subgroup: t.subgroup),
    ];
    return [...fromSchedule, ...extra];
  }

  Set<TeacherTarget> _currentSelection(List<TeacherTarget> allowed) {
    if (_selected != null) return _selected!.where(allowed.contains).toSet();
    final e = widget.editing;
    if (e != null && e.subject == _subject) {
      return {for (final t in allowed) if (e.targets.any((x) => x.groupId == t.groupId && x.subgroup == t.subgroup)) t};
    }
    return allowed.toSet();
  }

  Future<void> _attach() async {
    final picker = ref.read(attachmentPickerProvider);
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Сфотографировать'), onTap: () => Navigator.pop(context, 'camera')),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Фото из галереи'), onTap: () => Navigator.pop(context, 'gallery')),
          ListTile(
            leading: const Icon(Icons.attach_file_rounded),
            title: const Text('Файл'),
            subtitle: const Text('PDF, документ, презентация, таблица…'),
            onTap: () => Navigator.pop(context, 'file'),
          ),
        ]),
      ),
    );
    if (source == null) return;
    try {
      final picked = switch (source) {
        'camera' => [?await picker.takePhoto()],
        'gallery' => await picker.pickImages(),
        _ => await picker.pickFiles(),
      };
      var skippedBig = 0, skippedMany = 0;
      for (final p in picked) {
        if (_newFiles.length + _keepFiles.length >= maxGroupFilesPerHomework) {
          skippedMany++;
          continue;
        }
        if ((p.sizeBytes ?? 0) > maxTeacherFileBytes) {
          skippedBig++;
          continue;
        }
        final saved = await _store.save(p);
        if (!mounted) return;
        setState(() => _newFiles.add(saved));
      }
      if (skippedBig > 0) _say('Файл больше ${maxTeacherFileBytes ~/ (1024 * 1024)} МБ не прикреплён');
      if (skippedMany > 0) _say('К одному заданию можно прикрепить не больше $maxGroupFilesPerHomework файлов');
    } catch (_) {
      _say('Не удалось выбрать файл. Проверьте разрешения приложения в настройках телефона.');
    }
  }

  Future<void> _send(DateTime due, Set<TeacherTarget> targets) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await TeacherActions.of(context).send(
        id: widget.editing?.id,
        subject: _subject!,
        text: _text.text.trim(),
        due: due,
        kind: _kind,
        targets: [for (final t in targets) TeacherSentTarget(groupId: t.groupId, subgroup: t.subgroup)],
        newFiles: _newFiles,
        keepFiles: _keepFiles,
      );
    } on SharedApiException catch (e) {
      if (mounted) setState(() => _busy = false);
      if (e.code == 'bad_token') await ref.read(teacherSessionProvider.notifier).clear();
      _say(e.message);
      return;
    }
    _saved = true;
    final n = targets.map((t) => t.groupId).toSet().length;
    messenger.showSnackBar(SnackBar(content: Text(widget.editing == null ? 'Отправлено: $n ${_groupsWord(n)}' : 'Изменено у студентов ($n ${_groupsWord(n)})')));
    if (mounted) Navigator.of(context).pop();
  }

  String _groupsWord(int n) => plural(n, 'группа', 'группы', 'групп');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final view = ref.watch(teacherViewProvider).value;
    final session = ref.watch(teacherSessionProvider);
    final data = ref.watch(myScheduleProvider).value;
    final today = ref.watch(todayProvider);
    if (view == null || session == null || data == null) {
      return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    }
    final titles = {for (final f in data.index.forms) for (final g in f.groups) g.id: g.title};

    // Предметы: свои пары; при изменении — ещё и предмет прежней отправки
    final subjects = {...view.subjects, if (widget.editing != null) widget.editing!.subject}.toList()..sort();
    final subject = _subject;
    final allowed = subject == null ? const <TeacherTarget>[] : _allowed(view, session, subject, titles);
    final selected = _currentSelection(allowed);
    final blocked = subject == null
        ? const <String>[]
        : [for (final t in view.targetsBySubject[subject] ?? const <TeacherTarget>[]) if (!session.groups.contains(t.groupId)) t.title];

    DateTime? due = _manualDue;
    if (due == null && subject != null) {
      due = nextOccurrence(subject, today, data.index, data.schedule, data.profile, kind: _kind);
    }
    final fileCount = _newFiles.length + _keepFiles.length;
    final canSend = subject != null && _text.text.trim().isNotEmpty && due != null && selected.isNotEmpty && !_busy;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.editing == null ? 'ДЗ студентам' : 'Изменить ДЗ', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Подпись для студентов: ${session.teacher}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            DropdownMenu<String>(
              key: ValueKey(_subject),
              expandedInsets: EdgeInsets.zero,
              label: const Text('Предмет'),
              initialSelection: _subject,
              enableFilter: true,
              dropdownMenuEntries: [for (final s in subjects) DropdownMenuEntry(value: s, label: s)],
              onSelected: (v) => setState(() {
                _subject = v;
                _selected = null;
                if (widget.editing == null || widget.editing!.subject != v) _manualDue = null;
              }),
            ),
            if (subject != null) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Text('Кому отправить', style: theme.textTheme.labelLarge)),
                TextButton(
                  onPressed: allowed.isEmpty ? null : () => setState(() => _selected = selected.length == allowed.length ? <TeacherTarget>{} : allowed.toSet()),
                  child: Text(selected.length == allowed.length ? 'Снять все' : 'Выбрать все'),
                ),
              ]),
              if (allowed.isEmpty)
                Text('Для этого предмета нет групп, которым вам разрешена отправка. Напишите автору приложения, чтобы их добавили.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))
              else
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final t in allowed)
                    FilterChip(
                      label: Text(t.label),
                      selected: selected.contains(t),
                      showCheckmark: false,
                      avatar: selected.contains(t) ? const Icon(Icons.check_rounded, size: 18) : null,
                      onSelected: (v) => setState(() => _selected = v ? {...selected, t} : ({...selected}..remove(t))),
                    ),
                ]),
              if (blocked.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.xs),
                  child: Text('Нет разрешения на отправку: ${blocked.join(', ')}. Напишите автору приложения.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 2,
              maxLines: 6,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Что задать', border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('К любому занятию'), selected: _kind == null, onSelected: (_) => setState(() => _kind = null)),
              ChoiceChip(label: const Text('К лекции'), selected: _kind == LessonKind.lecture, onSelected: (_) => setState(() => _kind = LessonKind.lecture)),
              ChoiceChip(label: const Text('К практике'), selected: _kind == LessonKind.practice, onSelected: (_) => setState(() => _kind = LessonKind.practice)),
            ]),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(due == null ? (subject == null ? 'Выберите предмет' : 'Занятий не найдено: выберите дату') : 'Срок: ${dayTitle(due)}'),
              subtitle: Text(_manualDue == null ? 'Подставлено автоматически: ближайшее ваше занятие' : 'Выбрано вручную'),
              trailing: TextButton(
                child: const Text('Изменить'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: due ?? today,
                    firstDate: today.subtract(const Duration(days: 30)),
                    lastDate: today.add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _manualDue = DateTime.utc(picked.year, picked.month, picked.day));
                },
              ),
            ),
            if (fileCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final f in _keepFiles)
                    AttachmentTile(attachment: f.asAttachment, onRemove: () => setState(() => _keepFiles.remove(f))),
                  for (final f in _newFiles)
                    AttachmentTile(
                      attachment: f,
                      onRemove: () {
                        _store.delete(f);
                        setState(() => _newFiles.remove(f));
                      },
                    ),
                ]),
              ),
            Row(children: [
              OutlinedButton.icon(
                onPressed: fileCount >= maxGroupFilesPerHomework || _busy ? null : _attach,
                icon: const Icon(Icons.attach_file_rounded),
                label: Text(fileCount == 0 ? 'Прикрепить' : 'Ещё ($fileCount)'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: canSend ? () => _send(due!, selected) : null,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.send_rounded, size: 18),
                label: Text(widget.editing == null ? 'Отправить' : 'Сохранить'),
              ),
            ]),
            const SizedBox(height: 4),
            Text('Файлы: до $maxGroupFilesPerHomework шт., каждый до ${maxTeacherFileBytes ~/ (1024 * 1024)} МБ.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
