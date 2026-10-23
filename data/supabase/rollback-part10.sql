-- ============================================================================
-- Убрать Часть 10 (страница «Отправить ДЗ с компьютера», файлы в Storage). Выполнять целиком, одной командой (в SQL Editor).
-- Порядок:
--  1) Если уже есть файлы в Storage, СНАЧАЛА их надо стереть правильно (прямой delete из storage.objects файл не удаляет):
--       delete from public.group_files where storage_path is not null;   -- триггер кладёт пути в корзину
--       select public.maintain_web();                                    -- просит API Storage удалить; повторять раз в минуту,
--       select count(*) from storage.objects where bucket_id = 'homework';  -- пока не будет 0
--     Пока в бакете есть объекты, этот скрипт остановится сам (проверка ниже).
--  2) Скрипт возвращает три старые функции (текст из backup-before-part10.sql), снимает задание и политики, удаляет новые функции
--     и таблицы, возвращает прежние ограничения group_files. Данные Частей 1–9 не затрагиваются.
--  3) Пустой бакет homework и расширение pg_net остаются (Storage запрещает прямое удаление бакета; пустой бакет безвреден).
--     Бакет можно удалить кнопкой в разделе Storage панели Supabase.
-- ============================================================================
begin;

do $$ begin
  if exists (select 1 from storage.objects where bucket_id = 'homework') then
    raise exception 'В бакете homework ещё есть файлы: сначала удалите их через group_files и maintain_web() (см. шаг 1 в начале файла)';
  end if;
end $$;

select cron.unschedule('unigraf-maintain-web');

drop policy homework_insert on storage.objects;
drop policy homework_trash_select on storage.objects;
drop policy homework_trash_delete on storage.objects;

