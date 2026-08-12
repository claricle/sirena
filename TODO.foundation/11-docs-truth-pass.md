# 11 — Docs truth: claims generated, not hand-written

Can start: NOW — the claim inventory and the promised-features
dispositions read files, they don't need a building site. Only
publishing the corrected pages waits for 15; the dispositions this item
produces are what 15 needs to resolve ghost links (explicit handoff, no
cycle). Parallel with everything; does not block PlantUML.

## Problem

Docs claim what measurement disproves: "100% Syntax Parity" for types
at 3–6%, "95%+ compatible", unattributable benchmarks ("16x faster"),
ELK layout, 19-vs-24 type counts, broken quick-start code
(`Engine.render`/`render_file` don't exist), invented CLI env vars and
exit codes, `high-contrast` vs the real `high_contrast`
(`examples/README.md:63`, `docs/index.adoc:143`,
`docs/_guides/cli-reference.adoc:43`), "37 examples" vs 53 on disk,
and a three-way license contradiction: `LICENSE` and `sirena.gemspec:21`
say BSD-2-Clause, `README.adoc:365` says BSD-3, and `docs/index.adoc:166`
plus `docs/_config.yml:76` say MIT. `LICENSE` is the source of truth;
the other three are wrong and this is package metadata, not prose. Docs also promise
unbuilt features (plugins, caching, Rails/Jekyll/Sinatra integration,
error-code taxonomy, 38 absent pages).

On benchmarks, be precise: a harness DOES exist
(`lib/tasks/benchmark.rake:7`, tasks `benchmark:compare` and
`benchmark:quick`). It is nonfunctional —
neither the task nor the `Rakefile` requires Sirena before calling
`Sirena.render`. The true claim is "no recorded, reproducible run
substantiates the published figures, and the harness is broken."

## Do

1. Claim inventory: one row per factual assertion, source, evidence,
   disposition. Every row ends verified / corrected / removed. No
   unresolved rows. **Scope is every tracked user-facing surface**, not
   just the four obvious files:
   - `README.adoc`, `ARCHITECTURE.md`, `docs/**`
   - the 26 tracked `examples/**/README*` files
   - `sirena.gemspec` metadata — its description still claims "ELK
     layout" (line ~14), plus the license, summary and Ruby floor
   - CLI help text (`lib/sirena/cli.rb`, `lib/sirena/commands/*`)
   - generated benchmark reports

   Explicitly excluded: `_site/`, `docs/plans/`, and anything generated
   from a tracked source (fix the source instead).

   Two artifacts, and the split matters:
   - The full working inventory stays maintainer-local at
     `docs/plans/docs-claims-inventory.md` — it holds reasoning and
     half-formed rows nobody needs to review.
   - The dispositions items 14 and 15 consume are **committed** at
     `docs/claims-manifest.yml` (tracked, machine-readable, one row per
     decided claim). Tracked is the whole point: a fresh pipeline
     worktree checks out tracked files, so a committed manifest needs no
     bootstrap copying and cannot go stale relative to the branch. It is
     NOT part of item 13's bootstrap payload.
2. **Numbers are generated** (this step waits for item 02's
   scoreboard): compatibility tables and pass rates render from the
   scoreboard (rake task), so corpus progress can't make the docs stale
   again.
   Hand-written numbers are banned in support claims. Name the generated
   include targets, and add a freshness gate — either regenerate during
   every docs build, or require `rake <generate> && git diff
   --exit-code` on every scoreboard-changing PR. "Live" without a gate
   goes stale the first time someone forgets.
3. Benchmarks: repair `benchmark.rake` (it needs `require 'sirena'`) and
   record one reproducible run, or delete the tasks and every
   performance claim with them. Pick one — a broken advertised command
   is worse than no command.
4. Executable snippets: every README/docs code example runs in a
   doc-snippet spec. Item 12 also needs this harness for its runnable
   README examples — if 12 gets there first it ships a standalone
   version this item later absorbs.
5. Promised-features disposition: each category goes to the user —
   build (creates an owned item), defer (explicit "planned" marker), or
   delete the claim. Complete only when every category has a recorded
   decision. Item 15 doesn't remove a promised-page link before its
   category is dispositioned.
6. Fix ARCHITECTURE.md (counts, migration history, layout reality) and
   improve it: add mermaid text diagrams for the pipeline and registry
   (the style lutaml-model and Plurimath READMEs use) — a Mermaid
   renderer's own docs should draw with Mermaid.

## Done when

- Zero unresolved inventory rows — every row carries its evidence and a
  verified / corrected / removed disposition. **This is the criterion**;
  "no surviving false claim" is not one, because grep cannot classify
  semantic falsity.
- The mechanical half is a checker over `docs/claims-manifest.yml`: for
  every row marked *removed*, its exact claim string must no longer
  appear in any tracked source (excluding `_site/` and `docs/plans/`).
  That is a predicate a CI job can run.
- Generated tables live AND gated for freshness; snippet spec in CI;
  docs build green; the committed manifest exists and items 14/15
  consume it.
- The benchmark question is closed one way or the other: either
  `benchmark:compare` and `benchmark:quick` run and a recorded run is
  committed, or both tasks and every performance claim are deleted. A
  broken advertised command is not an acceptable end state.
- ARCHITECTURE.md carries the pipeline and registry Mermaid diagrams,
  and both parse.
