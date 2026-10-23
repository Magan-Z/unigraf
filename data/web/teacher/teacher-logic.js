// Логика страницы «Отправить ДЗ с компьютера» без привязки к браузеру (проверяется тестами в data/web_tests/).
// Правила сопоставления имени, подбор предметов и групп повторяют приложение: app/lib/domain/search.dart и app/lib/domain/teacher.dart.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.TeacherLogic = factory();
})(this, function () {
  'use strict';

  // ---------- имя преподавателя ----------

  /** Имя разобрано на фамилию и первые буквы имени и отчества (строчные): «Чураев И.Л.» и «Чураев Ибрагим Лечаевич» понимаются одинаково. */
  function splitName(name) {
    var parts = String(name).trim().split(/\s+/);
    var surname = parts[0].replace(/\./g, '').toLowerCase();
    if (parts.length === 1) return { surname: surname, first: '', second: '' };
    // Полное ФИО: «Имя» и «Отчество» — отдельные слова без точек
    if (parts.length >= 3 && parts[1].indexOf('.') < 0 && parts[1].length > 2) {
      return { surname: surname, first: parts[1][0].toLowerCase(), second: parts[2][0].toLowerCase() };
    }
    // Инициалы: «И.Л.», «С-М.», «И.»
    var rest = parts.slice(1).join('').toLowerCase();
    var dot = rest.indexOf('.');
    return { surname: surname, first: rest ? rest[0] : '', second: dot >= 0 && dot + 1 < rest.length ? rest[dot + 1] : '' };
  }

  /** Один и тот же человек: фамилия и первая буква имени совпадают; отчество сравнивается, только если оно есть в обоих написаниях. */
  function sameTeacher(a, b) {
    var x = splitName(a), y = splitName(b);
    if (x.surname !== y.surname) return false;
    if (x.first && y.first && x.first !== y.first) return false;
    if (x.second && y.second && x.second !== y.second) return false;
    return true;
  }

  // ---------- даты ----------

  function parseDay(text) {
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
    if (!m) return null;
    return new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
  }

  function dayText(date) {
    return date.toISOString().slice(0, 10);
  }

  /** Номер недели (1 или 2): ((дата − weekAnchor) // 7) % 2 + 1, как в парсере и приложении. */
  function weekNumber(date, anchor) {
    var days = Math.round((date.getTime() - anchor.getTime()) / 86400000);
    var weeks = Math.floor(days / 7);
    return (((weeks % 2) + 2) % 2) + 1;
  }

  /** Сегодняшняя дата в Москве (как в приложении), а не по часам и поясу компьютера. */
  function moscowToday(now) {
    var s = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Moscow', year: 'numeric', month: '2-digit', day: '2-digit' }).format(now || new Date());
    return parseDay(s);
  }

  // ---------- предметы и группы ----------

  function targetLabel(t) {
    return t.subgroup == null ? t.title : (t.subgroupLabel || t.title + ', подгруппа ' + t.subgroup);
  }

  /**
   * Что преподаватель ведёт и кому может задать ДЗ. [schedules] — файлы групп (groups/ID.json), уже отобранные по списку из сессии.
   * Возвращает { subjects: [предмет...], targets: {предмет: [{groupId, title, subgroup, subgroupLabel, label}]}, lessons: {предмет: [{weekday, week, kind}]} }.
   * Если по предмету у группы есть занятие для всей группы, подгруппы отдельно не нужны.
   */
  function buildTeacherView(teacher, schedules) {
    var whole = {}, bySub = {}, lessons = {};
    schedules.forEach(function (s) {
      var g = s.group, subgroups = g.subgroups || [];
      var all = subgroups.map(function (x) { return x.n; });
      s.lessons.forEach(function (lesson) {
        if (!lesson.teacher || !sameTeacher(teacher, lesson.teacher)) return;
        var subject = lesson.subject;
        var isWhole = subgroups.length <= 1 || all.every(function (n) { return lesson.subgroups.indexOf(n) >= 0; });
        (lessons[subject] = lessons[subject] || []).push({ weekday: lesson.weekday, week: lesson.week, kind: lesson.kind });
        if (isWhole) {
          (whole[subject] = whole[subject] || {})[g.id] = { groupId: g.id, title: g.title, subgroup: null, subgroupLabel: null };
        } else {
          var perGroup = ((bySub[subject] = bySub[subject] || {})[g.id] = bySub[subject][g.id] || []);
          subgroups.forEach(function (x) {
            if (lesson.subgroups.indexOf(x.n) >= 0 && !perGroup.some(function (t) { return t.subgroup === x.n; })) {
              perGroup.push({ groupId: g.id, title: g.title, subgroup: x.n, subgroupLabel: x.label });
            }
          });
        }
      });
    });
    var subjects = {};
    Object.keys(whole).concat(Object.keys(bySub)).forEach(function (s) { subjects[s] = true; });
    var targets = {};
    Object.keys(subjects).forEach(function (subject) {
      var list = Object.keys(whole[subject] || {}).map(function (id) { return whole[subject][id]; });
      var wholeIds = {};
      list.forEach(function (t) { wholeIds[t.groupId] = true; });
      Object.keys(bySub[subject] || {}).forEach(function (id) {
        if (!wholeIds[id]) list = list.concat(bySub[subject][id]);
      });
      list.forEach(function (t) { t.label = targetLabel(t); });
      list.sort(function (a, b) { return a.label < b.label ? -1 : a.label > b.label ? 1 : 0; });
      targets[subject] = list;
    });
    return { subjects: Object.keys(subjects).sort(), targets: targets, lessons: lessons };
  }

  /** Группы предмета, которым разрешена отправка по списку из сессии, и группы без разрешения (их названия показываются отдельно). */
  function splitAllowed(targets, allowedGroupIds) {
    var allowed = [], blocked = [];
    (targets || []).forEach(function (t) { (allowedGroupIds.indexOf(t.groupId) >= 0 ? allowed : blocked).push(t); });
    return { allowed: allowed, blocked: blocked };
  }

  /**
   * Ближайший день после [today], когда у преподавателя есть занятие по [subject] (и нужного вида, если указан).
   * index — index.json сайта (semester, weekAnchor, holidays). Ищем не дальше 28 дней вперёд, иначе null.
   */
  function nextOccurrence(subject, today, view, index, kind) {
    var anchor = parseDay(index.weekAnchor), start = parseDay(index.semester.start), end = parseDay(index.semester.end);
    var holidays = (index.holidays || []).map(function (h) { return typeof h === 'string' ? h : h.date; });
    var list = view.lessons[subject] || [];
    var day = new Date(today.getTime());
    for (var i = 0; i < 28; i++) {
      day = new Date(day.getTime() + 86400000);
      var weekday = day.getUTCDay() === 0 ? 7 : day.getUTCDay();
      if (weekday === 7 || day < start || day > end || holidays.indexOf(dayText(day)) >= 0) continue;
      var week = weekNumber(day, anchor);
      var hit = list.some(function (l) { return l.weekday === weekday && (l.week === 0 || l.week === week) && (!kind || l.kind === kind); });
      if (hit) return day;
    }
    return null;
  }

  // ---------- файлы ----------

  var MAX_FILES = 5;
  var MAX_FILE_BYTES = 15 * 1024 * 1024;
  var BLOCKED_EXT = /\.(exe|apk|bat|cmd|com|msi|scr|js|jse|vbs|vbe|wsf|ps1|sh|jar|dll|lnk|reg|hta|cpl)$/i;

  /** Название файла как отправляем: без путей и управляющих знаков, не длиннее 200. */
  function cleanFileName(name) {
    var n = String(name).replace(/[\\/\u0000-\u001f]/g, '_').trim();
    return n.length > 200 ? n.slice(0, 200) : n;
  }

  /** Код ошибки (или null), если файл прикрепить нельзя. */
  function checkFile(name, size, alreadyAttached) {
    if (alreadyAttached >= MAX_FILES) return 'too_many_files';
    if (BLOCKED_EXT.test(String(name).trim())) return 'bad_file_type';
    if (size > MAX_FILE_BYTES) return 'file_too_big';
    if (size < 1) return 'empty_file';
    return null;
  }

  function formatSize(bytes) {
    if (bytes < 1024) return bytes + ' Б';
    if (bytes < 1024 * 1024) return Math.round(bytes / 1024) + ' КБ';
    return (bytes / 1048576).toFixed(1).replace('.', ',') + ' МБ';
  }

  // ---------- вход и сообщения ----------

  /** «QAG3V3FY» → «QAG3-V3FY» (так код удобнее читать и вводить). */
  function formatCode(code) {
    return code.length === 8 ? code.slice(0, 4) + '-' + code.slice(4) : code;
  }

  function plural(n, one, few, many) {
    var m10 = n % 10, m100 = n % 100;
    if (m10 === 1 && m100 !== 11) return one;
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
    return many;
  }

  /** Понятные сообщения по кодам сервера (те же слова, что в приложении: SharedApiException.message). */
  var MESSAGES = {
    bad_token: 'Вход закрыт. Войдите снова',
    too_many_attempts: 'Слишком много попыток. Подождите минуту и повторите',
    busy: 'Сервер сейчас занят входами. Повторите через минуту',
    bad_pair: 'Код входа не найден. Обновите код',
    forbidden_group: 'Одна из групп не входит в ваш список. Напишите автору приложения, чтобы её добавили',
    bad_groups: 'Выберите хотя бы одну группу',
    rate_limit: 'Слишком много отправок за час. Подождите немного и повторите',
    too_many: 'Слишком много заданий у группы. Удалите ненужные в приложении',
    too_many_files: 'К одному заданию можно прикрепить не больше 5 файлов',
    file_too_big: 'Файл слишком большой: можно до 15 МБ. Для больших файлов дайте ссылку на облако',
    empty_file: 'Файл пустой',
    quota: 'У вас закончилось место для файлов. Удалите старые задания с файлами в приложении или дайте ссылку на облако',
    storage_full: 'На сервере сейчас нет места для файлов. Дайте студентам ссылку на облако',
    bad_file_type: 'Такие файлы (программы, скрипты) отправлять нельзя',
    bad_file_name: 'Название файла не подошло. Переименуйте файл',
    bad_ticket: 'Загрузка файла не разрешена. Повторите отправку',
    no_object: 'Файл не дошёл до сервера. Повторите отправку',
    network: 'Нет связи с сервером. Проверьте интернет и повторите',
    server: 'Ошибка сервера. Повторите позже'
  };

  function messageFor(code, details) {
    if (MESSAGES[code]) return MESSAGES[code];
    return MESSAGES.server + (details ? ' (' + details + ')' : '');
  }

  return {
    splitName: splitName, sameTeacher: sameTeacher, parseDay: parseDay, dayText: dayText, weekNumber: weekNumber, moscowToday: moscowToday,
    buildTeacherView: buildTeacherView, splitAllowed: splitAllowed, nextOccurrence: nextOccurrence,
    MAX_FILES: MAX_FILES, MAX_FILE_BYTES: MAX_FILE_BYTES, cleanFileName: cleanFileName, checkFile: checkFile, formatSize: formatSize,
    formatCode: formatCode, plural: plural, messageFor: messageFor
  };
});
