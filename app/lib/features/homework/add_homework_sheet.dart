// Окно «Добавить ДЗ». Срок подставляется сам — следующее занятие этого предмета (АРХИТЕКТУРА.md, §8).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../data/remote/shared_api.dart';
import '../../group_actions.dart';
import '../../data/attachments/attachment_store.dart';
import '../../data/attachments/group_files.dart';
import '../../domain/attachment.dart';
import '../teacher/teacher_homework_sheet.dart';
import 'attachment_widgets.dart';
import '../../core/formatting.dart';
import '../../domain/homework.dart';
import '../../domain/homework_due.dart';
import '../../domain/models.dart';
import '../../domain/week_view.dart';
import '../../theme/tokens.dart';

/// Открывает окно добавления. [subject] — предмет, если уже известен (например, по долгому нажатию на пару).
/// [forGroup] — староста открыл окно из вкладки «Староста»: переключатель «Для всей группы» сразу включён.
Future<void> showAddHomework(BuildContext context, {String? subject, bool forGroup = false}) {
  // Преподаватель: вместо личного ДЗ студента открывается отправка ДЗ студентам
  if (ProviderScope.containerOf(context).read(isTeacherModeProvider)) {
    return showTeacherHomeworkSheet(context, subject: subject);
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddHomeworkSheet(initialSubject: subject, initialForGroup: forGroup),
  );
}

class _AddHomeworkSheet extends ConsumerStatefulWidget {
  const _AddHomeworkSheet({this.initialSubject, this.initialForGroup = false});
  final String? initialSubject;
  final bool initialForGroup;

  @override
  ConsumerState<_AddHomeworkSheet> createState() => _AddHomeworkSheetState();
}

class _AddHomeworkSheetState extends ConsumerState<_AddHomeworkSheet> {
  final _text = TextEditingController();
  String? _subject;
  LessonKind? _kind; // null — к любому занятию
  DateTime? _manualDue; // выбранный вручную срок
  final List<Attachment> _files = []; // уже скопированные в память приложения
  bool _forGroup = false; // староста: ДЗ для всей группы
  int? _subgroup; // староста: ДЗ только одной подгруппе (null — всем)
  bool _saved = false;
  bool _busy = false; // идёт отправка на сервер (файлы могут грузиться долго)
  late final AttachmentStore _store; // запоминаем заранее: в dispose() ref уже читать нельзя

  @override
  void initState() {
    super.initState();
    _subject = widget.initialSubject;
    _forGroup = widget.initialForGroup && ref.read(isGroupEditorProvider); // переключатель есть только у старосты
    _store = ref.read(attachmentStoreProvider);
  }

  @override
  void dispose() {
    // Закрыли окно, не сохранив: скопированные файлы больше никому не нужны
    if (!_saved) {
      for (final f in _files) {
        _store.delete(f);
      }
    }
    _text.dispose();
    super.dispose();
  }

  /// У выбранного предмета есть деление на подгруппы (и ДЗ для группы): можно выбрать подгруппу.
  bool get _splits {
    final data = ref.read(myScheduleProvider).value;
    return _forGroup && _subject != null && data != null && subjectSplitsBySubgroup(data.schedule, _subject!);
  }

  /// Срок: выбранный вручную или следующее занятие предмета.
  DateTime? _due(MySchedule data, DateTime today) {
    if (_manualDue != null) return _manualDue;
    final subject = _subject;
    if (subject == null) return null;
    return nextOccurrence(subject, today, data.index, data.schedule, data.profile, kind: _kind);
  }

