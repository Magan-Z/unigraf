// «Объявить аттестацию, зачёт или экзамен»: вид, на какое занятие и необязательная заметка.
// Результат — обычная правка «заменить» с типом занятия (см. domain/assessments.dart).

import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../domain/assessments.dart';
import '../../domain/models.dart';
import '../../theme/tokens.dart';

class AnnounceDialog extends StatefulWidget {
  const AnnounceDialog({super.key, required this.lesson, required this.options, required this.initial, required this.forGroup, this.groupHint});

  /// Пара, на которую нажали.
  final ResolvedLesson lesson;

  /// Занятия, на которые можно объявить: сама пара и ближайшие такие же.
  final List<ResolvedLesson> options;
  final int initial;

  /// true — староста объявляет для группы, false — студент отмечает у себя.
  final bool forGroup;

  /// Пояснение для старосты: объявление увидит только его подгруппа.
  final String? groupHint;

  @override
  State<AnnounceDialog> createState() => _AnnounceDialogState();
}

class _AnnounceDialogState extends State<AnnounceDialog> {
  LessonKind? _kind;
  late int _picked = widget.initial;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _label(ResolvedLesson l) => '${dayTitle(l.date)} · ${l.pair} пара';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final target = widget.options[_picked];
    return AlertDialog(
      title: Text(widget.forGroup ? 'Объявить для группы' : 'Отметить у себя'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.lesson.subject, style: theme.textTheme.titleSmall),
          const SizedBox(height: Gap.md),
          Wrap(spacing: Gap.sm, children: [
            for (final k in announceKinds) ChoiceChip(label: Text(k.title), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
          ]),
          const SizedBox(height: Gap.lg),
          Text('На какое занятие', style: theme.textTheme.labelLarge),
          for (var i = 0; i < widget.options.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(i == _picked ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, color: i == _picked ? scheme.primary : scheme.onSurfaceVariant),
              title: Text(_label(widget.options[i])),
              subtitle: i == 0 ? const Text('это занятие') : (i == 1 ? const Text('следующее') : null),
              onTap: () => setState(() => _picked = i),
            ),
          const SizedBox(height: Gap.sm),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Заметка (необязательно)', hintText: 'темы, время, что взять')),
          if (widget.groupHint != null) ...[
            const SizedBox(height: Gap.md),
            Text(widget.groupHint!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: _kind == null
              ? null
              : () => Navigator.pop(
                    context,
                    Override(
                      date: target.date,
                      pair: target.pair,
                      type: OverrideType.replace,
                      kind: _kind,
                      matchSubject: widget.lesson.subject,
                      note: assessmentNote(_kind!, _note.text),
                    ),
                  ),
          child: Text(widget.forGroup ? 'Объявить' : 'Отметить'),
        ),
      ],
    );
  }
}
