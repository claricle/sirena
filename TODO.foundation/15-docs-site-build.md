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
- `docs/Gemfile`: no pins, no lockfile, `theme:` AND `remote_theme:`
  both set, `jekyll-remote-theme` plugin absent (theme silently never
  loads).
- Two link styles; `.html` suffixes 404 under `permalink: pretty`;
  markdown-syntax links inside AsciiDoc render literally; source-path
  links 404; `docs/assets/` missing.
- lychee runs via `links.yml` against `docs/_site` but accepts 403/429
  and misfires anchors against pretty permalinks.
- First step is a fact check: what does `build_deploy.yml` actually do
  on main today — fail, or "succeed" building something else?

## Do

1. Reproduce the build; record the real failure list.
2. Each of the 38 ghost targets: page written (only if item 11 needs
   it) or link removed — after its category's item-11 disposition;
   user-deleted categories go immediately; deferred ones get a
   non-link "planned" marker.
3. Front matter on all diagram-type pages; fix Gemfile (pin, lockfile
   committed — a docs site is an app — theme resolved).
4. One link mechanism compatible with pretty permalinks; convert
   markdown-style links to AsciiDoc.
5. Fix lychee config: no silent 403/429, anchors handled, `_site`
   scoped correctly.
6. Docs build = required status check (repo settings, done with the
   user).

## Done when

`jekyll build` exits 0 locally and in CI; every diagram-type page
renders; zero broken internal links; Gemfile pinned + locked.
