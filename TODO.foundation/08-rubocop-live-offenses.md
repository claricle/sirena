# 08 — Lint: zero live offenses, enforced

Can start: now. Small. Blocks: 09.

## Facts

109 live offenses, 104 of them autocorrectable, on top of the parked
todo (measured 2026-08-11 with `bundle exec rubocop`). `rake.yml`
delegates to metanorma/ci's `generic-rake`, so whether rubocop runs in
CI today is inherited and unaudited — step 1 settles it.

## Do

1. Establish rubocop as a lane entry through item 19a's extension
   contract (19a owns the workflow files); zero live offenses from then
   on. First read what `generic-rake` already runs, so we don't add a
   second rubocop invocation next to an inherited one.
2. `rubocop -a`, review the diff hunk-by-hunk, suite + corpus after.
3. Hand-fix the remainder.
4. Delete `scripts/rename_to_sirena.rb` (dead self-referential script)
   AND its three `.rubocop_todo.yml` exclusions — deleting the file
   without them leaves stale exclusions and silently moves the
   parked-debt number. If item 02 has already baselined the lint column,
   rebase and update it in the same PR.
5. Pin the lint toolchain in the `Gemfile`: `rubocop`,
   `rubocop-performance`, `rubocop-rake` and `rubocop-rspec` are all
   unconstrained today, and the todo was generated under 1.82.1 while
   the current bundle resolves 1.89.0 — the ratchet is not reproducible
   until they're pinned. Document the procedure for a reviewed bump.
6. Pin `.rubocop.yml`'s remote `inherit_from` to an immutable commit URL.
7. `.rubocop.yml` is also touched by item 01 (`TargetRubyVersion`) —
   whichever lands second rebases.

## Done when

`bundle exec rubocop` exits 0; CI enforces it; the lint toolchain is
pinned; the corpus scoreboard is unchanged.

On the lint-debt number: item 09 owns the machine-readable counter and
starts after this item, and 02b may not have shipped the scoreboard yet.
So item 08 records the before/after suppressed-offense count in its PR
body as a provisional figure. Whichever of 02b and 09 lands second
imports it as the baseline — nobody re-derives it later from memory.
