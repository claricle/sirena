# 01 — Safety net

**Goal:** make it impossible to break something silently, and close a
crash that is already waiting in the code.
**Size:** 2 PRs. Part A touches ~12 model files. Part B is one rake file
plus a generated JSON.
**Prerequisite:** none. Start here.

Everything after this item is a refactor. Refactors are only safe if
something tells you when you broke a diagram. Nothing does today.

---

## Part A — Contract spec (PR 1)

### Why

`Diagram::Base` declares `diagram_type` and `valid?` as abstract methods
that `raise NotImplementedError`. Measured across the 24 registered
types:

- **4 bypass `Diagram::Base` entirely**, subclassing
  `Lutaml::Model::Serializable` directly: `architecture`, `block`,
  `gantt`, `requirement`.
- **10 do not implement `diagram_type`.** Five spell it `type`
  (`architecture`, `packet`, `radar`, `treemap`, `xy_chart`); five define
  neither.
- **9 do not implement `valid?`.**
- 13 transforms call `diagram.valid?`, and those 13 happen to be a
  subset of the 15 models that define it.

Nothing crashes today **by coincidence**. Move the `valid?` call into
`Transform::Base` — an obvious cleanup, and one you will want to make
during item 05 — and 9 types raise `NotImplementedError` at runtime.

`Parser::Base` is bypassed too: `TreemapParser` does not inherit it,
builds its diagram model inline (`build_diagram` / `build_hierarchy` —
work every other type does in `Parser::Transforms::*`), and exports an
alias `Treemap = TreemapParser` (`parser/treemap.rb:96`).

### Steps

1. Write `spec/contract_spec.rb`. It iterates `DiagramRegistry.types`
   and asserts, for every type:
   - parser inherits `Parser::Base`
   - transform inherits `Transform::Base`
   - renderer inherits `Renderer::Base`
   - the parser returns a model inheriting `Diagram::Base`
   - that model responds to `diagram_type` and `valid?`
   - `diagram_type` returns the symbol the type is registered under
2. Run it. It will fail for about ten types. **That failure list is the
   work** — do not write it out by hand first.
3. Fix the models, never the spec:
   - rename `type` -> `diagram_type` (5 types)
   - add `valid?` where missing (9 types). Returning `true` is fine when
     there is genuinely nothing to check. An honest trivial
     implementation is correct; a missing one is not.
   - make the 4 bypassing types inherit `Diagram::Base`
4. Make `TreemapParser` inherit `Parser::Base`. Move its model building
   into `Parser::Transforms::Treemap`, where every other type has it.
   Delete the `Treemap = TreemapParser` alias.
5. Move the `raise TransformError unless diagram.valid?` line out of the
   13 individual transforms and into `Transform::Base`. This is the
   proof that the contract is now real.

### Done when

- [ ] `bundle exec rspec spec/contract_spec.rb` passes for all 24 types
- [ ] `Transform::Base` calls `valid?` once, for every type, suite green
- [ ] `grep -rn "def type$" lib/sirena/diagram/` returns nothing
- [ ] no `Treemap = TreemapParser` alias remains

### Do not

- Do not weaken the spec to make a type pass.
- Do not add a `valid?` that performs real validation on a type that had
  none — that changes behaviour and belongs in the corpus burndown.
  Return `true`.

---

## Part B — Corpus check (PR 2)

### Why

`scripts/corpus_sweep.rb` exists but is manual-only, so the ~31% pass
rate is unprotected: a refactor can drop 200 cases and nothing notices.

### Steps

0. **Fix the error taxonomy first — the harness is useless without it.**
   `Engine#render` currently collapses every non-detection failure into
   one `PipelineError`, with the backtrace concatenated into the message
   string (`engine.rb:104-106`). Recording a `stage` on top of that would
   record `PipelineError` for everything except detection, and
   `TODO.foundation/05` derives its whole work list from that field.

   Give each layer its own error class — `ParseError`, `LayoutError`
   (still `TransformError` until item 03 renames it), `RenderError`, all
   under `Sirena::Error` — and let them propagate. If the engine wraps at
   all, it wraps inside `rescue => e` so the original stays as `cause`,
   and it never stringifies a backtrace. See `LAYERS.md`.

1. Add `lib/tasks/corpus.rake`. `rake corpus` runs every `.mmd` under
   `spec/mermaid/` through `Sirena.render` and writes `corpus.json`:
   one row per case with `pass` or `fail`, and on failure:
   - **stage**: `detect` / `parse` / `layout` / `render`
   - the exception class
   The stage field is not optional. It costs one `rescue` and it is the
   entire input to item 08's first task.
2. Commit `corpus.json`.
3. `rake corpus:check` re-runs and diffs against the committed file:
   - a case that used to pass and now fails -> **fail the build**
   - a case that used to fail and now passes, not recorded -> **fail the
     build** (so the file cannot go stale; you re-run `rake corpus` and
     commit the improvement)
4. `rake corpus[flowchart]` scopes to one type. You will live in this
   command during item 08, so make its output good: for each failure,
   print the case path, the stage, and the first line of the error.
5. Wire `corpus:check` into default `rake` and into CI.

### Done when

- [ ] a failing parse raises `ParseError` out of `Engine#render`, not
      `PipelineError`; no backtrace appears inside any message string
- [ ] `rake corpus` writes `corpus.json`; it is committed
- [ ] `rake corpus:check` fails on a deliberately broken renderer
- [ ] `rake corpus:check` fails on an unrecorded improvement
- [ ] `rake corpus[pie]` prints only pie results
- [ ] CI runs `corpus:check`

### Do not

Build any of this — it is listed in `DO-NOT-BUILD.md` with the reason:

- pinning Node / mermaid-cli / Chromium / fonts
- regenerating reference SVGs
- content-hash case IDs or a rename migration
- per-case geometry or conformance columns
- a `scoreboard/` directory

`corpus.json` answers the only question this plan needs answered: *did I
just break something?*

### Files

`spec/contract_spec.rb` (new), `lib/tasks/corpus.rake` (new),
`corpus.json` (new), `lib/sirena/diagram/*.rb` (about 12 of them),
`lib/sirena/parser/treemap.rb`, `lib/sirena/transform/base.rb`.
