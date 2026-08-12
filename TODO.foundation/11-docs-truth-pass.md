# 11 — Docs truth: claims generated, not hand-written

Can start: NOW — the claim inventory and the promised-features
dispositions read files, they don't need a building site. Only
publishing the corrected pages waits for 15; the dispositions this item
produces are what 15 needs to resolve ghost links (explicit handoff, no
cycle). Parallel with everything; does not block PlantUML.

## Problem

Docs claim what measurement disproves: "100% Syntax Parity" for types
at 3–6%, "95%+ compatible", fabricated benchmarks ("16x faster" — no
harness exists), ELK layout, 19-vs-24 type counts, broken quick-start
code (`Engine.render`/`render_file` don't exist), invented CLI env vars
and exit codes, `high-contrast` vs the real `high_contrast`, "37
examples" vs 53 on disk. Docs also promise unbuilt features (plugins,
caching, Rails/Jekyll/Sinatra integration, error-code taxonomy, 38
absent pages).

## Do

1. Claim inventory: one row per factual assertion across README,
   ARCHITECTURE.md, CLAUDE.md, docs/ — source, evidence, disposition.
   Every row ends verified / corrected / removed. No unresolved rows.
2. **Numbers are generated**: compatibility tables and pass rates render
   from the scoreboard (rake task), so corpus progress can't restale
   the docs. Hand-written numbers are banned in support claims.
3. Executable snippets: every README/docs code example runs in a
   doc-snippet spec.
4. Promised-features disposition: each category goes to the user —
   build (creates an owned item), defer (explicit "planned" marker), or
   delete the claim. Complete only when every category has a recorded
   decision. Item 15 doesn't remove a promised-page link before its
   category is dispositioned.
5. Fix ARCHITECTURE.md (counts, migration history, layout reality) and
   improve it: add mermaid text diagrams for the pipeline and registry
   (the style lutaml-model and Plurimath READMEs use) — a Mermaid
   renderer's own docs should draw with Mermaid.

## Done when

Zero unresolved inventory rows; generated tables live; snippet spec in
CI; docs build green.