  /// Меню «Прикрепить»: камера, галерея или любой файл.
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
      await _addPicked(picked);
    } catch (_) {
      _say('Не удалось выбрать файл. Проверьте разрешения приложения в настройках телефона.');
    }
  }

  /// Для всей группы файлов можно меньше и они легче: они лежат на общем сервере.
  int get _maxFiles => _forGroup ? maxGroupFilesPerHomework : maxAttachmentsPerHomework;
  int get _maxBytes => _forGroup ? maxGroupFileBytes : maxAttachmentBytes;

  Future<void> _addPicked(List<PickedFileInfo> picked) async {
    final store = ref.read(attachmentStoreProvider);
    var skippedBig = 0;
    var skippedMany = 0;
    for (final p in picked) {
      if (_files.length >= _maxFiles) {
        skippedMany++;
        continue;
      }
      if ((p.sizeBytes ?? 0) > _maxBytes) {
        skippedBig++;
        continue;
      }
      final saved = await store.save(p);
      if (!mounted) return;
      setState(() => _files.add(saved));
    }
    if (skippedBig > 0) _say('Файл больше ${_maxBytes ~/ (1024 * 1024)} МБ не прикреплён');
    if (skippedMany > 0) _say('К одному заданию можно прикрепить не больше $_maxFiles файлов');
  }

  void _say(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save(DateTime due) async {
    // Староста: ДЗ уходит на сервер и появляется у всей группы во вкладке «Староста»
    if (_forGroup) {
      setState(() => _busy = true);
      try {
        await GroupEditorActions.of(context).saveHomework(subject: _subject!, text: _text.text.trim(), due: due, kind: _kind, subgroup: _splits ? _subgroup : null, files: _files);
      } on SharedApiException catch (e) {
        if (mounted) setState(() => _busy = false);
        _say(e.message);
        return;
      }
      _saved = true; // копии файлов остаются в телефоне старосты как «скачанные»
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await ref.read(homeworkRepositoryProvider).add(HomeworkItem(
          subject: _subject!,
          text: _text.text.trim(),
          dueDate: due,
          kind: _kind,
          createdAt: DateTime.now().toUtc(),
          attachments: _files,
        ));
    _saved = true;
    ref.invalidate(homeworkProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(myScheduleProvider).value;
    final today = ref.watch(todayProvider);
    final theme = Theme.of(context);
    if (data == null) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));

    final subjects = subjectsOf(data.schedule, data.profile);
    final due = _due(data, today);
    final canSave = _subject != null && _text.text.trim().isNotEmpty && due != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Новое ДЗ', style: theme.textTheme.titleLarge),
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
                _manualDue = null;
                _subgroup = null;
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: widget.initialSubject != null,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Что задали', border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('К любому занятию'), selected: _kind == null, onSelected: (_) => setState(() => _kind = null)),
              ChoiceChip(label: const Text('К лекции'), selected: _kind == LessonKind.lecture, onSelected: (_) => setState(() => _kind = LessonKind.lecture)),
              ChoiceChip(label: const Text('К практике'), selected: _kind == LessonKind.practice, onSelected: (_) => setState(() => _kind = LessonKind.practice)),
            ]),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(due == null ? (_subject == null ? 'Выберите предмет' : 'Занятий не найдено — выберите дату') : 'Срок: ${dayTitle(due)}'),
              subtitle: Text(_manualDue == null ? 'Подставлено автоматически — следующее занятие' : 'Выбрано вручную'),
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
            if (ref.watch(isGroupEditorProvider))
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Для всей группы'),
                subtitle: Text(_forGroup
                    ? 'Увидят все студенты группы во вкладке «Староста». Файлы: до $maxGroupFilesPerHomework шт., каждый до ${maxGroupFileBytes ~/ (1024 * 1024)} МБ'
                    : 'Вы староста: можно задать ДЗ всем сразу'),
                value: _forGroup,
                onChanged: (v) => setState(() {
                  _forGroup = v;
                  if (!v) _subgroup = null;
                }),
              ),
            if (_splits)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Для кого ДЗ', style: theme.textTheme.labelLarge),
                  const SizedBox(height: Gap.xs),
                  Wrap(spacing: 8, children: [
                    ChoiceChip(label: const Text('Всей группе'), selected: _subgroup == null, onSelected: (_) => setState(() => _subgroup = null)),
                    for (final s in data.schedule.subgroups)
                      ChoiceChip(label: Text(s.label), selected: _subgroup == s.n, onSelected: (_) => setState(() => _subgroup = s.n)),
                  ]),
                ]),
              ),
            if (_files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final f in _files)
                    AttachmentTile(
                      attachment: f,
                      onRemove: () {
                        ref.read(attachmentStoreProvider).delete(f);
                        setState(() => _files.remove(f));
                      },
                    ),
                ]),
              ),
            Row(children: [
              OutlinedButton.icon(
                onPressed: _files.length >= _maxFiles ? null : _attach,
                icon: const Icon(Icons.attach_file_rounded),
                label: Text(_files.isEmpty ? 'Прикрепить' : 'Ещё (${_files.length})'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: canSave && !_busy ? () => _save(due) : null,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Добавить'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
