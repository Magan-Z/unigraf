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

  /// Область нажатия: не меньше 44 dp, чтобы попадать одним пальцем. Сама плитка чуть меньше.
  static const double size = 44;
  static const double visual = 40;

  /// Отступы области нажатия от верхнего и правого края карточки (плитка от краёв на 2 dp дальше).
  static const double top = 8;
  static const double right = 10;

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

    final tile = Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: done && !dark ? BorderSide(color: scheme.outlineVariant) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: visual,
          height: visual,
          child: Stack(alignment: Alignment.center, children: [
            HomeworkIcon(color: fg, size: 27),
            if (done)
              Positioned(
                right: 4,
                bottom: 4,
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            kNextDesign ? PressScale(scale: 0.94, child: tile) : tile,
            if (!done && count > 1)
              Positioned(
                top: (size - visual) / 2 - 6,
                right: (size - visual) / 2 - 6,
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
      ),
    );
  }
}

/// Значок «планшет со списком»: толстая закруглённая линия, три строки с точками (нарисован по макету владельца).
class HomeworkIcon extends StatelessWidget {
  const HomeworkIcon({super.key, required this.color, this.size = 24});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _HomeworkIconPainter(color));
}

class _HomeworkIconPainter extends CustomPainter {
  _HomeworkIconPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // рисуем на сетке 24 x 24 и растягиваем под нужный размер
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;

    // корпус: рамка с разрывом сверху, где крепится зажим
    const l = 4.3, r = 19.7, t = 5.3, b = 21.7, rad = 1.9;
    final body = Path()
      ..moveTo(8.0, t)
      ..lineTo(l + rad, t)
      ..arcToPoint(const Offset(l, t + rad), radius: const Radius.circular(rad), clockwise: false)
      ..lineTo(l, b - rad)
      ..arcToPoint(const Offset(l + rad, b), radius: const Radius.circular(rad), clockwise: false)
      ..lineTo(r - rad, b)
      ..arcToPoint(const Offset(r, b - rad), radius: const Radius.circular(rad), clockwise: false)
      ..lineTo(r, t + rad)
      ..arcToPoint(const Offset(r - rad, t), radius: const Radius.circular(rad), clockwise: false)
      ..lineTo(16.0, t);
    canvas.drawPath(body, stroke);

    // зажим: невысокий прямоугольник с «горбом» сверху
    canvas.drawRRect(RRect.fromLTRBR(8.1, 4.1, 15.9, 7.0, const Radius.circular(1.5)), stroke);
    canvas.drawArc(Rect.fromCircle(center: const Offset(12, 4.4), radius: 2.1), 3.14159, 3.14159, false, stroke);

    // три строки: квадратик и линия
    for (final y in const [10.9, 14.3, 17.6]) {
      canvas.drawRRect(RRect.fromLTRBR(7.1, y - 0.85, 9.2, y + 0.85, const Radius.circular(0.6)), fill);
      canvas.drawLine(Offset(11.2, y), Offset(16.2, y), stroke);
    }
  }

  @override
  bool shouldRepaint(_HomeworkIconPainter old) => old.color != color;
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
            Stack(alignment: Alignment.center, children: [
              HomeworkIcon(color: color, size: 24),
              if (done)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(color: scheme.onSurfaceVariant, shape: BoxShape.circle),
                    child: Icon(Icons.check_rounded, size: 10, color: scheme.surface),
                  ),
                ),
            ]),
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
