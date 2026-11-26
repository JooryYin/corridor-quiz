-- Corridor Quiz update 1: suggestion box.
-- Run once in Supabase → SQL Editor → New query → Run.

alter table questions add column if not exists suggested boolean not null default false;
alter table questions add column if not exists suggested_by text;

create or replace function suggest_question(q text, opts text[], d text) returns bigint
language plpgsql security definer set search_path = public as $$
declare new_id bigint; clean text[];
begin
  q := btrim(q);
  if q is null or length(q) < 5 or length(q) > 140 then raise exception 'question length'; end if;
  select array_agg(btrim(o) order by i) into clean
    from unnest(opts) with ordinality as t(o, i) where btrim(o) <> '';
  if clean is null or array_length(clean, 1) < 2 or array_length(clean, 1) > 6 then raise exception 'need 2-6 answers'; end if;
  if exists (select 1 from unnest(clean) o where length(o) > 60) then raise exception 'answer too long'; end if;
  if d is null or length(d) < 8 or length(d) > 64 then raise exception 'bad device'; end if;
  if (select count(*) from questions where suggested_by = d and created_at > now() - interval '1 day') >= 3 then
    raise exception 'limit';
  end if;
  insert into questions (question, options, suggested, suggested_by) values (q, clean, true, d)
    returning id into new_id;
  return new_id;
end $$;

grant execute on function suggest_question(text, text[], text) to anon;
