# 01 — Safety net

**Goal:** make it impossible to break something silently, and close a
crash that is already waiting in the code.
**Size:** 2 PRs. Part A touches ~12 model files. Part B is one rake file
plus a generated JSON.
**Prerequisite:** `TODO.foundation/03a`'s coverage gate — nothing in
this plan. Part A closes a latent runtime crash and Part B changes a
failing parse from `PipelineError` to `ParseError`; both are behaviour,
and `TODO.foundation/03:16` says no behaviour PR closes before 03a.
Otherwise, start here.

Everything after this item is a refactor. Refactors are only safe if
something tells you when you broke a diagram. Nothing does today.

---

## Part A — Contract spec (PR 1)

### Why

`Diagram::Base` declares `diagram_type` and `valid?` as abstract methods
that `raise NotImplementedError`. Measured across the 24 registered
types (2026-08-25, by introspecting the model each parser actually
returns — not by reading class names, which do not match the type
names):

- **4 bypass `Diagram::Base` entirely**, subclassing
  `Lutaml::Model::Serializable` directly: `architecture`, `block`,
  `gantt`, `requirement`. On those, `valid?` raises `NoMethodError`.
- **6 inherit `Diagram::Base#valid?`**, which raises
  `NotImplementedError`: `git_graph`, `mindmap`, `packet`, `radar`,
  `treemap`, `xychart`.
- **So 10 of 24 have no working `valid?`**, in two different failure
  modes.
- **10 do not implement `diagram_type`.** Five spell it `type`
  (`architecture`, `packet`, `radar`, `treemap`, `xy_chart`); five define
  neither.
- **14 models define their own `valid?`.** 13 transforms call
  `diagram.valid?`, and those 13 are a subset of the 14 — `kanban`
  defines one nobody calls.

Nothing crashes today **by coincidence**. But note what the obvious
cleanup actually buys, before you reach for it:

- 7 transforms do not inherit `Transform::Base` at all (`git_graph`,
  `kanban`, `mindmap`, `packet`, `radar`, `treemap`, `xychart`), so a
  `valid?` call moved into the base class never runs for them.
- Of the 10 broken types, the 6 whose model raises `NotImplementedError`
  are exactly the ones whose transform skips the base class. Moving the
  call reaches the other **4** — `architecture`, `block`, `gantt`,
  `requirement` — and they raise `NoMethodError`, not
  `NotImplementedError`.
- `NotImplementedError` inherits `ScriptError`, not `StandardError`. So
  even when one does fire, `engine.rb:119`'s `rescue StandardError` does
  not catch it: it escapes `PipelineError` entirely and reaches the
  caller raw. Whatever the corpus harness records for that case, it will
  not be a pipeline failure.

That is the crash, and it is worse than "9 types raise at runtime": the
fix has to cover both failure modes and both transform hierarchies.

`Parser::Base` is bypassed too, and treemap is not the only one:

- `TreemapParser` does not inherit `Parser::Base`, builds its model
  inline (`build_diagram` / `build_hierarchy`), and exports an alias
  `Treemap = TreemapParser` (`parser/treemap.rb:96`).
- **Six more parsers build the model inline the same way**, through a
  private `create_diagram`: `git_graph`, `kanban`, `mindmap`, `packet`,
  `radar`, `xy_chart`. They have a builder file under
  `parser/transforms/` and then do the work themselves anyway.
- `user_journey` has **no builder file at all** — there is no
  `parser/transforms/user_journey.rb`. It builds inline and raises its
  own semantic error at `parser/user_journey.rb:116`.

So "every other type does it in `Parser::Transforms::*`" is true of 16
of 24, not 23.

### Steps

1. Add a required `model:` row to `DiagramRegistry.register`. Today it
   takes `parser:`, `transform:` and `renderer:` only
   (`diagram_registry.rb:47`), so the registry cannot name the model
   whose contract is being checked. Fill it in on all 24 rows in
   `lib/sirena.rb`.

   The registry is the source of completeness here. One row per type
   means the invariant grows with the table instead of with a hand-kept
   list somewhere else.
