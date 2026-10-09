# 15 — Docs site build integrity

Can start: now. Pairs with 11 (this is mechanics; 11 is truth).

## Facts (verified)

- 51 `{% link %}` occurrences reference 38 nonexistent files.
  [MEASURED 2026-08-10: the build EXITS 0 — jekyll-asciidoc doesn't
  Liquid-process these pages, so the tags render as literal text
  instead of raising. Defect stands (broken links + literal tag text
  on published pages); "cannot build" was the wrong mechanism.]
- 23 of 25 `_diagram_types/*.adoc` lack YAML front matter (incl. the
  orphaned `examples/` page) — Jekyll skips them entirely.
- `docs/Gemfile` exactly pins all seven direct dependencies, and
  `docs/_config.yml` selects only `theme: just-the-docs`. The owner ruled
  in PR #111 that Sirena commits no lockfiles, including
  `docs/Gemfile.lock`; exact docs Gemfile pins satisfy this criterion.
- Two link styles; `.html` suffixes 404 under `permalink: pretty`;
  markdown-syntax links inside AsciiDoc render literally; source-path
  links 404; `docs/assets/` missing.
- **lychee never reads its config.** `links.yml:46` runs from the repo
  root with `--config lychee.toml`, but the only config is
  `docs/lychee.toml`. So none of that tuning has ever taken effect:
  403/429 acceptance and anchor handling are whatever lychee defaults
  to, not what the file says.
- One of the front-matter targets is generated:
  `docs/_diagram_types/examples/flowchart-examples.adoc` is rewritten by
  `lib/tasks/examples.rake:108`, which emits no front matter, and
  `examples:build` always calls it. Hand-adding front matter there gets
  overwritten on the next build.
- A machine-local `docs/Gemfile.lock` may exist, but `Gemfile.lock` is
  intentionally git-ignored for this library. It is not a project
  artifact and must not be committed or used as CI evidence.

## Do

1. Reproduce the build and record the real failure list — including
   what `build_deploy.yml` actually does on main today: fail, or
   "succeed" while publishing something incomplete.
2. Each of the 38 ghost targets: page written (only if item 11 needs
   it) or link removed — after its category's item-11 disposition;
   user-deleted categories go immediately; deferred ones get a
   non-link "planned" marker.
3. Front matter on the diagram-type pages. For the generated
   `examples/` page, pick one and record which:
   - **Include**: it stops being a page. The expected page set drops to
     24, and a separate assertion proves the include's content actually
     appears in its host page.
   - **Page**: teach `examples.rake` to emit deterministic front matter
     and add a regenerate-and-diff check. The page set stays 25.

   Whichever is chosen, the Done manifest below counts the RESULTING
   page set, not a fixed 25. Hand-editing a generated file is not a fix.
4. Keep every direct dependency in `docs/Gemfile` exactly pinned and keep
   one selected theme in `_config.yml`. Preserve the owner's PR #111
   no-lockfile ruling: do not commit `docs/Gemfile.lock` or add an ignore
   exception for it. Docs CI installs from the exact pins under the docs
   bundle.
5. One link mechanism compatible with pretty permalinks; convert
   markdown-style links to AsciiDoc.
6. Point lychee at the real config (`--config docs/lychee.toml`, or run
   it with `docs` as the working directory), THEN fix the config: no
   silent 403/429, anchors handled, `_site` scoped correctly.
7. Docs build = required status check (repo settings, done with the
   user).

## Done when

- `jekyll build` exits 0 locally and in CI. (It already does today —
  that is why every criterion below checks the OUTPUT instead.)
- A source-to-output manifest assertion proves every diagram page in the
  set chosen at step 3 (24 or 25) reached `_site`, and — if the include
  route was taken — that the include's content appears in its host page.
  "The directory exists" is the check that already failed to catch this.
- No literal `{% link %}` text survives in published output.
- The selected theme's layout and assets are present in `_site`.
- lychee runs against the real config, and two seeded failures prove it
  bites: one broken relative link, one broken fragment.
- Every direct docs dependency is exactly pinned, docs CI installs that
  bundle, and no lockfile is committed, per the owner's PR #111 ruling.
- lychee no longer accepts 403/429 silently — a seeded link of each
  kind fails the run.
- The owner has made the docs build a required status check, and that
  is recorded.
