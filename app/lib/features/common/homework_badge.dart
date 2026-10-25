// Значок домашнего задания на карточке пары: квадратная кнопка с рамкой в правом верхнем углу, как «табличка» аудитории,
// только красная. Внутри прежний значок приложения (портфель с восклицательным знаком). Красная — есть невыполненное
// (с цифрой, если заданий несколько); серая с галочкой — всё сделано. Фон кнопки берётся из темы, поэтому в тёмной теме она тёмная.
// Нажатие открывает окно со списком заданий к этой паре.

import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../domain/lesson_homework.dart';
import '../../theme/next_design.dart';
import '../../theme/tokens.dart';
import 'press_scale.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final done = homework.allDone;
    final count = homework.open;
    // Красная — «надо сделать»; серая — сделано. Рамка и значок одного цвета, фон из темы (как у таблички аудитории).
    final color = done ? scheme.onSurfaceVariant : scheme.error;
    final border = done ? scheme.outlineVariant : scheme.error;

    final button = Material(
      color: scheme.surface.withValues(alpha: done ? 0.6 : 0.85),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        side: BorderSide(color: border, width: kNextDesign ? 2.5 : 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(done ? Icons.assignment_turned_in_rounded : Icons.assignment_late_rounded, size: 26, color: color),
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
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.error,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: scheme.surface, width: 2),
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(color: scheme.onError, fontSize: 12, fontWeight: FontWeight.w800, height: 1.1),
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
    final color = done ? scheme.onSurfaceVariant : scheme.error;
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
            Icon(done ? Icons.assignment_turned_in_rounded : Icons.assignment_late_rounded, size: 24, color: color),
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
