// ДЗ к паре из трёх источников: отбор по предмету и сроку, порядок, счётчик на значке, подсказка о дубле.

import 'package:flutter_test/flutter_test.dart';
import 'package:unigraf/domain/homework.dart';
import 'package:unigraf/domain/lesson_homework.dart';
import 'package:unigraf/domain/models.dart';

HomeworkItem _hw(
  String text, {
  HomeworkSource source = HomeworkSource.mine,
  String subject = 'Философия',
  String due = '2026-10-14',
  LessonKind? kind,
  bool done = false,
  int minute = 0,
}) =>
    HomeworkItem(
      subject: subject,
      text: text,
      dueDate: parseDay(due),
      kind: kind,
      done: done,
      createdAt: DateTime.utc(2026, 10, 7, 10, minute),
      source: source,
    );

void main() {
  final day = parseDay('2026-10-14');

  group('homeworkForLesson', () {
    test('берёт тот же предмет и тот же срок, чужое не берёт', () {
      final all = [
        _hw('моё'),
        _hw('другой предмет', subject: 'ЧТК и этика'),
        _hw('другой срок', due: '2026-10-15'),
      ];
      expect(homeworkForLesson(all, subject: 'Философия', day: day).map((h) => h.text), ['моё']);
    });

    test('порядок: преподаватель, староста, ваше; внутри источника по времени создания', () {
      final all = [
        _hw('м2', minute: 5),
        _hw('м1', minute: 1),
        _hw('с', source: HomeworkSource.headman),
        _hw('п', source: HomeworkSource.teacher),
      ];
      expect(homeworkForLesson(all, subject: 'Философия', day: day).map((h) => h.text), ['п', 'с', 'м1', 'м2']);
    });

    test('тип занятия: «любое» подходит всем, «лекция» не подходит практике', () {
      final all = [_hw('любое'), _hw('лекция', kind: LessonKind.lecture), _hw('практика', kind: LessonKind.practice)];
      expect(homeworkForLesson(all, subject: 'Философия', day: day, kind: LessonKind.lecture).map((h) => h.text), ['любое', 'лекция']);
      expect(homeworkForLesson(all, subject: 'Философия', day: day).map((h) => h.text).toSet(), {'любое', 'лекция', 'практика'});
    });

    test('выполненные тоже входят (значок станет серым, а не пропадёт)', () {
      final list = homeworkForLesson([_hw('сделано', done: true)], subject: 'Философия', day: day);
      expect(list, hasLength(1));
      final hw = LessonHomework(list);
      expect(hw.allDone, isTrue);
      expect(hw.open, 0);
    });
  });

  group('LessonHomework', () {
    test('счётчик и состояния', () {
      expect(LessonHomework.none.isEmpty, isTrue);
      expect(LessonHomework.none.allDone, isFalse);
      final hw = LessonHomework([_hw('а'), _hw('б', done: true), _hw('в', source: HomeworkSource.teacher)]);
      expect(hw.open, 2);
      expect(hw.allDone, isFalse);
    });
  });

  group('alreadyAssigned (подсказка о дубле)', () {
    test('находит невыполненное на тот же предмет и срок у любого источника', () {
      final all = [
        _hw('от старосты', source: HomeworkSource.headman),
        _hw('от преподавателя', source: HomeworkSource.teacher),
        _hw('уже сделано', done: true),
        _hw('другой предмет', subject: 'ЧТК и этика'),
      ];
      final found = alreadyAssigned(all, subject: 'Философия', due: day);
      expect(found.map((h) => h.source), [HomeworkSource.teacher, HomeworkSource.headman]);
    });

    test('когда ничего нет — пусто', () {
      expect(alreadyAssigned([_hw('другой срок', due: '2026-10-20')], subject: 'Философия', due: day), isEmpty);
    });
  });
}
