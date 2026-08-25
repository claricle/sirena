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
until something compares against those references. `corpus.json` answers
the only question items 01-07 ask — *did I just break something?*

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

## Cross-notation typed IR

**Why not now:** an IR designed from Mermaid alone encodes Mermaid's
assumptions. That is `TODO.foundation/18`'s own argument and it is
correct. Item 04's Scenes are deliberately Mermaid-shaped and private to
the Mermaid notation.

**Trigger:** after PlantUML ships class and sequence.

---

## Staged coverage floor timeline

Branch coverage staged 70 -> 80 -> 90 -> 97, each raise tied to a named
event in another track.

**Do the simple version instead:** one line floor and one branch floor,
raised by hand when someone raises them. Tying floors to other items'
completion buys nothing a manual bump does not.

---

## CI lane topology

Lane skeleton, an extension contract, per-item lane ownership, measured
budgets.

**Do the simple version instead:** one workflow file; add a job when a
gate exists. Revisit if CI runtime becomes a problem — measure it before
designing for it.
