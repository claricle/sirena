# 17 — Release + versioning (0.x)

Can start: after 01. Small. Blocks: 12 (a demo needs an installable cut).

## Problem

Pre-1.0 gem with release automation (`release.yml` → metanorma/ci
rubygems-release) but no versioning discipline in the plan: item 01
changes the dependency floors and Ruby minimum; item 10 changes
internals behind the public API. Nothing owns "cut 0.x, changelog,
what this version promises".

## Do

1. Adopt explicit 0.x semantics: what the public API promises
   (`Sirena.render`, `Engine#render`, CLI), what is internal (notation
   plugin shapes — the item-10 boundary).
2. CHANGELOG.md; every released change lands there.
3. Release mechanics (fixed convention): releases run ONLY through the
   cimas-generated `release.yml` (`workflow_dispatch` with
   `next_version`) — the bot bumps `lib/sirena/version.rb`, tags, and
   pushes the gem. No PR ever bumps a version; a PR that wants a
   release says so in its body and the maintainer dispatches.
4. This item = the PRE-12 release gate, two cuts:
   - post-01 (loads clean) — the weekend status links this installable
     version, not a branch;
   - post-10/16 (multi-notation demo cut).
   The PHASE-END release is item 12's close-out deliverable (listed
   there), NOT this item's — otherwise 17-blocks-12 becomes a cycle.

## Done when

Both pre-12 cuts released with changelog entries; changelog discipline
enforced in CI (release blocked without an entry).
