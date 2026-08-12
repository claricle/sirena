# 09 — Lint: burn the todo to deletion

Can start: after 08. **Completion** needs 02 — the suppressed-debt
column lives in the scoreboard, so the burndown can run without it but
cannot close without it. Does NOT block PlantUML.

Parallel with everything **except item 10**: `.rubocop_todo.yml` parks
debt in `lib/sirena.rb` (one exclusion) and
`lib/sirena/commands/batch.rb` (three: `Layout/ArgumentAlignment`,
`Style/RescueStandardError`, `Style/StringConcatenation`), and item 10
rewrites both files. Cop families touching those files wait for item 10
or rebase onto it; every other family stays parallel.

## Target (user-ruled)

`.rubocop_todo.yml` **deleted**. Parked debt teaches every future
session that parked debt is acceptable — so none survives. The only
permanent exclusions allowed: a tiny set of metrics cops on grammar
files where refactoring provably worsens the grammar — each single-file,
justified in `.rubocop.yml`, and **negotiated with the user at the
START of this item**, not discovered at the end.

## Do

1. Split the 95 cops into mechanical / RSpec / metrics classes (measured
   inventory, checked in here).
2. Burn down one cop family per PR, safest first. Suite + corpus green
   after each.
3. Suppressed-offense total is a scoreboard column. **Name the
   command**: add a rake task that runs rubocop with `.rubocop_todo.yml`
   excluded and emits a machine-readable total (JSON formatter, not
   scraped text), so two runs on two machines agree.

   It must also count suppressions in `.rubocop.yml` itself. Deleting
   the todo file means nothing if the same debt reappears as an
   `Exclude:` or `Enabled: false` in the main config, where ordinary
   RuboCop reports zero. The counter reads BOTH files, subtracts only
   the exact user-signed exception allowlist, and anything outside that
   allowlist counts as debt. May only decrease,
   reaches the user-signed exception set, then the todo file is deleted.
4. Seed two failures proving the column is enforced: reintroduce a
   suppressed offense via the todo file, and again via a fresh
   `Exclude:` in `.rubocop.yml`. Both must exit non-zero. The
   `# approved:` comment is documentation, not a guard — the allowlist
   is what the counter reads.

## Done when

Todo deleted; each surviving exclusion (if any) in `.rubocop.yml`
carries a `# approved: <user> <date>` comment naming its single file;
scoreboard column at its floor.

Also required, because they are what make the ratchet real: the cop
inventory from step 1 is checked in, the JSON-emitting rake task from
step 3 exists and two runs on two machines agree, and the seeded
suppressed offense from step 4 makes the guard exit non-zero.
