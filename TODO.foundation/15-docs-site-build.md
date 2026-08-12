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
- `docs/Gemfile`: no pins, no tracked lockfile, `theme:` AND `remote_theme:`
  both set, `jekyll-remote-theme` plugin absent (theme silently never
  loads).
- Two link styles; `.html` suffixes 404 under `permalink: pretty`;
  markdown-syntax links inside AsciiDoc render literally; source-path
  links 404; `docs/assets/` missing.
- **lychee never reads its config.** `links.yml:46` runs from the repo
  root with `--config lychee.toml`, but the only config is
  `docs/lychee.toml`. So the tuning nobody knew was inert is inert:
  403/429 acceptance and anchor handling are whatever lychee defaults
  to, not what the file says.
- One of the front-matter targets is generated:
  `docs/_diagram_types/examples/flowchart-examples.adoc` is rewritten by
  `lib/tasks/examples.rake:108`, which emits no front matter, and
  `examples:build` always calls it. Hand-adding front matter there gets
  overwritten on the next build.
- `docs/Gemfile.lock` exists on disk but is git-ignored, and lists only
  `arm64-darwin` — docs CI runs Ubuntu, and the dependency set has
  native gems. Committing it as-is does not make CI reproducible.
- First step is a fact check: what does `build_deploy.yml` actually do
  on main today — fail, or "succeed" building something else?

## Do

1. Reproduce the build; record the real failure list.
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
4. Fix `docs/Gemfile`: pin versions, resolve the `theme:` /
   `remote_theme:` conflict, and commit a lockfile that CI can actually
   use — regenerate it on Linux or add the supported platforms, then
   prove `bundle install` leaves it unchanged in CI. Lift the ignore
   with a narrow `!/docs/Gemfile.lock` exception; do NOT unignore the
   root library lockfile.
5. One link mechanism compatible with pretty permalinks; convert
   markdown-style links to AsciiDoc.
6. Point lychee at the real config (`--config docs/lychee.toml`, or run
   it with `docs` as the working directory), THEN fix the config: no
   silent 403/429, anchors handled, `_site` scoped correctly.
7. Docs build = required status check (repo settings, done with the
   user).

## Done when

- `jekyll build` exits 0 locally and in CI.
- A source-to-output manifest assertion proves every diagram page in the
  set chosen at step 3 (24 or 25) reached `_site`, and — if the include
  route was taken — that the include's content appears in its host page.
  "The directory exists" is the check that already failed to catch this.
- No literal `{% link %}` text survives in published output.
- The selected theme's layout and assets are present in `_site`.
- lychee runs against the real config, and two seeded failures prove it
  bites: one broken relative link, one broken fragment.
- Gemfile pinned, lockfile committed and CI-complete.
