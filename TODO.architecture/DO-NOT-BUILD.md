# Do not build these (yet)

Each of these is real, well-researched work in `TODO.foundation/`. Each
is premature today. Each has a named trigger — the event that makes it
worth doing.

**Deferring is not deleting.** When a trigger fires, the research is
already written down; go and use it.

If you find yourself building one of these, stop and ask first.

---

## Notation plugin system

Two-level notation registry, notation plugin objects, external discovery
via a RubyGems hook or directory loader, cold-subprocess proof that an
external notation renders.

**Why not now:** one notation exists. An API designed against a single
example is a guess. `TODO.foundation/10` itself notes the shape is
settled but the API contract is not — that is the signal there is not
enough evidence yet.

**Trigger: the PlantUML PR, expected within months.** Close enough that
item 06 keeps detection inside `Notation::Mermaid` so the seam is ready
— but not close enough to design its API before seeing what PlantUML
actually needs.

---

## Hermetic oracle toolchain

Committed Node / mermaid-cli / mermaid / Puppeteer / Chromium / font pin
or container digest, drift detection, three-outcome verdicts with
declared-type-aware error markers, per-case provenance records.

**Why not now:** this makes two machines agree about what the reference
renderer says, and it makes reference SVGs reproducible. Neither matters
until something compares against those references.
`scoreboard/corpus.json` answers the only question items 01-07 ask —
*did I just break something?*

**Trigger: item 08 step 3a — and it WILL fire.** Geometry parity is the
agreed bar, so this is scheduled work, not hypothetical. It is deferred
by about two months, not dropped. Also fires earlier if a second person
starts committing corpus fixes, or a corpus number goes into a published
claim (`TODO.foundation/11` generates docs numbers from it).

---

## Stable content-hash case identity

Case IDs derived from upstream path + test identity + source hash, with
an old-to-new migration manifest and collision detection.

**Why not now:** ordinal case names work until upstream inserts a case,
and then they break loudly rather than silently.

**Trigger:** the first time `spec/mermaid/` is regenerated from a newer
mermaid-js checkout.

---

## Reference SVG regeneration and geometry parity

**Why not now:** the references exist to compare geometry, and nothing
compares geometry until item 08 step 3.

**Trigger: item 08 step 3b.** Scheduled, not hypothetical — see the
ordering in `08-burndown.md`. Must come after the toolchain pin, or the
references are not reproducible and the comparator reads noise.

---

## Cross-notation typed IR — OVERRULED, it is foundation work

**This entry used to defer the IR until after PlantUML shipped class and
sequence. That is wrong and it is withdrawn.**

`TODO.foundation/18:3-8` carries an owner ruling dated 2026-08-13: the
typed IR **is** built in this foundation, because Issue #2 states it as
the architecture. The item says so in as many words — the earlier
deferral "was our reasoning rather than the author's instruction". This
page cited that deferral approvingly, which made it our reasoning twice
over.

What survives of the argument is the sequencing, and item 18 already
carries it. An IR designed from Mermaid alone would encode Mermaid's
assumptions, so the evidence lands before the design: item 18 starts
after item 10, after item 14's `docs/emit-accept-survey.md`, and after
item 16's PlantUML class spike — the second notation's shapes are the
data point the deferral said was missing. Then the IR is fixed and both
notations migrate onto it.

**Item 04 does not replace it.** Scenes are the layout→renderer boundary
and carry geometry; the IR is the notation→layout boundary and carries
meaning. Building one does not discharge the other. Item 04's Scenes
stay Mermaid-shaped, and that part is still correct — see
`00-overview.md`, "The IR, and what the owner ruled".

**What is still deferred:** an IR written before 14's survey and 16's
spike exist. That is item 18's own constraint, and it is the only one
left.

---

## Staged coverage floor timeline

Branch coverage staged 70 -> 80 -> 90 -> 97, each raise tied to a named
event in another track.

**Do the simple version instead:** one line floor and one branch floor,
raised by hand when someone raises them. Tying floors to other items'
completion buys nothing a manual bump does not.

**The gate itself stays.** `TODO.foundation/03:16` — "No behavior PR may
close before 03a lands" — is not repealed here, and
`TODO.foundation/05` still names 03a as a prerequisite. Only the staged
timeline goes. See `03-name-the-layers.md`.

---

## CI lane topology

Lane skeleton, an extension contract, per-item lane ownership, measured
budgets.

**Do the simple version instead:** one workflow file; add a job when a
gate exists. Revisit if CI runtime becomes a problem — measure it before
designing for it.

**Two foundation items still name 19a, and simplifying it does not
release them.** `TODO.foundation/08:14` establishes rubocop "as a lane
entry through item 19a's extension contract", and
`TODO.foundation/17:3` says the release cut cannot run until 19a pins
the release workflow, because otherwise it publishes the gem through
mutable external code at `metanorma/ci@main`.

The one-workflow-file version has to carry both obligations: a rubocop
job, and a pinned release workflow. Read those two items as "the CI file
owes me this", not as "19a was deleted".

The requirement that survives is the pin. Dropping the lane skeleton is
a simplification; dropping the pin would be a regression, and item 17's
reason for it is a real one.

---

## A second ratchet mechanism

A tracker for corpus, conformance, lint debt, coverage or parity that
lives anywhere other than `scoreboard/`.

**Why not now, and why not ever:** `AGENTS.md` is explicit — every
ratchet is a column in `scoreboard/`, and a second tracking mechanism is
not to be invented. `scoreboard/corpus.json` (item 01 part B) is the
first column of that one scoreboard, shipped early, not a rival to it.
Every `TODO.foundation` item that names the scoreboard in its Done-when
criteria — 04, 05, 06, 07, 08, 11 and 14 — still means that directory,
and none of them changes.

**What is deferred is the rest of the machinery, not the place:** the
other columns, the per-metric floors, and the CI merge-base diff, all of
which arrive with `TODO.foundation/02b` at item 08 step 3a.
