# 01 — elkrb coordination + lutaml-model 0.8 migration

Critical path. Can start: now. Blocks: 02's in-bundle gates, 04, 10, 12, 17.

## Problem

- Cold `bundle install` resolves lutaml-model 0.8.19; the gem crashes at
  require (`lib/sirena/svg/document.rb:27` uses the removed string-URI
  `namespace` form).
- **Verified blocker: elkrb 1.0.2 itself declares `lutaml-model (~> 0.7)`.**
  Raising sirena's floor to 0.8 makes the bundle unresolvable until
  elkrb ships a 0.8-compatible release. claricle/elkrb is in-org.
- Ruby matrix conflict: svg_conform needs Ruby ≥ 3.1, lutaml-model 0.8
  needs ≥ 3.0, gemspec claims ≥ 2.7 (EOL, untested).

## Do

1. **elkrb first** (cross-repo, day one): patch claricle/elkrb to allow
   lutaml-model 0.8 (verify it actually works with 0.8, not just the
   constraint), get it released. Until released, develop against a
   git-pinned elkrb in the Gemfile.
2. Migrate `Svg::Document` to the 0.8 XmlNamespace API; sweep the full
   suite + corpus under 0.8 and fix every difference.
3. Gemspec: lutaml-model `~> 0.8`; set the REAL tested Ruby floor
   (≥ 3.1, driven by svg_conform) — one number, stated everywhere.
4. Output must not change: run the CURRENT corpus pass set before/after
   (614 at last count — use the day's measured set, never this
   number); any differing SVG goes in the PR description with its
   reason (execution-diff gate; one-time PR artifact, not a permanent
   ledger).
5. Fresh-resolution CI job: clean install, no lockfile, full suite —
   catches the next upstream break on push instead of at a user's
   machine.

## Done when

- Clean clone + `bundle install` + `bundle exec rspec`: green, no pins.
- elkrb resolves in the same bundle at lutaml-model 0.8.
- svg_conform installs alongside (proves the conflict is dead).
- 0 failures; the 1 pending xit is owned by item 07.
- Ruby floor tested in CI at the declared minimum and latest stable.

## Files

`lib/sirena/svg/document.rb`, `sirena.gemspec`, CI workflow;
cross-repo: claricle/elkrb gemspec + release.
