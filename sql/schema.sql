-- Corridor Quiz: run this once in Supabase → SQL Editor → New query → Run.

create table questions (
  id bigint generated always as identity primary key,
  question text not null,
  options text[] not null,
  paper_counts int[] not null default '{}',   -- tallies from paper/whiteboard, added to online votes
  is_current boolean not null default false,  -- the question of the week
  created_at timestamptz not null default now()
);

create table votes (
  question_id bigint not null references questions(id) on delete cascade,
  device_id text not null,
  choice int not null,
  voted_at timestamptz not null default now(),
  primary key (question_id, device_id)        -- one vote per phone per question
);

alter table questions enable row level security;
alter table votes enable row level security;

-- Visitors may read questions. Nobody may touch the votes table directly:
-- they vote and read totals only through the functions below.
create policy "anyone can read questions" on questions for select using (true);

create or replace function cast_vote(q bigint, d text, c int) returns void
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  select array_length(options, 1) into n from questions where id = q;
  if n is null or c < 0 or c >= n then raise exception 'bad choice'; end if;
  if d is null or length(d) < 8 or length(d) > 64 then raise exception 'bad device'; end if;
  insert into votes(question_id, device_id, choice) values (q, d, c)
  on conflict (question_id, device_id) do update set choice = excluded.choice, voted_at = now();
end $$;

create or replace function results() returns table(question_id bigint, choice int, total bigint)
language sql security definer set search_path = public as $$
  select v.question_id, v.choice, count(*) from votes v group by 1, 2;
$$;

create or replace function my_votes(d text) returns table(question_id bigint, choice int)
language sql security definer set search_path = public as $$
  select v.question_id, v.choice from votes v where v.device_id = d;
$$;

-- Website visitors may read the questions and use the three functions, nothing more.
grant usage on schema public to anon;
grant select on questions to anon;
grant execute on function cast_vote(bigint, text, int), results(), my_votes(text) to anon;

-- The four questions from the hallway, with the paper tallies (26 Nov).
insert into questions (question, options, paper_counts, is_current, created_at) values
 ('Would you rather have unlimited money or unlimited time?',
  array['Unlimited money','Unlimited time','Neither, quality over quantity'], array[11,5,2], false, now() - interval '4 minutes'),
 ('Would you rather have in Denmark forever: rainy days or windy days?',
  array['Rainy days','Windy days','I would emigrate'], array[6,5,2], false, now() - interval '3 minutes'),
 ('Which is your favourite weekday?',
  array['Monday','Tuesday','Wednesday','Thursday','Friday'], array[0,2,0,2,9], false, now() - interval '2 minutes'),
 ('What powers your work day?',
  array['Coffee','Tea','Water','Pure willpower','My lovely colleagues!!'], array[3,0,0,3,1], true, now() - interval '1 minute');


-- ─────────────────────────────────────────────────────────────
-- WEEKLY: new question of the week (edit the text, then select only these lines and Run)
--
-- update questions set is_current = false where is_current;
-- insert into questions (question, options, is_current)
--   values ('Would you rather work from a cabin or a café?', array['Cabin','Café'], true);
--
-- Make an older question the question of the week again:
-- update questions set is_current = (id = 3);
--
-- Remove a question (and its votes):
-- delete from questions where id = 3;


-- ── Suggestion box (also in update-1-suggestions.sql) ──

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


-- ── Keeper mode (also in update-2-keepers.sql). Change CHANGE-ME before running! ──

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
