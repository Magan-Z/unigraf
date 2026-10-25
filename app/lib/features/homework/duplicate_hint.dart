// Подсказка в окне «Новое ДЗ»: на этот предмет и срок уже есть задание (от преподавателя, старосты или ваше).
// Ничего не запрещает: тексты бывают разными. Но чаще всего добавлять второй раз то же самое не нужно.

import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../domain/homework.dart';
import '../../theme/tokens.dart';

class DuplicateHint extends StatelessWidget {
  const DuplicateHint({super.key, required this.items, required this.onSkip});

  /// Уже заданное (не выполненное) на тот же предмет и срок.
  final List<HomeworkItem> items;

  /// «Не добавлять»: закрыть окно.
  final VoidCallback onSkip;

  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final extra = items.length - _shown;
    return Semantics(
      container: true,
      label: 'На эту пару уже задано: ${items.length} ${plural(items.length, 'задание', 'задания', 'заданий')}',
      child: Container(
        margin: const EdgeInsets.only(top: Gap.md),
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.sm, Gap.xs),
        decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(Radii.sm)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.info_outline_rounded, size: 20, color: scheme.onTertiaryContainer),
            const SizedBox(width: Gap.sm),
            Expanded(child: Text('На эту пару уже задано', style: theme.textTheme.titleSmall?.copyWith(color: scheme.onTertiaryContainer))),
          ]),
          const SizedBox(height: Gap.sm),
          for (final h in items.take(_shown))
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.xs, right: Gap.sm),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${h.source.title}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: h.text),
                ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onTertiaryContainer),
              ),
            ),
          if (extra > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.xs),
              child: Text('и ещё $extra', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onTertiaryContainer)),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(foregroundColor: scheme.onTertiaryContainer),
              child: const Text('Не добавлять'),
            ),
          ),
        ]),
      ),
    );
  }
}