2. Write `spec/contract_spec.rb`. It iterates `DiagramRegistry.types`
   and asserts, for every type:
   - parser inherits `Parser::Base`
   - transform inherits `Transform::Base`
   - renderer inherits `Renderer::Base`
   - the registered `model:` inherits `Diagram::Base`
   - that model responds to `diagram_type` and `valid?`
   - `diagram_type` returns the symbol the type is registered under
   - the parser returns an instance of the registered `model:`

   Add a set-parity assertion in the same file: `DiagramRegistry.types`
   must equal `Engine::DIAGRAM_TYPE_PATTERNS.keys` (`engine.rb:32`).
   `types` is `@handlers.keys` — only the rows that exist. Without
   parity a type missing from the registry is invisible, and the spec
   goes green over the ones it can see.

   Both sets are the same 24 today — measured 2026-08-27. So this
   assertion lands green and its whole job is to stay that way.

   The last assertion needs input, so add one canonical fixture per type
   under `spec/fixtures/contract/<type>.mmd` — the smallest source that
   parses. `engine.rb:106` hands the parser's return value straight to
   the transform without checking its class, so nothing catches a parser
   that builds the wrong model.
3. Run it. It will fail for about ten types. **That failure list is the
   work** — do not write it out by hand first.
4. Fix the models, never the spec:
   - rename `type` -> `diagram_type` (5 types)
   - give `valid?` a real body on the 10 that lack one. Returning `true`
     is fine when there is genuinely nothing to check. An honest trivial
     implementation is correct; a missing one is not.
   - make the 4 bypassing types inherit `Diagram::Base`
5. Make `TreemapParser` inherit `Parser::Base`. Move its model building
   into `Parser::Transforms::Treemap`. Delete the
   `Treemap = TreemapParser` alias.

   The six `create_diagram` parsers and `user_journey` have the same
   problem. Move them too if the PR stays reviewable; otherwise write
   them down and take them in item 05 part A, which is already opening
   every parser. Do not leave the list undiscovered.
6. Move the `raise TransformError unless diagram.valid?` line out of the
   13 individual transforms and into `Transform::Base`. This is the
   proof that the contract is now real — but it only reaches the 17
   transforms that inherit `Transform::Base`. Make the other 7 inherit
   it first (`git_graph`, `kanban`, `mindmap`, `packet`, `radar`,
   `treemap`, `xychart`), or the check silently skips exactly the types
   most likely to fail it.

### Do not

- Do not weaken the spec to make a type pass.
- Do not add a `valid?` that performs real validation on a type that had
  none — that changes behaviour and belongs in the corpus burndown.
  Return `true`.

---

## Part B — Corpus check (PR 2)

### Why

`scripts/corpus_sweep.rb` exists but is manual-only, so the 55.6%
evidence-valid pass rate (574/1032, swept 2026-08-27) is unprotected: a
refactor can drop 200 cases and nothing notices.

### Steps

0. **Fix the error taxonomy first — the harness is useless without it.**
   `Engine#render` currently collapses every non-detection failure into
   one `PipelineError`, with the backtrace concatenated into the message
   string (`engine.rb:119-121`). Recording a `stage` on top of that would
   record `PipelineError` for everything except detection, and
   `TODO.foundation/05` derives its whole work list from that field.

   Give each layer its own error class — `ParseError`, `LayoutError`
   (still `TransformError` until item 03 renames it), `RenderError`, all
   under `Sirena::Error` — and let them propagate. If the engine wraps at
   all, it wraps inside `rescue => e` so the original stays as `cause`,
   and it never stringifies a backtrace. See `LAYERS.md`.

