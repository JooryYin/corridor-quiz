-- Corridor Quiz update 2: keeper mode (manage the quiz from the website with a password).
-- 1. Change CHANGE-ME on the last lines to your own keeper password (keep the quotes).
-- 2. Run once in Supabase → SQL Editor → New query → Run.
-- To change the password later, run only the last statement again with a new password.

create extension if not exists pgcrypto with schema extensions;

create table if not exists keeper_secret (
  id int primary key default 1 check (id = 1),
  hash text not null
);
alter table keeper_secret enable row level security;
revoke all on keeper_secret from anon, authenticated;

create or replace function keeper_ok(pw text) returns boolean
language sql security definer set search_path = public, extensions as $$
  select exists (select 1 from keeper_secret where hash = extensions.crypt(coalesce(pw, ''), hash));
$$;

create or replace function keeper_feature(pw text, qid bigint) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not keeper_ok(pw) then raise exception 'wrong password'; end if;
  update questions set is_current = false where is_current;
  update questions
     set is_current = true,
         created_at = case when suggested then now() else created_at end,
         suggested = false
   where id = qid;
end $$;

create or replace function keeper_delete(pw text, qid bigint) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not keeper_ok(pw) then raise exception 'wrong password'; end if;
  delete from questions where id = qid;
end $$;

create or replace function keeper_set_paper(pw text, qid bigint, counts int[]) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not keeper_ok(pw) then raise exception 'wrong password'; end if;
  if exists (select 1 from unnest(counts) c where c < 0 or c > 100000) then raise exception 'bad count'; end if;
  update questions set paper_counts = counts where id = qid;
end $$;

create or replace function keeper_add(pw text, q text, opts text[], make_current boolean) returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare new_id bigint; clean text[];
begin
  if not keeper_ok(pw) then raise exception 'wrong password'; end if;
  q := btrim(q);
  if q is null or length(q) < 3 or length(q) > 140 then raise exception 'question length'; end if;
  select array_agg(btrim(o) order by i) into clean
    from unnest(opts) with ordinality as t(o, i) where btrim(o) <> '';
  if clean is null or array_length(clean, 1) < 2 or array_length(clean, 1) > 6 then raise exception 'need 2-6 answers'; end if;
  if make_current then update questions set is_current = false where is_current; end if;
  insert into questions (question, options, is_current) values (q, clean, coalesce(make_current, false))
    returning id into new_id;
  return new_id;
end $$;

grant execute on function keeper_ok(text), keeper_feature(text, bigint), keeper_delete(text, bigint),
  keeper_set_paper(text, bigint, int[]), keeper_add(text, text, text[], boolean) to anon;

-- Your keeper password: replace CHANGE-ME (share it only with the other keeper).
insert into keeper_secret (id, hash) values (1, extensions.crypt('CHANGE-ME', extensions.gen_salt('bf')))
on conflict (id) do update set hash = excluded.hash;
