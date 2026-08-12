# 03 — Coverage floors and the branch timeline

Can start: after 02 (floors live in the scoreboard). Runs in parallel
with everything; does not block PlantUML.

## Facts

Measured baseline (unit+integration only): ~86% line, ~55% branch.
No coverage tooling is wired in yet.

## Bars (user-ruled)

- **Line**: floor rises to 92 immediately, **97 is the hard phase
  gate**, 100 the aspiration. Every PR: changed lines 100% covered.
- **Branch**: the bar is **97** — reached on a staged timeline. Each
  step is a floor raise TIED TO A NAMED EVENT, enforced when the event
  completes (the floor raise is part of that event's acceptance):

  | Branch floor | Raised when |
  |---|---|
  | 55 → 70 | item 06 complete |
  | 70 → 80 | sub-tracks 07a–07c complete (defined in item 07) |
  | 80 → 90 | item 07 complete + item 14 complete |
  | 90 → 97 | the item-03 coverage-completion pass |

  The bar is never lowered; only the schedule flexes.
- **Line 86 → 92 is an owned task**, not a hope: this item's first PR
  is a dedicated test pass on the least-covered components to reach 92,
  before the floor is set there.
- Zero pending/skipped examples suite-wide (single owner: item 07 for
  the existing xit; this item for the CI rule).

## Do

1. SimpleCov with line+branch, grouped by component; corpus spec runs
   in a SEPARATE process so exercised-not-verified lines can't inflate
   the number (split rake tasks; verify once by comparing with/without).
2. Floors live in the scoreboard (item 02's mechanism) — ratchet up only.
3. Each burndown PR raises the floor to what it achieves.
4. A dedicated coverage-completion pass closes the last gap to 97 line
   once the corpus tracks quiet down; branch steps land per the
   timeline above.

## Done when

- CI fails below the floors; floors only ever rise.
- Line ≥ 97, branch ≥ 97 (end of timeline), changed-line rule active.

## Files

`.simplecov`, `Gemfile`, `spec/spec_helper.rb`, `Rakefile`, CI, scoreboard.
