# 03 — Coverage floors and the branch timeline

Split into two stages. **03a** lands the measuring machinery AND the
test pass that closes the 86→92 line gap — two PRs, instrumentation
first, then the test pass that lets the 92 floor be set without landing
red. **03b** is the ongoing floor timeline and the final completion
pass.

**Can start: as soon as item 01's migration makes the suite runnable —
NOT after 02.** Only floor STORAGE needs the scoreboard (step 5);
SimpleCov, the changed-line calculation and the seeded failures need
nothing from item 02. Landing 03a early is what gives every later
behavior PR a gate to pass. Runs in parallel with everything after
that; does not block PlantUML.

**No behavior PR may close before 03a lands.** That means every item
that changes runtime code, not just the corpus tracks: 04 (XML escaping,
renderers, theme), 05, 06, 07, 10 (engine, registry, CLI), 12, 14 and
16 (the PlantUML spike ships real code). Investigation and drafting stay
parallel; merging waits.

Item 01's migration is the single named exemption, above.

## The bootstrap exemption

Item 01's migration PR changes runtime code and lands BEFORE this item,
because nothing — not the suite, not SimpleCov — runs until it does.
There is no way to gate it with machinery it is the prerequisite for.

So: item 01's migration PR is explicitly exempt from the changed-line
rule and states its coverage manually in the PR body instead. Every PR
after 03a is gated. The exemption is named here rather than left as a
silent hole, and it applies to exactly one PR.

## Facts

Measured baseline (unit+integration only): ~86% line, ~55% branch,
measured under the local 0.7 pin. No coverage tooling is wired in yet.

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
  | 70 → 80 | whichever completes LAST of item 06 and 07a/07b/07c |
  | 80 → 90 | whichever of item 07 and item 14 completes SECOND |
  | 90 → 97 | 03b's own coverage-completion pass |

  Each raise names the PR that performs it, so no raise can be left to
  "whoever notices". Where a raise depends on two tracks that run
  concurrently, the FIRST to finish records the handoff in its PR body
  and closes; the SECOND performs the raise. Neither is blocked on the
  other. The bar is never lowered; only the schedule flexes.
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
3. Seed two failures and prove both go red: one uncovered changed line,
   and one corpus-inflated coverage number.
4. Then the test pass on the least-covered components to reach 92 line.
   This is 03a's second PR, not a separate item.
5. Floor STORAGE moves into the scoreboard once item 02 has built it —
   the only part of this item that waits on 02. Until then the floors
   live in the coverage config and the guard still fails below them.

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
- Line coverage ≥ 92, with the 92 floor enforced (in the coverage
  config if item 02 has not landed yet, in the scoreboard once it has).
- Item 01's migration PR is the ONLY changed-line exemption on record.

**03b**

- CI fails below the floors; floors only ever rise.
- The first three raises in the table have fired, each performed by the
  PR named there, and each owning item's Done section lists its raise as
  acceptance (items 06, 07 and 14 do).
- 03b's own completion pass then takes branch 90 → 97.
- Line ≥ 97, branch ≥ 97, changed-line rule active.

## Files

`.simplecov`, `Gemfile`, `spec/spec_helper.rb`, `Rakefile`, scoreboard.

**No workflow file.** 03a lands BEFORE 19a, so it cannot add a lane
entry — it ships rake tasks, and 19a picks coverage up through the
existing rake path when it wires the lanes. An earlier revision listed a
`.github/workflows/` entry here, which was the same circularity this
item exists to avoid.
