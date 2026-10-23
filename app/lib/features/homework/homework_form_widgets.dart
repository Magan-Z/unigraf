// Общие части окон «Новое ДЗ» и «ДЗ студентам»: оформление то же, что на странице «Отправить ДЗ с компьютера»
// (подписи полей, чипы с галочкой, переключатель-таблетка, поле срока, зона файлов, панель отправки внизу).

import 'package:flutter/material.dart';

import '../../domain/attachment.dart';
import '../../theme/tokens.dart';

/// Подпись поля: жирная, с необязательной подсказкой справа.
class FormLabel extends StatelessWidget {
  const FormLabel(this.text, {super.key, this.hint, this.trailing});
  final String text;
  final String? hint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Row(children: [
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: text, style: theme.textTheme.titleSmall),
            if (hint != null) TextSpan(text: '  $hint', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ])),
        ),
        ?trailing,
      ]),
    );
  }
}

/// Выбираемая таблетка с круглой галочкой слева (группы, подгруппы).
class CheckChip extends StatelessWidget {
  const CheckChip({super.key, required this.label, required this.selected, required this.onSelected});
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: label,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: StadiumBorder(side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => onSelected(!selected),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 16, 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(
                  duration: Motion.fast,
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? scheme.primary : Colors.transparent,
                    border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: 1.5),
                  ),
                  child: selected ? Icon(Icons.check_rounded, size: 15, color: scheme.onPrimary) : null,
                ),
                const SizedBox(width: Gap.sm),
                Flexible(
                  child: Text(label, style: theme.textTheme.labelLarge?.copyWith(color: selected ? scheme.onPrimaryContainer : scheme.onSurface)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Переключатель-таблетка на 2–3 варианта (к какому занятию, для кого).
class PillSegments<T> extends StatelessWidget {
  const PillSegments({super.key, required this.options, required this.selected, required this.onChanged});
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: ShapeDecoration(color: scheme.surfaceContainerHigh, shape: const StadiumBorder()),
      child: Row(children: [
        for (final (value, label) in options)
          Expanded(
            child: Semantics(
              button: true,
              selected: value == selected,
              excludeSemantics: true,
              label: label,
              child: Material(
                color: value == selected ? scheme.surface : Colors.transparent,
                elevation: value == selected ? 1 : 0,
                shadowColor: scheme.shadow.withValues(alpha: 0.4),
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onChanged(value),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 40),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(color: value == selected ? scheme.onSurface : scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Срок сдачи: поле с датой и значком календаря, под ним пояснение, откуда дата.
class DueDateField extends StatelessWidget {
  const DueDateField({super.key, required this.value, required this.placeholder, required this.hint, required this.onTap});
  final String? value;
  final String placeholder;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const FormLabel('Срок сдачи'),
      Semantics(
        button: true,
        label: 'Срок сдачи: ${value ?? placeholder}. Изменить дату',
        excludeSemantics: true,
        child: Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm), side: BorderSide(color: scheme.outlineVariant, width: 1.5)),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.sm),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              child: Row(children: [
                Expanded(
                  child: Text(value ?? placeholder, style: theme.textTheme.bodyLarge?.copyWith(color: value == null ? scheme.onSurfaceVariant : scheme.onSurface)),
                ),
                Icon(Icons.event_rounded, color: scheme.onSurfaceVariant),
              ]),
            ),
          ),
        ),
      ),
      const SizedBox(height: Gap.xs),
      Text(hint, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
    ]);
  }
}

/// Прикреплённый файл: расширение в плитке, имя, размер, «убрать».
class FileRow extends StatelessWidget {
  const FileRow({super.key, required this.attachment, required this.onRemove});
  final Attachment attachment;
  final VoidCallback onRemove;

  static String _ext(String name) {
    final i = name.lastIndexOf('.');
    return i > 0 && i < name.length - 1 ? name.substring(i + 1, (i + 5).clamp(0, name.length)).toUpperCase() : '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ext = _ext(attachment.name);
    return Semantics(
      label: 'Вложение ${attachment.name}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.xs, Gap.sm),
        decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(Radii.sm)),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
            child: ext.isEmpty
                ? Icon(Icons.insert_drive_file_outlined, size: 20, color: scheme.onPrimaryContainer)
                : Text(ext, style: theme.textTheme.labelSmall?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(attachment.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
              if (attachment.sizeText.isNotEmpty) Text(attachment.sizeText, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
          ),
          IconButton(tooltip: 'Убрать вложение', icon: const Icon(Icons.close_rounded), color: scheme.onSurfaceVariant, onPressed: onRemove),
        ]),
      ),
    );
  }
}

/// Зона прикрепления файлов: пунктирная рамка, значок, подсказка и кнопка.
class AttachZone extends StatelessWidget {
  const AttachZone({super.key, required this.count, required this.limitText, required this.onPressed});
  final int count;
  final String limitText;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return CustomPaint(
      painter: _DashedBorder(color: scheme.outlineVariant, radius: Radii.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.lg),
        child: SizedBox(
          width: double.infinity,
          child: Column(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(Icons.upload_file_rounded, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: Gap.sm),
            Text('Фото, PDF, документы', style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(limitText, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: Gap.md),
            FilledButton.tonalIcon(
              onPressed: onPressed,
              icon: const Icon(Icons.attach_file_rounded),
              label: Text(count == 0 ? 'Прикрепить' : 'Ещё ($count)'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    const dash = 7.0, gap = 5.0;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, (d + dash).clamp(0, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color || old.radius != radius;
}

/// Панель отправки внизу окна: всегда на виду, одна крупная кнопка.
class SheetActionBar extends StatelessWidget {
  const SheetActionBar({super.key, required this.label, required this.onPressed, this.busy = false, this.icon, this.note});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(color: scheme.surface, border: Border(top: BorderSide(color: scheme.outlineVariant))),
      padding: const EdgeInsets.fromLTRB(20, Gap.md, 20, Gap.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 52,
          child: icon == null && !busy
              ? FilledButton(onPressed: onPressed, child: Text(label))
              : FilledButton.icon(
                  onPressed: onPressed,
                  icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)) : Icon(icon, size: 18),
                  label: Text(label),
                ),
        ),
        if (note != null) ...[
          const SizedBox(height: Gap.xs),
          Text(note!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ]),
    );
  }
}
