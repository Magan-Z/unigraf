// Значок домашнего задания на карточке пары: «закладка», которая торчит из верхнего края (как закладка в тетради).
// Красная — есть невыполненное (с цифрой, если заданий несколько); серая с галочкой — всё сделано.
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
  const HomeworkBadge({super.key, required this.homework, required this.cardColor, required this.onPressed});

  final LessonHomework homework;

  /// Цвет карточки под значком: от него считается серый цвет выполненного.
  final Color cardColor;
  final VoidCallback onPressed;

  static const double ribbonWidth = 36;
  static const double ribbonHeight = 56;

  /// Ширина области нажатия (меньше 48 dp не бывает) и высота значка вместе с областью.
  static const double hitWidth = 48;

  /// Сколько места значок занимает справа от левого края карточки: нужно, чтобы название не заезжало под него.
  static const double reserved = 14 + ribbonWidth + 6;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = homework.allDone;
    final bg = done ? Color.lerp(cardColor, scheme.onSurfaceVariant, 0.55)! : scheme.error;
    final fg = done ? cardColor : scheme.onError;
    final count = homework.open;

    final ribbon = PhysicalShape(
      clipper: const _RibbonClipper(),
      color: bg,
      elevation: 2,
      shadowColor: Colors.black,
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: ribbonWidth,
            height: ribbonHeight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(done ? Icons.assignment_turned_in_rounded : Icons.assignment_late_rounded, size: 22, color: fg),
                if (!done && count > 1)
                  Text(
                    count > 9 ? '9+' : '$count',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800, height: 1.1),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: homeworkBadgeLabel(homework),
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: hitWidth,
          height: ribbonHeight + 4,
          child: Align(
            alignment: Alignment.topCenter,
            child: kNextDesign ? PressScale(scale: 0.94, child: ribbon) : ribbon,
          ),
        ),
      ),
    );
  }
}

class _RibbonClipper extends CustomClipper<Path> {
  const _RibbonClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(size.width / 2, size.height * 0.8)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
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
