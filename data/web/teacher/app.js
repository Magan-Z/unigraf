// Страница «Отправить ДЗ с компьютера» для преподавателей.
// Вход по QR с телефона (там же подтверждается числом), форма, загрузка файлов в хранилище, отправка. Ничего не запоминается:
// токен сессии живёт только в памяти вкладки. После успешной отправки сервер сам закрывает вход.
(function () {
  'use strict';

  // Не показываем страницу внутри чужой страницы (защита от «подсовывания» формы в рамке)
  if (window.top !== window.self) { document.documentElement.hidden = true; return; }

  var L = window.TeacherLogic;
  var cfg = window.UNIGRAF_TEACHER;
  var $ = function (id) { return document.getElementById(id); };

  var PAIR_SECONDS = 180;          // сколько живёт код входа
  var AUTO_REFRESHES = 4;          // сколько раз код обновляется сам, потом ждёт кнопку (чтобы не плодить запросы на брошенной странице)
  var IDLE_MS = 5 * 60 * 1000;     // без движения мыши и нажатий вход закрывается
  var HARD_MS = 3 * 60 * 60 * 1000; // жёсткий предел сессии
  var HEARTBEAT_MS = 3 * 60 * 1000; // пока страница в работе, сервер тоже видит, что вход нужен (у него свой предел 15 минут)

  var state = {
    pair: null, refreshes: 0, pollTimer: null, tickTimer: null,
    session: null,                  // { token, teacher, groups, since }
    view: null, index: null,        // расписание преподавателя и index.json
    selected: {},                   // ключ «группа|подгруппа» → true
    manualDue: null, files: [], busy: false, lastActivity: Date.now(), watchTimer: null, heartbeatTimer: null
  };

  // ---------- сервер ----------

  function ApiError(code, details) { this.code = code; this.details = details; }

  var KNOWN = ['bad_token', 'too_many_attempts', 'busy', 'bad_pair', 'forbidden_group', 'bad_groups', 'rate_limit', 'too_many', 'too_many_files',
    'file_too_big', 'quota', 'storage_full', 'bad_file_type', 'bad_file_name', 'bad_ticket', 'no_object'];

  function rpc(fn, args, opts) {
    opts = opts || {};
    var ctl = new AbortController();
    var timer = setTimeout(function () { ctl.abort(); }, opts.timeout || 20000);
    return fetch(cfg.api + '/rest/v1/rpc/' + fn, {
      method: 'POST', cache: 'no-store', keepalive: !!opts.keepalive, signal: ctl.signal,
      headers: { apikey: cfg.key, 'Content-Type': 'application/json' }, body: JSON.stringify(args || {})
    }).catch(function () { throw new ApiError('network'); }).then(function (res) {
      return res.text().then(function (text) {
        clearTimeout(timer);
        var data = null;
        try { data = text ? JSON.parse(text) : null; } catch (e) { /* не JSON */ }
        if (res.ok) return data;
        var msg = data && data.message;
        throw new ApiError(KNOWN.indexOf(msg) >= 0 ? msg : 'server', msg);
      });
    }, function (e) { clearTimeout(timer); throw e; });
  }

  function errText(e) {
    if (e && e.code) return L.messageFor(e.code, e.code === 'server' ? e.details : undefined);
    return L.messageFor('server');
  }

  function uuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    var b = crypto.getRandomValues(new Uint8Array(16));
    b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
    var h = Array.prototype.map.call(b, function (x) { return ('0' + x.toString(16)).slice(-2); }).join('');
    return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20);
  }

  // ---------- экраны ----------

  var VIEWS = ['boot', 'login', 'form', 'done', 'ended'];
  function show(name) {
    VIEWS.forEach(function (v) { $('view-' + v).hidden = v !== name; });
    $('logout').hidden = name !== 'form';
    var heading = document.querySelector('#view-' + name + ' h1');
    if (heading) { heading.setAttribute('tabindex', '-1'); heading.focus({ preventScroll: true }); }
  }

  function setError(id, text) {
    var el = $(id);
    el.hidden = !text;
    el.textContent = text || '';
  }

  // ---------- вход ----------

  function drawQr(text) {
    var canvas = $('qr');
    var qr = window.qrcode(0, 'M');
    qr.addData(text);
    qr.make();
    var n = qr.getModuleCount(), quiet = 4, scale = Math.floor(canvas.width / (n + quiet * 2));
    var size = (n + quiet * 2) * scale;
    var ctx = canvas.getContext('2d');
    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    var offset = Math.floor((canvas.width - size) / 2) + quiet * scale;
    ctx.fillStyle = '#000';
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (qr.isDark(r, c)) ctx.fillRect(offset + c * scale, offset + r * scale, scale, scale);
      }
    }
  }

  function stopPairing() {
    clearInterval(state.pollTimer); clearInterval(state.tickTimer);
    state.pollTimer = state.tickTimer = null;
    state.pair = null;
  }

  /** Старый QR и число после отказа или устаревания не оставляем на экране: по ним уже не войти. */
  function clearPairDisplay() {
    var canvas = $('qr'), ctx = canvas.getContext('2d');
    ctx.fillStyle = '#eee';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    $('pair-number').textContent = '····';
    $('pair-code').textContent = '········';
  }

  function startPairing(auto) {
    stopPairing();
    if (!auto) state.refreshes = 0;
    show('login');
    $('refresh-code').hidden = true;
    $('qr-timer').textContent = 'Готовим код…';
    setError('login-error', '');
    rpc('web_pair_start', {}).then(function (p) {
      state.pair = { id: p.id, secret: p.secret, until: Date.now() + PAIR_SECONDS * 1000 };
      drawQr('unigraf://pair/' + p.id);
      $('pair-number').textContent = p.number;
      $('pair-code').textContent = L.formatCode(p.code);
      tickPairing();
      state.tickTimer = setInterval(tickPairing, 1000);
      state.pollTimer = setInterval(pollPairing, 2000);
    }).catch(function (e) {
      clearPairDisplay();
      $('qr-timer').textContent = '';
      $('refresh-code').hidden = false;
      setError('login-error', errText(e));
    });
  }

  function tickPairing() {
    if (!state.pair) return;
    var left = Math.max(0, Math.round((state.pair.until - Date.now()) / 1000));
    if (left === 0) { pairingExpired(); return; }
    $('qr-timer').textContent = 'Код действует ещё ' + Math.floor(left / 60) + ':' + ('0' + (left % 60)).slice(-2);
  }

  function pairingExpired() {
    if (state.refreshes < AUTO_REFRESHES) { state.refreshes++; startPairing(true); return; }
    stopPairing();
    clearPairDisplay();
    $('qr-timer').textContent = 'Код устарел';
    $('refresh-code').hidden = false;
  }

  var polling = false;
  function pollPairing() {
    if (!state.pair || polling) return;
    var p = state.pair;
    polling = true;
    rpc('web_pair_poll', { p_id: p.id, p_secret: p.secret }, { timeout: 8000 }).then(function (r) {
      polling = false;
      if (state.pair !== p) return;
      if (r.status === 'ok') { stopPairing(); loggedIn(r); }
      else if (r.status === 'denied') {
        stopPairing();
        clearPairDisplay();
        $('qr-timer').textContent = '';
        $('refresh-code').hidden = false;
        setError('login-error', 'Вход отклонён: число введено неверно. Обновите код и попробуйте ещё раз.');
      } else if (r.status === 'expired' || r.status === 'used') pairingExpired();
    }).catch(function (e) {
      polling = false;
      if (e.code === 'bad_pair') pairingExpired(); // запрос уже стёрт сервером
      // обрыв связи: просто пробуем в следующий раз
    });
  }

  // ---------- после входа ----------

  function loggedIn(r) {
    state.session = { token: r.token, teacher: r.teacher, groups: r.groups || [], since: Date.now() };
    state.lastActivity = Date.now();
    $('who').textContent = r.teacher;
    startWatching();
    show('boot');
    $('view-boot').firstElementChild.textContent = 'Загружаем ваше расписание…';
    loadSchedule();
  }

  function fetchJson(path) {
    return fetch(cfg.siteBase + path, { cache: 'no-cache' }).then(function (res) {
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return res.json();
    });
  }

  function loadSchedule() {
    var groups = state.session.groups;
    Promise.all([fetchJson('index.json')].concat(groups.map(function (id) { return fetchJson('groups/' + id + '.json').catch(function () { return null; }); })))
      .then(function (all) {
        state.index = all[0];
        var schedules = all.slice(1).filter(Boolean);
        state.view = L.buildTeacherView(state.session.teacher, schedules);
        renderForm();
        show('form');
      }).catch(function () {
        var box = $('view-boot');
        box.firstElementChild.textContent = 'Не удалось загрузить расписание.';
        if (!$('boot-retry')) {
          var b = document.createElement('button');
          b.type = 'button'; b.id = 'boot-retry'; b.className = 'btn secondary'; b.textContent = 'Повторить';
          b.addEventListener('click', function () { b.remove(); box.firstElementChild.textContent = 'Загружаем ваше расписание…'; loadSchedule(); });
          box.appendChild(b);
        }
      });
  }

  // ---------- форма ----------

  function currentTargets() {
    var subject = $('subject').value;
    return L.splitAllowed(state.view.targets[subject], state.session.groups);
  }

  function targetKey(t) { return t.groupId + '|' + (t.subgroup == null ? '' : t.subgroup); }

  function currentKind() {
    var el = document.querySelector('input[name=kind]:checked');
    return el && el.value ? el.value : null;
  }

  function renderForm() {
    var sel = $('subject');
    sel.textContent = '';
    state.view.subjects.forEach(function (s) {
      var o = document.createElement('option');
      o.value = s; o.textContent = s;
      sel.appendChild(o);
    });
    $('no-subjects').hidden = state.view.subjects.length > 0;
    sel.disabled = state.view.subjects.length === 0;
    onSubjectChanged();
  }

  function onSubjectChanged() {
    state.manualDue = null;
    state.selected = {};
    if ($('subject').value) {
      currentTargets().allowed.forEach(function (t) { state.selected[targetKey(t)] = true; });
    }
    renderGroups();
    updateDue();
    updateSendState();
  }

  function renderGroups() {
    var box = $('groups');
    box.textContent = '';
    var subject = $('subject').value;
    var r = subject ? currentTargets() : { allowed: [], blocked: [] };
    r.allowed.forEach(function (t) {
      var label = document.createElement('label');
      label.className = 'chip';
      var cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.checked = !!state.selected[targetKey(t)];
      cb.addEventListener('change', function () {
        if (cb.checked) state.selected[targetKey(t)] = true; else delete state.selected[targetKey(t)];
        updateToggleAll(r.allowed);
        updateSendState();
      });
      label.appendChild(cb);
      label.appendChild(document.createTextNode(t.label));
      box.appendChild(label);
    });
    $('no-groups').hidden = !subject || r.allowed.length > 0;
    $('toggle-all').hidden = r.allowed.length < 2;
    var blocked = $('blocked');
    blocked.hidden = r.blocked.length === 0;
    blocked.textContent = r.blocked.length ? 'Нет разрешения на отправку: ' + r.blocked.map(function (t) { return t.label; }).join(', ') + '. Напишите автору приложения.' : '';
    updateToggleAll(r.allowed);
  }

  function updateToggleAll(allowed) {
    var all = allowed.length > 0 && allowed.every(function (t) { return state.selected[targetKey(t)]; });
    $('toggle-all').textContent = all ? 'Снять все' : 'Выбрать все';
  }

  function selectedTargets() {
    return $('subject').value ? currentTargets().allowed.filter(function (t) { return state.selected[targetKey(t)]; }) : [];
  }

  function updateDue() {
    var subject = $('subject').value, due = $('due'), hint = $('due-hint');
    if (state.manualDue) { due.value = state.manualDue; hint.textContent = 'Выбрано вручную'; return; }
    var auto = subject ? L.nextOccurrence(subject, L.moscowToday(), state.view, state.index, currentKind()) : null;
    due.value = auto ? L.dayText(auto) : '';
    hint.textContent = !subject ? '' : auto ? 'Подставлено автоматически: ближайшее ваше занятие' : 'Занятий не найдено: выберите дату';
  }

  function updateSendState() {
    var ok = !!$('subject').value && $('body').value.trim().length > 0 && !!$('due').value && selectedTargets().length > 0 && !state.busy;
    $('send').disabled = !ok;
    $('send-note').textContent = '';
  }

  // ---------- файлы ----------

  function addFiles(list) {
    setError('form-error', '');
    var problems = [];
    Array.prototype.forEach.call(list, function (file) {
      var code = L.checkFile(file.name, file.size, state.files.length);
      if (code) { problems.push(file.name + ': ' + L.messageFor(code)); return; }
      state.files.push({ file: file, name: L.cleanFileName(file.name), progress: 0, status: '', reg: null });
    });
    renderFiles();
    if (problems.length) setError('form-error', problems.join('\n'));
  }

  function renderFiles() {
    var ul = $('files');
    ul.textContent = '';
    state.files.forEach(function (f, i) {
      var li = document.createElement('li');
      var name = document.createElement('span');
      name.className = 'name';
      name.textContent = f.name + ' (' + L.formatSize(f.file.size) + ')';
      li.appendChild(name);
      var rm = document.createElement('button');
      rm.type = 'button'; rm.className = 'link small'; rm.textContent = 'Убрать'; rm.disabled = state.busy;
      rm.addEventListener('click', function () { state.files.splice(i, 1); renderFiles(); });
      li.appendChild(rm);
      if (state.busy || f.status) {
        var bar = document.createElement('progress');
        bar.max = 100; bar.value = f.reg ? 100 : f.progress;
        li.appendChild(bar);
        var st = document.createElement('span');
        st.className = 'state' + (f.error ? ' bad' : '');
        st.textContent = f.error || f.status;
        li.appendChild(st);
      }
      ul.appendChild(li);
    });
    $('file-input').disabled = state.files.length >= L.MAX_FILES || state.busy;
  }

  function uploadFile(ticket, id, file, onProgress) {
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      xhr.open('POST', cfg.api + '/storage/v1/object/homework/' + ticket + '/' + id);
      xhr.setRequestHeader('apikey', cfg.key);
      xhr.setRequestHeader('Authorization', 'Bearer ' + cfg.key);
      xhr.setRequestHeader('Content-Type', 'application/octet-stream');
      xhr.timeout = 10 * 60 * 1000;
      xhr.upload.onprogress = function (ev) { if (ev.lengthComputable) onProgress(Math.round(ev.loaded / ev.total * 100)); };
      xhr.onload = function () {
        if (xhr.status >= 200 && xhr.status < 300) return resolve();
        var body = xhr.responseText || '';
        if (xhr.status === 413 || body.indexOf('EntityTooLarge') >= 0) return reject(new ApiError('file_too_big'));
        if (xhr.status === 403 || body.indexOf('AccessDenied') >= 0) return reject(new ApiError('bad_ticket'));
        reject(new ApiError('server', 'хранилище: HTTP ' + xhr.status));
      };
      xhr.onerror = xhr.ontimeout = function () { reject(new ApiError('network')); };
      xhr.send(file);
    });
  }

  // ---------- отправка ----------

  function setBusy(busy) {
    state.busy = busy;
    ['subject', 'body', 'due'].forEach(function (id) { $(id).disabled = busy; });
    Array.prototype.forEach.call(document.querySelectorAll('#groups input, input[name=kind], #toggle-all'), function (el) { el.disabled = busy; });
    $('send').textContent = busy ? 'Отправляем…' : 'Отправить';
    renderFiles();
    updateSendState();
  }

  function send() {
    if (state.busy || $('send').disabled) return;
    var token = state.session.token;
    var targets = selectedTargets();
    var subject = $('subject').value;
    setError('form-error', '');
    setBusy(true);
    touch();

    var ticketPromise = null;
    function ticket() {
      return ticketPromise || (ticketPromise = rpc('teacher_upload_ticket', { p_token: token }).then(function (r) { return r.ticket; }));
    }
    var chain = Promise.resolve();
    state.files.forEach(function (f) {
      chain = chain.then(function () {
        if (f.reg) return;
        f.error = ''; f.status = 'Загружаем…'; f.progress = 0; renderFiles();
        var id = uuid();
        return ticket().then(function (tk) {
          return uploadFile(tk, id, f.file, function (pct) { f.progress = pct; touch(); renderFiles(); }).then(function () {
            f.status = 'Проверяем…'; renderFiles();
            return rpc('register_teacher_file', { p_token: token, p_id: id, p_ticket: tk, p_name: f.name }, { timeout: 30000 });
          });
        }).then(function () {
          f.reg = { id: id, name: f.name, size: f.file.size };
          f.status = 'Загружен'; renderFiles();
        }).catch(function (e) { f.error = errText(e); f.status = ''; ticketPromise = null; throw e; });
      });
    });
    chain.then(function () {
      var row = {
        subject: subject, body: $('body').value.trim(), due_date: $('due').value, kind: currentKind(),
        groups: targets.map(function (t) { return t.subgroup == null ? { id: t.groupId } : { id: t.groupId, subgroup: t.subgroup }; }),
        files: state.files.map(function (f) { return f.reg; })
      };
      return rpc('put_teacher_homework', { p_token: token, p_row: row }, { timeout: 30000 });
    }).then(function () {
      var n = targets.map(function (t) { return t.groupId; }).filter(function (g, i, a) { return a.indexOf(g) === i; }).length;
      finished('Задание «' + subject + '» отправлено: ' + n + ' ' + L.plural(n, 'группа', 'группы', 'групп') + '.');
    }).catch(function (e) {
      setBusy(false);
      if (e && e.code === 'bad_token') { endSession(L.messageFor('bad_token'), true); return; }
      setError('form-error', errText(e) + (state.files.some(function (f) { return f.reg; }) ? '\nУже загруженные файлы повторно не грузятся.' : ''));
    });
  }

  function finished(text) {
    clearTimers();
    state.session = null; state.files = []; state.view = null;
    $('body').value = '';
    $('done-text').textContent = text;
    show('done');
  }

  // ---------- закрытие входа, бездействие ----------

  function touch() { state.lastActivity = Date.now(); }

  function startWatching() {
    clearTimers();
    state.watchTimer = setInterval(watch, 1000);
    state.heartbeatTimer = setInterval(function () {
      if (!state.session || state.busy) return;
      rpc('check_teacher', { p_token: state.session.token }, { timeout: 10000 }).catch(function (e) {
        if (e && e.code === 'bad_token') endSession(L.messageFor('bad_token'), true);
      });
    }, HEARTBEAT_MS);
  }

  function clearTimers() {
    clearInterval(state.watchTimer); clearInterval(state.heartbeatTimer);
    state.watchTimer = state.heartbeatTimer = null;
  }

  function watch() {
    if (!state.session) return;
    var idle = Date.now() - state.lastActivity, hard = Date.now() - state.session.since;
    if (hard >= HARD_MS) { endSession('Прошло 3 часа: вход закрыт.', false); return; }
    if (idle >= IDLE_MS) { endSession('Вход закрыт: страницу долго не трогали.', false); return; }
    var left = Math.ceil((IDLE_MS - idle) / 1000);
    $('idle-note').textContent = left <= 60
      ? 'Вход закроется через ' + left + ' с, если не трогать страницу.'
      : 'Вход закроется сам после отправки или если 5 минут не трогать страницу.';
  }

  function endSession(text, alreadyClosed) {
    var s = state.session;
    clearTimers();
    state.session = null; state.files = []; state.view = null; state.busy = false;
    $('body').value = '';
    if (s && !alreadyClosed) rpc('web_session_end', { p_token: s.token }, { timeout: 8000 }).catch(function () { /* сервер сам закроет по сроку */ });
    $('ended-text').textContent = text;
    show('ended');
  }

  // ---------- события ----------

  ['mousemove', 'mousedown', 'keydown', 'touchstart', 'scroll', 'input', 'wheel'].forEach(function (ev) {
    window.addEventListener(ev, touch, { passive: true, capture: true });
  });

  // Закрыли вкладку: сразу закрываем вход на сервере (запрос «keepalive» уходит и при закрытии страницы)
  window.addEventListener('pagehide', function () {
    if (state.session) rpc('web_session_end', { p_token: state.session.token }, { keepalive: true, timeout: 5000 }).catch(function () {});
  });

  $('refresh-code').addEventListener('click', function () { startPairing(false); });
  $('relogin').addEventListener('click', function () { startPairing(false); });
  $('logout').addEventListener('click', function () { endSession('Вы вышли. Вход на этом компьютере закрыт.', false); });
  $('subject').addEventListener('change', onSubjectChanged);
  $('body').addEventListener('input', function () { $('body-count').textContent = $('body').value.length; updateSendState(); });
  $('due').addEventListener('change', function () { state.manualDue = $('due').value || null; updateDue(); updateSendState(); });
  Array.prototype.forEach.call(document.querySelectorAll('input[name=kind]'), function (r) {
    r.addEventListener('change', function () { updateDue(); updateSendState(); });
  });
  $('toggle-all').addEventListener('click', function () {
    var allowed = currentTargets().allowed;
    var all = allowed.every(function (t) { return state.selected[targetKey(t)]; });
    state.selected = {};
    if (!all) allowed.forEach(function (t) { state.selected[targetKey(t)] = true; });
    renderGroups(); updateSendState();
  });
  $('file-input').addEventListener('change', function (e) { addFiles(e.target.files); e.target.value = ''; });
  var drop = $('drop');
  ['dragenter', 'dragover'].forEach(function (ev) { drop.addEventListener(ev, function (e) { e.preventDefault(); drop.classList.add('over'); }); });
  ['dragleave', 'drop'].forEach(function (ev) { drop.addEventListener(ev, function (e) { e.preventDefault(); drop.classList.remove('over'); }); });
  drop.addEventListener('drop', function (e) { if (!state.busy) addFiles(e.dataTransfer.files); });
  // Файл, брошенный мимо зоны, не должен открываться в этой вкладке и ронять форму
  ['dragover', 'drop'].forEach(function (ev) { window.addEventListener(ev, function (e) { e.preventDefault(); }); });
  $('form').addEventListener('submit', function (e) { e.preventDefault(); send(); });

  startPairing(false);
})();
