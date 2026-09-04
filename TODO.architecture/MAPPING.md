# How this relates to TODO.foundation

`TODO.foundation/` is a thorough plan for **measuring** this codebase —
oracles, scoreboards, ratchets, coverage timelines, CI lane contracts.
Its research is good: the file:line citations are accurate, the corpus
counts are real, and several of its items are the reference for work
that has not happened yet.

`TODO.architecture/` is about **shaping** the code. It reorders the same
destination: structural work first, measurement sized to what the work
actually needs.

Nothing in `TODO.foundation/` is deleted. Use this page to find where an
item went. **Every one of the 19 items appears below**, so a missing row
is a bug in this page, not a silent drop.

## Still the reference — use them as written

These are unchanged and still correct. When their turn comes, read them.

| Item | Where it is used |
|---|---|
| `04` XML escaping | research reused by `02-svg-one-serializer.md` |
| `05` type detection | first task of `08-burndown.md` |
| `06`, `07` corpus burndown | `08-burndown.md` |
| `08` lint: 109 live offences | `08-burndown.md`, step 4 |
| `11` docs truth | starts any time — but it **cannot close before the scoreboard exists** (`TODO.foundation/11:5-8`), because its generated tables read it. So: start now, close at item 08 step 3a |
| `14` elkrb + layout parity | `08-burndown.md`, step 3 — adopted **in full**, including the 8%/15% bar and the whole metric contract. This is the agreed fidelity target. **One of its open choices is now made:** 14 asks whether the grid survives as an opt-in; item 06 deletes `Layout::Grid` instead, so the answer on record is "removed". **Note the knock-on:** 14 also owes `docs/emit-accept-survey.md`, and item 18 cannot start without it — scheduling 14 at step 3 puts that survey on item 18's critical path. **Its paths are stale the same way item 18's are, below:** it names `Transform::Treemap`, `Transform::BlockTransform`, `Transform::PieTransform` and `lib/sirena/transform/*`, all of which item 03 renames to `Layout::*` / `lib/sirena/layout/` well before step 3 runs — translate the names when this item is picked up, same as item 18 |
| `15` docs site build | independent |
| `17` release + versioning | independent |
| `01` lutaml 0.8 migration | appears already landed — gemspec is `~> 0.8.0` as of commit 2702a09 |
| `12` PlantUML phase 1 | unchanged, and out of this plan's scope. Item 06 keeps the detection seam ready for it; `TODO.foundation/18` gates its **Done**, not its start |
| `16` PlantUML class spike | unchanged, and now load-bearing: it supplies the second notation's shapes that `TODO.foundation/18` designs the IR against |

## Same problem, smaller answer

| Foundation item | Becomes | What changed |
|---|---|---|
| `02` corpus oracle + scoreboard | `01-safety-net.md` part B **now**, `08-burndown.md` step 3a **later** | split by time, not dropped, and **not relocated**. `scoreboard/corpus.json` is the scoreboard's first column, shipped early; it answers "did I break something" for items 01-07. The other columns, the floors and the CI diff arrive at item 08 step 3a, along with the hermetic toolchain pin and reference provenance, which geometry parity work requires |
| `10` notation registry | `06-registry-as-data.md` | a data table and convention-based lookup, instead of a notation plugin system with external discovery. Same seam, no speculative API |
| `18` typed IR | **kept, but its paths and boundary need rewriting before it starts** — see the note below. `04-typed-scene.md` does not replace it | An earlier draft of this plan said 18 was "brought forward and scoped to Mermaid only". That was wrong on both halves, and the owner ruled against it on 2026-08-13. See below |
| `03` coverage floors | one line floor, one branch floor | staged timeline tied to other tracks' completion removed. **This overrides the floor-raise criteria inside items 06, 07 and 14**, which are otherwise adopted as written — see the note below |
| `19` CI topology | one workflow file | lane ownership protocol removed. **But 08 and 17 still depend on 19a** — 08 wants a rubocop lane, 17 needs the release workflow pinned off `metanorma/ci@main`. The one file owes both; see `DO-NOT-BUILD.md` |

### Item 18 cannot start against the paths it names

It is kept in full, but two things in it are stale the moment item 03 lands
and must be rewritten before anyone picks it up:

- It targets `lib/sirena/transform/*`, a directory **item 03 removes** —
  that code becomes `lib/sirena/layout/`.
- It directs those transforms to emit the IR, while this architecture puts
  the IR at the **notation -> layout** boundary and admits mapper ownership
  is unsettled.

Rewriting the paths is mechanical. Deciding who emits the IR is not, and it
is the part to settle first.