1. Add `lib/tasks/corpus.rake`. `rake corpus` runs every `.mmd` under
   `spec/mermaid/` through `Sirena.render` and writes
   `scoreboard/corpus.json`: one row per case with `pass` or `fail`, and
   on failure:
   - **stage**: `detect` / `parse` / `layout` / `render`
   - the exception class
   The stage field is not optional. It costs one `rescue` and it is the
   entire input to item 08's first task.
2. Commit `scoreboard/corpus.json`.

   Record each case's verdict from `spec/mermaid/corpus-verdicts.yml`
   alongside its status, and report the rate over **evidence-valid cases
   only**. `AGENTS.md`: a case leaves the denominator by oracle
   rejection, never by judgment. A rate over all 1,997 files counts 632
   extraction artifacts and 59 mmdc rejections as work.
3. `rake corpus:check` re-runs and diffs against the committed file:
   - a case that used to pass and now fails -> **fail the build**
   - a case that used to fail and now passes, not recorded -> **fail the
     build** (so the file cannot go stale; you re-run `rake corpus` and
     commit the improvement)
4. `rake corpus[flowchart]` scopes to one type. You will live in this
   command during item 08, so make its output good: for each failure,
   print the case path, the stage, and the first line of the error.
5. Wire `corpus:check` into default `rake` and into CI.

### Do not

Build any of this — it is listed in `DO-NOT-BUILD.md` with the reason:

- pinning Node / mermaid-cli / Chromium / fonts
- regenerating reference SVGs
- content-hash case IDs or a rename migration
- geometry, conformance, coverage or lint-debt columns
- the CI merge-base diff machinery of `TODO.foundation/02b`

**This file IS the scoreboard's corpus column, not a rival to it.** Write
it at `scoreboard/corpus.json`, with the schema `TODO.foundation/02b`
step 2 defines for that column. `AGENTS.md` is explicit that every
ratchet is a column in one place and that a second tracking mechanism is
not to be invented, so this ships the first column early rather than
building somewhere else and migrating later. The other columns — and the
CI diff — arrive with 02b at item 08 step 3a. Every `TODO.foundation`
item that names the scoreboard in its Done-when criteria still means
this directory.

The corpus column answers the only question items 01-07 ask: *did I just
break something?*

### Files

`spec/contract_spec.rb` (new), `spec/fixtures/contract/*.mmd` (new,
24 of them), `lib/sirena/diagram_registry.rb`, `lib/sirena.rb`,
`lib/tasks/corpus.rake` (new),
`scoreboard/corpus.json` (new), `lib/sirena/diagram/*.rb` (about 12 of
them), `lib/sirena/parser/treemap.rb`, `lib/sirena/transform/*.rb`.

---

Both parts' criteria are one list below, at the end of the file. The
plan scorer reads the first `## Done when` in a file and stops at the
next `##`, so a per-part heading silently drops everything after the
first block.

## Done when

- [ ] A — `bundle exec rspec spec/contract_spec.rb` passes for all 24 types
- [ ] A — every `DiagramRegistry.register` row carries a `model:`
- [ ] A — `DiagramRegistry.types` and `Engine::DIAGRAM_TYPE_PATTERNS.keys` are the same set
- [ ] A — deleting one registry row turns `contract_spec.rb` red
- [ ] A — `Transform::Base` calls `valid?` once, for every type, suite green
- [ ] A — `grep -rn "def type$" lib/sirena/diagram/` returns nothing
- [ ] A — all 24 transforms inherit `Transform::Base`
- [ ] A — no `Treemap = TreemapParser` alias remains
- [ ] B — a failing parse raises `ParseError` out of `Engine#render`, not `PipelineError`; no backtrace appears inside any message string
- [ ] B — `rake corpus` writes `scoreboard/corpus.json`; it is committed
- [ ] B — the reported rate is over evidence-valid cases, and says so
- [ ] B — `rake corpus:check` fails on a deliberately broken renderer
- [ ] B — `rake corpus:check` fails on an unrecorded improvement
- [ ] B — `rake corpus[pie]` prints only pie results
- [ ] B — CI runs `corpus:check`
