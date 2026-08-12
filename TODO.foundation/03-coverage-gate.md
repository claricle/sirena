# 03 — Coverage floors and the branch timeline

Split into two stages. **03a** lands the measuring machinery AND the
test pass that closes the 86→92 line gap — two PRs, instrumentation
first, then the test pass that lets the 92 floor be set without landing
red. **03b** is the ongoing floor timeline and the final completion
pass.

Can start: after 02 (floors live in the scoreboard). Runs in parallel
with everything; does not block PlantUML. **But no behavior PR may
close before 03a lands** — items 05, 06, 07, 12 and 14 all change
behavior, and without 03a there is no changed-line gate for them to
pass. Investigation and drafting stay parallel; merging waits.

## Facts

Measured baseline (unit+integration only): ~86% line, ~55% branch.
No coverage tooling is wired in yet.

## Bars (user-ruled)

- **Line**: floor set at 92 once this item's initial test pass closes
  the 86→92 gap (the pass comes first, so the gate never lands red);
  **97 is the hard phase gate**, 100 the aspiration. Every PR: changed
  lines 100% covered.
- **Branch**: the bar is **97** — reached on a staged timeline. Each
  step is a floor raise TIED TO A NAMED EVENT, enforced when the event
  completes (the floor raise is part of that event's acceptance):

  | Branch floor | Raised by |
  |---|---|
  | 55 → 70 | the PR that completes item 06 |
  | 70 → 80 | the PR that completes the LAST of 07a, 07b, 07c |
  | 80 → 90 | whichever of item 07 and item 14 completes SECOND |
  | 90 → 97 | 03b's own coverage-completion pass |

  Each raise names the PR that performs it, so no raise can be left to
  "whoever notices". The bar is never lowered; only the schedule flexes.
- **Line 86 → 92 is an owned task**, not a hope: 03a's second PR is a
  dedicated test pass on the least-covered components to reach 92,
  before the floor is set there.
- Zero pending/skipped examples suite-wide (single owner: item 07 for
  the existing xit; this item for the CI rule).

## Do — 03a, instrumentation

1. SimpleCov with line+branch, grouped by component; corpus spec runs
   in a SEPARATE process and its results are **explicitly not collated**
   into the coverage number, so exercised-not-verified lines can't
   inflate it (split rake tasks; verify once by comparing with/without).
2. **Name the changed-line mechanism.** SimpleCov measures coverage; it
   does not map a diff onto it. Pick the tool or write the algorithm,
   and state: merge-base computation, how renames and deletions are
   handled, and which files are in scope. "Changed lines 100% covered"
   is not a gate until something computes it.
3. Floors live in the scoreboard (item 02's mechanism) — ratchet up only.
4. Seed two failures and prove both go red: one uncovered changed line,
   and one corpus-inflated coverage number.
5. Then the test pass on the least-covered components to reach 92 line,
   and set that floor. This is 03a's second PR, not a separate item.

## Do — 03b, the timeline

6. Each burndown PR raises the floor to what it achieves.
7. A dedicated coverage-completion pass closes the last gap to 97 line
   once the corpus tracks quiet down; branch steps land per the
   timeline above.

## Done when

**03a**

- The changed-line calculation is implemented and named, not described.
- Both seeded failures exit non-zero.
- Corpus results provably absent from the coverage number.
- Line coverage ≥ 92 and the 92 floor set in the scoreboard.

**03b**

- CI fails below the floors; floors only ever rise.
- The first three raises in the table have fired, each performed by the
  PR named there, and each owning item's Done section lists its raise as
  acceptance (items 06, 07 and 14 do).
- 03b's own completion pass then takes branch 90 → 97.
- Line ≥ 97, branch ≥ 97, changed-line rule active.

## Files

`.simplecov`, `Gemfile`, `spec/spec_helper.rb`, `Rakefile`, scoreboard,
and one lane entry in `.github/workflows/` (19a owns those files).
