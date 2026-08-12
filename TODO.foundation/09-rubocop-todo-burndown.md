# 09 — Lint: burn the todo to deletion

Can start: after 08. Parallel with everything; does NOT block PlantUML.

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
3. Suppressed-offense total is a scoreboard column: measured by a
   stripped-config run, may only decrease, reaches the user-signed
   exception set, then the todo file is deleted.

## Done when

Todo deleted; each surviving exclusion (if any) in `.rubocop.yml`
carries a `# approved: <user> <date>` comment naming its single file;
scoreboard column at its floor.
