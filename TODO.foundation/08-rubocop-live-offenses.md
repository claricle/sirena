# 08 — Lint: zero live offenses, enforced

Can start: now. Small. Blocks: 09.

## Facts

109 live offenses (104 autocorrectable) on top of the parked todo.
`rake.yml` delegates to metanorma/ci's `generic-rake` — read it to
learn whether rubocop runs in CI at all (item 19 pins the workflow).

## Do

1. Confirm/establish rubocop in CI; zero live offenses from then on.
2. `rubocop -a`, review the diff hunk-by-hunk, suite + corpus after.
3. Hand-fix the remainder.
4. Delete `scripts/rename_to_sirena.rb` (dead self-referential script).
5. Pin `.rubocop.yml`'s remote `inherit_from` to an immutable commit URL.

## Done when

`bundle exec rubocop` exits 0; CI enforces it; scoreboard unchanged.
