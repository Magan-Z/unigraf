// Проверка логики страницы преподавателя: node --test data/web_tests/*.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const here = fileURLToPath(new URL('.', import.meta.url));
const L = createRequire(import.meta.url)(here + '../web/teacher/teacher-logic.js');
const fixture = (name) => JSON.parse(fs.readFileSync(here + 'fixtures/' + name, 'utf8'));
const index = fixture('index.json');
const schedules = ['ofo-1-bi-25.json', 'ofo-2-bi-25.json'].map(fixture);

test('имя преподавателя: инициалы и полное ФИО (как в приложении)', () => {
  assert.equal(L.sameTeacher('Чураев И.Л.', 'Чураев Ибрагим Лечаевич'), true);
  assert.equal(L.sameTeacher('Алиева М.', 'Алиева М.В.'), true);
  assert.equal(L.sameTeacher('Алиева М.В.', 'Алиева М.П.'), false);
  assert.equal(L.sameTeacher('Юсупова М.Д.', 'Юсупова Элина Ахмадовна'), false);
  assert.equal(L.sameTeacher('Халиев М.С-У.', 'Халиев Магомед Сайд-Усманович'), true);
  assert.equal(L.sameTeacher('Аюбов. С-М.', 'Аюбов С-М.'), true);
  assert.equal(L.sameTeacher('Иванов', 'Петров'), false);
  assert.deepEqual(L.splitName('Батаева П.С'), { surname: 'батаева', first: 'п', second: 'с' });
});

test('неделя: ((дата − якорь) // 7) % 2 + 1, и до якоря тоже', () => {
  const anchor = L.parseDay('2026-08-31');
  assert.equal(L.weekNumber(L.parseDay('2026-08-31'), anchor), 1);
  assert.equal(L.weekNumber(L.parseDay('2026-09-07'), anchor), 2);
  assert.equal(L.weekNumber(L.parseDay('2026-10-07'), anchor), 2); // среда 7 октября: 2 неделя (как в тестах приложения)
  assert.equal(L.weekNumber(L.parseDay('2026-08-24'), anchor), 2);
});

test('предметы и группы преподавателя по настоящему расписанию: общая лекция у двух групп', () => {
  const v = L.buildTeacherView('Халиев М.С-У.', schedules);
  assert.deepEqual(v.subjects, ['Технологическое предпринимательство']);
  assert.deepEqual(v.targets['Технологическое предпринимательство'].map((t) => t.label), ['1 БИ-25', '2 БИ-25']);
  const none = L.buildTeacherView('Несуществующий Н.Н.', schedules);
  assert.deepEqual(none.subjects, []);
});

test('подгруппы: если есть занятие для всей группы, отдельные подгруппы не нужны; иначе предлагаются подгруппы', () => {
  const group = { id: 'g1', title: '1 БИ-1', subgroups: [{ n: 1, label: 'БИ-1-1' }, { n: 2, label: 'БИ-1-2' }] };
  const lesson = (subject, subgroups) => ({ weekday: 2, pair: 1, week: 0, subgroups, kind: 'practice', subject, teacher: 'Тестов Т.Т.' });
  const s = [{ group, lessons: [lesson('Только вторая', [2]), lessons0('Обе', [1, 2]), lesson('Смешанно', [1]), lesson('Смешанно', [1, 2])] }];
  function lessons0(a, b) { return lesson(a, b); }
  const v = L.buildTeacherView('Тестов Т.Т.', s);
  assert.deepEqual(v.targets['Только вторая'].map((t) => t.label), ['БИ-1-2']);
  assert.deepEqual(v.targets['Обе'].map((t) => [t.label, t.subgroup]), [['1 БИ-1', null]]);
  assert.deepEqual(v.targets['Смешанно'].map((t) => t.label), ['1 БИ-1']);
});

test('разрешённые группы берутся из сессии, остальные показываются отдельно', () => {
  const v = L.buildTeacherView('Халиев М.С-У.', schedules);
  const r = L.splitAllowed(v.targets['Технологическое предпринимательство'], ['ofo-1-bi-25']);
  assert.deepEqual(r.allowed.map((t) => t.label), ['1 БИ-25']);
  assert.deepEqual(r.blocked.map((t) => t.label), ['2 БИ-25']);
});

test('срок по умолчанию: ближайшее занятие после сегодняшнего дня', () => {
  const v = L.buildTeacherView('Халиев М.С-У.', schedules);
  const subject = 'Технологическое предпринимательство';
  const today = L.parseDay('2026-10-07'); // среда
  assert.equal(L.dayText(L.nextOccurrence(subject, today, v, index)), '2026-10-10'); // суббота (практика)
  assert.equal(L.dayText(L.nextOccurrence(subject, today, v, index, 'lecture')), '2026-10-14'); // следующая среда
  assert.equal(L.nextOccurrence('Нет такого', today, v, index), null);
  // после конца семестра занятий нет
  assert.equal(L.nextOccurrence(subject, L.parseDay('2026-12-30'), v, index), null);
});

test('сегодня считается по Москве, а не по поясу компьютера', () => {
  assert.equal(L.dayText(L.moscowToday(new Date('2026-10-07T22:30:00Z'))), '2026-10-08'); // в Москве уже 01:30 восьмого
  assert.equal(L.dayText(L.moscowToday(new Date('2026-10-07T20:30:00Z'))), '2026-10-07');
});

test('файлы: предел 15 МБ и 5 штук, программы запрещены, пустой файл нельзя', () => {
  assert.equal(L.checkFile('Лекция.pdf', 15 * 1024 * 1024, 0), null);
  assert.equal(L.checkFile('Лекция.pdf', 15 * 1024 * 1024 + 1, 0), 'file_too_big');
  assert.equal(L.checkFile('a.pdf', 10, 5), 'too_many_files');
  assert.equal(L.checkFile('setup.EXE', 10, 0), 'bad_file_type');
  assert.equal(L.checkFile('run.js', 10, 0), 'bad_file_type');
  assert.equal(L.checkFile('data.json', 10, 0), null);
  assert.equal(L.checkFile('a.pdf', 0, 0), 'empty_file');
  assert.equal(L.cleanFileName('..\\..\\a/b.pdf'), '.._.._a_b.pdf');
  assert.equal(L.cleanFileName('x'.repeat(300)).length, 200);
  assert.equal(L.formatSize(1536), '2 КБ');
  assert.equal(L.formatSize(15 * 1024 * 1024), '15,0 МБ');
});

test('код и слова', () => {
  assert.equal(L.formatCode('QAG3V3FY'), 'QAG3-V3FY');
  assert.equal(L.plural(1, 'группа', 'группы', 'групп'), 'группа');
  assert.equal(L.plural(3, 'группа', 'группы', 'групп'), 'группы');
  assert.equal(L.plural(11, 'группа', 'группы', 'групп'), 'групп');
  assert.match(L.messageFor('bad_token'), /Вход закрыт/);
  assert.match(L.messageFor("что-то новое", "x"), /Ошибка сервера.*\(x\)/);
});
