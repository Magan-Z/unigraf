// Значок домашнего задания на карточке пары: квадратная кнопка в правом верхнем углу (вариант выбран владельцем 2026-10-25).
// Красная заливка с белым значком «планшет со списком»: есть невыполненное; красный кружок с цифрой, если заданий несколько.
// Всё сделано: светлая плитка с серым значком и галочкой (в тёмной теме тёмно-серая). Нажатие открывает окно со списком заданий.

import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../domain/lesson_homework.dart';
import '../../theme/next_design.dart';
import '../../theme/tokens.dart';
import 'press_scale.dart';

/// Красный цвет значка «надо сделать»: один и тот же в светлой и тёмной теме, белый значок на нём читается (контраст ≥ 4,5:1).
const Color homeworkRed = Color(0xFFD92D20);

/// Подпись для экранной читалки (одна и та же на «Сегодня» и в «Неделе»).
String homeworkBadgeLabel(LessonHomework hw) {
  if (hw.allDone) return 'Домашнее задание выполнено. Открыть';
  final n = hw.open;
  return 'Домашнее задание: $n ${plural(n, 'задание', 'задания', 'заданий')}. Открыть';
}

class HomeworkBadge extends StatelessWidget {
  const HomeworkBadge({super.key, required this.homework, required this.onPressed});

  final LessonHomework homework;
  final VoidCallback onPressed;

  /// Сторона кнопки: не меньше 44 dp, чтобы попадать одним пальцем.
  static const double size = 44;

  /// Отступы от верхнего и правого края карточки.
  static const double top = 10;
  static const double right = 12;

  /// Сколько места слева от правого края карточки кнопка занимает вместе с зазором: название не должно заезжать под неё.
  static const double reserved = right + size + 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final done = homework.allDone;
    final count = homework.open;

    // Сделано: в светлой теме белая плитка с тонкой рамкой, в тёмной полупрозрачно-серая
    final bg = done ? (dark ? scheme.onSurface.withValues(alpha: 0.16) : scheme.surfaceContainerLowest) : homeworkRed;
    final fg = done ? scheme.onSurfaceVariant : Colors.white;

    final button = Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        side: done && !dark ? BorderSide(color: scheme.outlineVariant) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(alignment: Alignment.center, children: [
            Icon(Icons.assignment_outlined, size: 26, color: fg),
            if (done)
              Positioned(
                right: 5,
                bottom: 5,
                child: Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(color: scheme.onSurfaceVariant, shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded, size: 11, color: scheme.surface),
                ),
              ),
          ]),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: homeworkBadgeLabel(homework),
      excludeSemantics: true,
      onTap: onPressed,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: kNextDesign ? PressScale(scale: 0.94, child: button) : button),
          if (!done && count > 1)
            Positioned(
              top: -6,
              right: -6,
              child: IgnorePointer(
                child: Container(
                  constraints: const BoxConstraints(minWidth: 21, minHeight: 21),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Color.lerp(homeworkRed, Colors.black, 0.32),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: scheme.surface, width: 2),
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, height: 1.1),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Компактный значок для «Недели», где строки тесные: тот же значок из приложения, с цифрой и областью нажатия 44 dp.
class HomeworkInlineBadge extends StatelessWidget {
  const HomeworkInlineBadge({super.key, required this.homework, required this.onPressed});

  final LessonHomework homework;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = homework.allDone;
    final color = done ? scheme.onSurfaceVariant : homeworkRed;
    return Semantics(
      button: true,
      label: homeworkBadgeLabel(homework),
      excludeSemantics: true,
      onTap: onPressed,
      child: InkResponse(
        onTap: onPressed,
        radius: 24,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(done ? Icons.assignment_turned_in_outlined : Icons.assignment_outlined, size: 24, color: color),
            if (!done && homework.open > 1)
              Padding(
                padding: const EdgeInsets.only(left: Gap.xs),
                child: Text('${homework.open}', textScaler: TextScaler.noScaling, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800)),
              ),
          ]),
        ),
      ),
    );
  }
}
