-- Часть 11: потолок скачиваний считается на пару «файл + группа», сутки по Москве, очистка счётчиков при любом скачивании.
-- Меняет только функции get_group_file, put_group_file и put_teacher_file (таблицы и права не трогает). Откат: выполнить прежнюю версию функции из git (коммит cecd219).
-- Применять по слову владельца; сначала на тестовой копии.

-- get_group_file: как в Части 6, плюс файлы из Storage (ссылка вместо base64, месячный потолок трафика 4,5 ГБ).
-- Часть 11: потолок «100 скачиваний в сутки» считается на пару «файл + группа» (файл преподавателя один на все группы, лимит не должен
-- быть общим); сутки по Москве; очистка старых счётчиков идёт при любом скачивании, в том числе файлов из Storage.
create or replace function public.get_group_file(p_group text, p_id uuid) returns jsonb
language plpgsql security definer set search_path = '' set statement_timeout = '25s' as $$
declare r public.group_files%rowtype; cnt int; total bigint; base text; d date := (now() at time zone 'Europe/Moscow')::date;
begin
  if p_group is null or p_group !~ '^[a-z0-9-]{3,40}$' then raise exception 'bad_group'; end if;
  select * into r from public.group_files f
   where f.id = p_id and (f.group_id = p_group or (f.group_id like 'teacher-%' and exists (
     select 1 from public.group_homework h, jsonb_array_elements(h.files) e
      where h.group_id = p_group and h.author is not null and not h.deleted and e->>'id' = p_id::text)));
  if not found then raise exception 'no_file'; end if;
  -- счётчик ведётся по ключу «файл + группа» (md5 → uuid): таблица и её ключ остаются прежними
  insert into public.download_file_day (day, file_id, n) values (d, md5(p_id::text || '|' || p_group)::uuid, 1)
    on conflict (day, file_id) do update set n = public.download_file_day.n + 1
    returning n into cnt;
  delete from public.download_file_day where day < d - 7;
  if cnt > 100 then raise exception 'download_limit'; end if;
  if r.storage_path is not null then
    select value into base from public.app_config where key = 'storage_url';
    if base is null then raise exception 'storage_not_configured'; end if;
    insert into public.download_month (month, bytes) values (date_trunc('month', now())::date, r.size)
      on conflict (month) do update set bytes = public.download_month.bytes + excluded.bytes
      returning bytes into total;
    if total > 4831838208 then raise exception 'download_limit'; end if;
    delete from public.download_month where month < (date_trunc('month', now()) - interval '6 months')::date;
    return jsonb_build_object('name', r.name, 'size', r.size, 'url', base || '/storage/v1/object/public/homework/' || r.storage_path);
  end if;
  insert into public.download_day (day, bytes) values (d, r.size)
    on conflict (day) do update set bytes = public.download_day.bytes + excluded.bytes
    returning bytes into total;
  if total > 167772160 then raise exception 'download_limit'; end if;
  delete from public.download_day where day < d - 7;
  return jsonb_build_object('name', r.name, 'data', translate(encode(r.data, 'base64'), E'\n\r', ''));
end $$;

-- Часть 11 (продолжение): программы и скрипты нельзя прикреплять и старосте, и по старому пути преподавателя
-- (раньше список запрещённых типов проверялся только в register_teacher_file). Таблицы и права не меняются.

create or replace function public.put_group_file(p_token text, p_id uuid, p_name text, p_data text) returns void
language plpgsql security definer set search_path = '' set statement_timeout = '25s' as $$
declare g text := public.editor_group(p_token); bytes bytea; used bigint;
begin
  if lower(coalesce(p_name, '')) ~ '\.(exe|apk|bat|cmd|com|msi|scr|js|jse|vbs|vbe|wsf|ps1|sh|jar|dll|lnk|reg|hta|cpl)$' then raise exception 'bad_file_type'; end if;
  if length(p_data) > 11500000 then raise exception 'file_too_big'; end if;
  bytes := decode(p_data, 'base64');
  if octet_length(bytes) > 8388608 or octet_length(bytes) = 0 then raise exception 'file_too_big'; end if;
  perform public.purge_group_files(g);
  select coalesce(sum(size), 0) into used from public.group_files where group_id = g;
  if used + octet_length(bytes) > 157286400 then raise exception 'quota'; end if;
  insert into public.group_files (id, group_id, name, size, data)
  values (p_id, g, left(p_name, 200), octet_length(bytes), bytes)
  on conflict (id) do nothing;
end $$;

create or replace function public.put_teacher_file(p_token text, p_id uuid, p_name text, p_data text) returns void
language plpgsql security definer set search_path = '' set statement_timeout = '25s' as $$
declare t public.teacher_codes%rowtype; g text; bytes bytea; used bigint;
begin
  if lower(coalesce(p_name, '')) ~ '\.(exe|apk|bat|cmd|com|msi|scr|js|jse|vbs|vbe|wsf|ps1|sh|jar|dll|lnk|reg|hta|cpl)$' then raise exception 'bad_file_type'; end if;
  t := public.teacher_row(p_token);
  g := 'teacher-' || substr(md5(lower(t.teacher)), 1, 8);
  if length(p_data) > 11500000 then raise exception 'file_too_big'; end if;
  bytes := decode(p_data, 'base64');
  if octet_length(bytes) > 8388608 or octet_length(bytes) = 0 then raise exception 'file_too_big'; end if;
  perform public.purge_teacher_files(g);
  select coalesce(sum(size), 0) into used from public.group_files where group_id = g;
  if used + octet_length(bytes) > 157286400 then raise exception 'quota'; end if;
  insert into public.group_files (id, group_id, name, size, data)
  values (p_id, g, left(p_name, 200), octet_length(bytes), bytes)
  on conflict (id) do nothing;
end $$;
