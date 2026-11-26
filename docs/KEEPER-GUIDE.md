# Keeper guide: running the Corridor Quiz

Contact: Joory (joory@agro.au.dk, Jingru Yin)

## What's in this folder
- `index.html`: the voting website. Upload it to Netlify to put it online.
- `sql/update-1-suggestions.sql`: adds the suggestion box. Run once (already included in `sql/schema.sql` for new projects).
- `sql/update-2-keepers.sql`: adds keeper mode and sets the keeper password. Run it again with a new password to change the password.
- `sql/schema.sql`: creates the database. It has already been run once; only run it again for a brand-new Supabase project.
- `docs/vote-qr.png`: the QR code for the whiteboard .

## Where things live
- **Database (votes and questions):** Supabase project `corridor-quiz`.
- **Website:** Netlify, https://klima-corridor-quiz.netlify.app

## Every week: keeper mode (no SQL needed)
1. Open the website, scroll to the bottom and click **Keeper login**. Enter the keeper password (ask Joory or Rikke).
2. In keeper mode you can:
   - **Post a new question:** use the form at the bottom and tick "Make it the question of the week".
   - **Pick a suggestion:** click **Make question of the week** under a sticky note in the suggestion box.
   - **Copy whiteboard tallies:** use **+** and **−** next to each answer. Online votes are added on top.
   - **Take down** a question or a silly suggestion: tap it twice.
3. Draw the same question on the whiteboard, and click **Log out** when you're done.

## Doing the same with SQL (backup)
In Supabase → **SQL Editor**:

```sql
-- new question of the week
update questions set is_current = false where is_current;
insert into questions (question, options, is_current)
  values ('Would you rather work from a cabin or a café?', array['Cabin','Café'], true);

-- make suggestion #7 the question of the week
update questions set is_current = false where is_current;
update questions set is_current = true, suggested = false, created_at = now() where id = 7;

-- remove question or suggestion #7
delete from questions where id = 7;
```

## Other changes
- **Add whiteboard tallies to an answer:** go to **Table Editor → questions** and edit `paper_counts`. The numbers are in the same order as the answers, for example `{3,0,0,3,1}`.
- **Fix a typo:** edit the row in **Table Editor → questions**.
- **Remove a question and its votes:** `delete from questions where id = 3;`
- **Change the website itself:** edit `index.html`, then in Netlify open the site, go to **Deploys**, and drag the folder in again. The link stays the same.

## Good to know
- Free Supabase projects pause after about a week with no visits. If the site says it can't reach the vote box, log in to Supabase and click **Restore project**.
- Don't share the **secret** or **service_role** key from Supabase. The publishable key inside `index.html` is meant to be public.
- To take over the quiz, ask the current keepers to invite you to the Supabase and Netlify accounts. Don't share passwords.