### Which wins on the corpus denominators

Two rules here contradict each other and one has to win:

- Rows above say foundation `06`/`07`'s per-type case counts "stand as
  written".
- `CHANGES-TO-THE-PLAN.md` says to re-derive them because they include
  extraction artifacts, and `08-burndown.md:83-89` rejects the original
  denominators outright.

**Re-derivation wins.** The original counts are measured against the whole
1,997-file corpus, which carries 632 extraction artifacts and 59 cases mmdc
itself rejects. Only the evidence-valid denominator means anything. What
still stands from `06`/`07` is their ORDERING and their per-type
prioritisation — not their absolute numbers. Re-measure before quoting any
of them.

### Which wins on the coverage floors

Rows above adopt items `06`, `07` and `14` "as written" and "in full", and each of
those carries a branch-floor raise as its own acceptance criterion — 06 at
`55 → 70`, 07 at `70 → 80` and `80 → 90`, 14 at `80 → 90`, with 07 stating
outright that "floor raises are acceptance criteria of this item, not side
effects". `DO-NOT-BUILD.md:108-115` repeals exactly that ladder.

Read literally, two engineers closing two items set opposite CI floors and
neither is wrong on the text.

**The SCHEDULE flexes; the BAR does not.** An earlier draft of this section said
to treat the floor-raise bullets as satisfied without touching CI. That was wrong,
and `AGENTS.md` is the reason: it sets branch coverage at "97% via staged floors —
70/80/90/97 tied to plan items; **schedule flexes, bar doesn't**." Waiving the
raises waives the bar, which is not this plan's to waive.

What `DO-NOT-BUILD.md` actually rejects is the COUPLING — each raise firing
automatically on another track's completion event. What stands is the ladder
itself. So: raise the branch floor by hand, in its own PR, when the coverage is
actually there; do not tie the raise to item 06, 07 or 14 closing. The 97%
destination is unchanged and still owned. The
rest of those items — the 8%/15% bar and the metric contract — still stand as
written. **Their absolute per-type case counts do NOT** — see "Which wins on
the corpus denominators" above; what survives there is their ordering and
prioritisation, not their numbers.

## Moved later

**`09` — `.rubocop_todo.yml` burndown (7,602 entries).** It is now step 4
of `08-burndown.md`. Items 04-06 delete a large fraction of the files
that debt is parked in; styling them first means doing it twice. The
original item already noticed the collision with item 10 and resolved it
with "rebase onto it" — that is the same signal.

**`13` — skills and agents.** The item states this tooling is
maintainer-local and untracked, while also making it a global blocker on
all agent dispatch. A blocking dependency that is not in the repo cannot
be verified by whoever picks the work up. Either commit it or drop it
from the plan; it is not a prerequisite for anything here.

## Where the original plan was right

Two things worth recording, because the reordering can read as a
rejection and it is not:

**The oracle toolchain pin was the right instinct.** With geometry
parity as the agreed bar, comparing against irreproducible reference
SVGs measures noise, so `TODO.foundation/02a` is genuinely necessary —
the disagreement was only about *when*. It is scheduled at item 08 step
3a, roughly two months later, once something exists that actually reads
those references.

**The metric contract in item 14 is the best-calibrated part of either
plan.** Node identity, normalisation, the equations, overlap semantics,
non-box types — geometry comparison really is that subtle, and it is
adopted unchanged.

**And the typed IR belongs in this foundation.** The owner ruled it on
2026-08-13 (`TODO.foundation/18:3-8`), citing Issue #2. An earlier draft
of this plan deferred it and cited item 18's old deferral in support —
but item 18 had already withdrawn that argument as "our reasoning rather
than the author's instruction". So the plan quoted a position that no
longer existed.

Two things follow, and both are corrections rather than choices:

- Item 18 keeps its full scope and its own prerequisites (after 10,
  after 14's `docs/emit-accept-survey.md`, after 16's class spike). It
  is not folded into item 04.
- Item 04 is a different boundary — geometry between layout and
  renderer — and it still runs early and still stays Mermaid-shaped.
  Nothing about the ruling slows it down.

`00-overview.md` has the full version, including the scheduling
consequence for item 14.

## What actually changed, in one paragraph

The original plan front-loads measurement and defers structure. Because
the structure is what makes each of the 458 remaining evidence-valid
corpus fixes expensive, that ordering pays the high per-fix cost across
the largest block of work in the project. This plan front-loads the cheap structural
work — six items, all mechanical, none changing whether a case renders
well-formed output, though 04 and 05 change what it looks like — and
then runs the same burndown against a codebase
with one documented contract instead of 24 undocumented ones.
