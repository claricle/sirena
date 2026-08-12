# 17 — Release + versioning (0.x)

Can start: after 01, and after **19a** pins the release workflow — the
first cut would otherwise run through `metanorma/ci@main`, mutable
external code publishing our gem. Small. Blocks: 12 (a demo needs an
installable cut).

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
2. CHANGELOG.md — define the format and what makes an entry
   *releasable*, precisely enough that a job can check it. "Every
   released change lands there" is a rule; the Done criterion below
   needs a predicate.
3. Release mechanics (fixed convention): releases run through the
   cimas-generated `release.yml` — the bot bumps
   `lib/sirena/version.rb`, tags, and pushes the gem. No PR ever bumps
   a version; a PR that wants a release says so in its body and the
   maintainer dispatches. Note that `workflow_dispatch` is not the only
   trigger — `release.yml:9` ALSO accepts `repository_dispatch`
   (`types: [do-release]`), so a release can be fired from outside the
   convention. Either remove that trigger or define exactly who may
   fire it and what it does.
4. The changelog check must be a real prerequisite JOB in the release
   workflow, not a convention. `release.yml` delegates immediately to
   external generated logic, so a preflight has to be added ahead of
   that delegation — and added in the Cimas source item 19a tracks, not
   only in the generated YAML.
5. This item = the PRE-12 release gate, two cuts:
   - post-01 (loads clean) — the weekend status links this installable
     version, not a branch;
   - post-10/16 (multi-notation demo cut).
   The PHASE-END release is item 12's close-out deliverable (listed
   there), NOT this item's — otherwise 17-blocks-12 becomes a cycle.

## Done when

Both pre-12 cuts released with changelog entries; the changelog
preflight job exists in the tracked source and a seeded release with no
releasable entry is blocked by it.

The 0.x versioning contract is committed and names what the public API
promises (`Sirena.render`, `Engine#render`, the CLI) and what is
internal (the item-10 notation plugin shapes) — a contract nobody wrote
down cannot be honoured.

`repository_dispatch` is either removed, or documented with who may
fire it, what authorization it requires and exactly what it does.