-- Старые функции (create or replace сохраняет права доступа)
-- check_teacher (Часть 5)
create or replace function public.check_teacher(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r public.teacher_codes%rowtype;
begin
  r := public.teacher_row(p_token);
  return jsonb_build_object('teacher', r.teacher, 'groups', to_jsonb(r.groups));
end $$;

-- put_teacher_homework (Часть 5)
create or replace function public.put_teacher_homework(p_token text, p_row jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  t public.teacher_codes%rowtype; v_batch uuid; fl jsonb; tg jsonb; e record; ids text[] := '{}'; gid text; sg smallint;
  is_new boolean; n int; g text;
begin
  t := public.teacher_row(p_token);
  perform public.purge_tombstones();
  fl := coalesce(p_row->'files', '[]'::jsonb);
  if jsonb_typeof(fl) <> 'array' or jsonb_array_length(fl) > 5 then raise exception 'too_many_files'; end if;
  tg := p_row->'groups';
  if tg is null or jsonb_typeof(tg) <> 'array' or jsonb_array_length(tg) < 1 or jsonb_array_length(tg) > 80 then raise exception 'bad_groups'; end if;
  -- каждая цель: {id, subgroup?}; только группы из списка преподавателя, без повторов
  for e in select value from jsonb_array_elements(tg) loop
    gid := e.value->>'id';
    if gid is null or not (gid = any (t.groups)) then raise exception 'forbidden_group'; end if;
    if gid = any (ids) then raise exception 'bad_groups'; end if;
    ids := ids || gid;
  end loop;

  v_batch := coalesce((p_row->>'batch_id')::uuid, gen_random_uuid());
  if exists (select 1 from public.group_homework where batch_id = v_batch and author is distinct from t.teacher) then raise exception 'bad_batch'; end if;
  is_new := not exists (select 1 from public.group_homework where batch_id = v_batch and author = t.teacher);
  if is_new then
    select count(distinct batch_id) into n from public.group_homework where author = t.teacher and not deleted;
    if n >= 300 then raise exception 'too_many'; end if;
    select count(distinct batch_id) into n from public.group_homework where author = t.teacher and updated_at > now() - interval '1 hour';
    if n >= 30 then raise exception 'rate_limit'; end if;
  end if;

  -- группы, которых больше нет в пачке, снимаем
  update public.group_homework set deleted = true, updated_at = now()
   where batch_id = v_batch and author = t.teacher and not deleted and not (group_id = any (ids));

  foreach g in array ids loop
    sg := null;
    select nullif(x.value->>'subgroup', '')::smallint into sg from jsonb_array_elements(tg) x where x.value->>'id' = g;
    update public.group_homework set subject = p_row->>'subject', body = p_row->>'body', due_date = (p_row->>'due_date')::date,
           kind = nullif(p_row->>'kind', ''), subgroup = sg, files = fl, deleted = false, updated_at = now()
     where batch_id = v_batch and author = t.teacher and group_id = g;
    if not found then
      select count(*) into n from public.group_homework where group_id = g and author is not null and not deleted;
      if n >= 100 then raise exception 'too_many'; end if;
      insert into public.group_homework (group_id, subject, body, due_date, kind, subgroup, files, deleted, updated_at, author, batch_id)
      values (g, p_row->>'subject', p_row->>'body', (p_row->>'due_date')::date, nullif(p_row->>'kind', ''), sg, fl, false, now(), t.teacher, v_batch);
    end if;
  end loop;
  perform public.purge_teacher_files('teacher-' || substr(md5(lower(t.teacher)), 1, 8));
  return v_batch;
end $$;

-- get_group_file (Часть 6, действующая версия)
create or replace function public.get_group_file(p_group text, p_id uuid) returns jsonb
language plpgsql security definer set search_path = '' set statement_timeout = '25s' as $$
declare r public.group_files%rowtype; cnt int; total bigint;
begin
  if p_group is null or p_group !~ '^[a-z0-9-]{3,40}$' then raise exception 'bad_group'; end if;
  select * into r from public.group_files f
   where f.id = p_id and (f.group_id = p_group or (f.group_id like 'teacher-%' and exists (
     select 1 from public.group_homework h, jsonb_array_elements(h.files) e
      where h.group_id = p_group and h.author is not null and not h.deleted and e->>'id' = p_id::text)));
  if not found then raise exception 'no_file'; end if;
  insert into public.download_file_day (day, file_id, n) values (current_date, p_id, 1)
    on conflict (day, file_id) do update set n = public.download_file_day.n + 1
    returning n into cnt;
  if cnt > 100 then raise exception 'download_limit'; end if;
  insert into public.download_day (day, bytes) values (current_date, r.size)
    on conflict (day) do update set bytes = public.download_day.bytes + excluded.bytes
    returning bytes into total;
  if total > 167772160 then raise exception 'download_limit'; end if;
  delete from public.download_day where day < current_date - 7;
  delete from public.download_file_day where day < current_date - 7;
  -- encode(..., 'base64') вставляет перенос строки каждые 76 знаков, а приложение (Dart) такой текст не читает:
  -- файлы больше ~57 байт не скачивались. Переносы убираем.
  return jsonb_build_object('name', r.name, 'data', translate(encode(r.data, 'base64'), E'\n\r', ''));
end $$;


drop trigger group_files_trash on public.group_files;
drop function public.group_files_to_trash(), public.maintain_web(), public.register_teacher_file(text, uuid, text, text),
  public.teacher_upload_ticket(text), public.upload_name_ok(text), public.in_trash(text),
  public.web_pair_start(), public.web_pair_poll(uuid, text), public.web_pair_approve(text, text, text),
  public.web_sessions_list(text), public.web_session_revoke(text, uuid), public.web_session_end(text),
  public.web_session_close(text), public.teacher_row_any(text),
  public.web_reject(text), public.web_locked(), public.web_hit(text, int), public.web_hash(text);
drop table public.web_pairs, public.web_sessions, public.web_limits, public.upload_tickets, public.storage_trash,
  public.download_month, public.app_config;

alter table public.group_files drop constraint group_files_data_or_path;
alter table public.group_files drop constraint group_files_size_check;
alter table public.group_files add constraint group_files_size_check check (size between 1 and 8388608);
alter table public.group_files drop column storage_path;
alter table public.group_files alter column data set not null;

commit;
