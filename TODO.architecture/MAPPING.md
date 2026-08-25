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
item went.

## Still the reference — use them as written

These are unchanged and still correct. When their turn comes, read them.

| Item | Where it is used |
|---|---|
| `04` XML escaping | research reused by `02-svg-one-serializer.md` |
| `05` type detection | first task of `08-burndown.md` |
| `06`, `07` corpus burndown | `08-burndown.md` |
| `08` lint: 109 live offences | `08-burndown.md`, step 4 |
| `11` docs truth | independent; can run any time |
| `14` elkrb + layout parity | `08-burndown.md`, step 3 — adopted **in full**, including the 8%/15% bar and the whole metric contract. This is the agreed fidelity target |
| `15` docs site build | independent |
| `17` release + versioning | independent |
| `01` lutaml 0.8 migration | appears already landed — gemspec is `~> 0.8.0` as of commit 2702a09 |

## Same problem, smaller answer

| Foundation item | Becomes | What changed |
|---|---|---|
| `02` corpus oracle + scoreboard | `01-safety-net.md` part B **now**, `08-burndown.md` step 3a **later** | split by time, not dropped. `corpus.json` answers "did I break something" for items 01-07. The hermetic toolchain pin and reference provenance are **required** once geometry parity work starts, and are scheduled at item 08 step 3a |
| `10` notation registry | `06-registry-as-data.md` | a data table and convention-based lookup, instead of a notation plugin system with external discovery. Same seam, no speculative API |
| `18` typed IR | `04-typed-scene.md` | brought forward and scoped to Mermaid only. Deferring a *cross-notation* IR is right; having no contract at all is what costs on every corpus fix today |
| `03` coverage floors | one line floor, one branch floor | staged timeline tied to other tracks' completion removed |
| `19` CI topology | one workflow file | lane ownership protocol removed |

## Moved later

**`09` — `.rubocop_todo.yml` burndown (7,614 entries).** It is now step 4
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

## What actually changed, in one paragraph

The original plan front-loads measurement and defers structure. Because
the structure is what makes each of the ~1,380 remaining corpus fixes
expensive, that ordering pays the high per-fix cost across the largest
block of work in the project. This plan front-loads the cheap structural
work — six items, all mechanical, none changing rendered output except
one escaping fix — and then runs the same burndown against a codebase
with one documented contract instead of 24 undocumented ones.
