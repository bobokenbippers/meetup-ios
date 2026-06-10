# Pending migrations

SQL that is written but intentionally **not applied**, because it encodes a
product decision that hasn't been made yet. Files here are outside
`supabase/migrations/` so `db push` cannot apply them by accident.

When a decision is made: move the file into `supabase/migrations/` with a fresh
unique timestamp prefix, apply it, and record it in the migration history.

| File | Decision needed |
| --- | --- |
| `20260609_sharelink_join_rls.sql` | Should share links let **anyone** self-join an active shareable meetup, or stay friends-only? Currently friends-only, which means share links do not work for non-friends. See the header comment in the file. |
