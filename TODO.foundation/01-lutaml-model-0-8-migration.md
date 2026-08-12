# 01 — lutaml-model 0.8 migration

Critical path, and the FIRST thing that lands — nothing else can be
green before it. `bundle exec rspec` today reports "0 examples, 1 error
occurred outside of examples", so the suite, coverage instrumentation
and every CI lane are all blocked on this item's migration.

Can start: now. Blocks: 02's in-bundle gates, 03a, 04, 10, 12, 17, 14's
integration work, and 19a's lanes.

**Starts first, closes last of the wave.** The migration itself (step 1,
`document.rb` + gemspec) touches no CI and lands immediately. The CI
criteria below — Ruby matrix, fresh-resolution job — need a lane, which
is 19a, which in turn needs the suite this item repairs. So the running
order is: 01's migration → 03a instrumentation → 19a lanes → 01's lane
entry → this item closes.

Item 03 records the one consequence: 01's migration PR predates the
changed-line gate and is explicitly exempt from it, stating its
coverage in the PR body instead.

All in-repo work — no cross-repo release is required (re-verified
2026-08-11; see below).

## Problem

- Cold `bundle install` resolves lutaml-model 0.8.19 because sirena's
  own gemspec floor is `~> 0.7` (which admits 0.8.x); the gem then
  crashes at require (`lib/sirena/svg/document.rb:27` uses the removed
  string-URI `namespace` form).
- **elkrb does NOT block this** (proven 2026-08-11 by live `bundle
  lock` + require smoke test): elkrb 1.0.2's `lutaml-model ~> 0.7`
  constraint means `>= 0.7, < 1.0` and admits 0.8.x — a bundle with
  lutaml-model 0.8.19 + elkrb 1.0.2 resolves and `require 'elkrb'`
  works. An earlier revision of this item wrongly read the constraint
  as blocking and put a cross-repo elkrb release on the critical path.
  elkrb's FUNCTIONAL behavior under 0.8 is untested — item 14 owns
  proving that when integration starts (elkrb is not called today).
- svg_conform 0.2.1 requires `lutaml-model ~> 0.8.0` — so the local
  0.7-pin workaround makes svg_conform uninstallable in the same
  bundle. Item 04 can only run after this item lands.
- Ruby matrix conflict: svg_conform needs Ruby ≥ 3.1, lutaml-model 0.8
  needs ≥ 3.0, gemspec claims ≥ 2.7 (EOL, untested).

## Do

1. Migrate `Svg::Document` to the 0.8 XmlNamespace API. TWO changes at
   `document.rb:27`, not one: replace the string namespace
   (`namespace SVG_NAMESPACE, 'svg'`) with an XmlNamespace class, AND
   move the positional `'svg'` prefix into it via `prefix_default`
   (0.8 deprecates the positional prefix and warns it will be
   ignored — output may differ; the sweep must catch it).
2. Sweep the full suite + corpus under 0.8 and fix every difference.
3. Gemspec: lutaml-model `~> 0.8.0` — pessimistic to the patch series,
   NOT `~> 0.8` (that admits an untested 0.9, repeating exactly the
   mistake this item exists to fix). Widening to 0.9 is a later,
   tested change.
4. Set the REAL tested Ruby floor (≥ 3.1, driven by svg_conform) — one
   number, stated in EVERY version-bearing file: `sirena.gemspec`,
   `README.adoc`, `docs/_guides/installation.adoc`, and `.rubocop.yml`
   (`TargetRubyVersion`, currently 3.0). `.rubocop.yml`
   is also touched by item 08 — whichever lands second rebases; the
   floor value is this item's call.
5. Add `svg_conform` to the `Gemfile` (development group) constrained
   to `~> 0.2.0`, so the same-bundle smoke below can actually run.
6. **Output is expected to stay byte-identical, and every exception is
   explained.** The prefix change at step 1 could move it, which is
   exactly why this is measured rather than assumed: run the CURRENT
   corpus pass set before/after (whatever the day's measured set is —
   never a hardcoded count). Zero differing SVGs is the target; any
   difference must be traced to the prefix migration and written into
   the PR description with its reason. An unexplained difference blocks
   the merge (execution-diff gate; one-time PR artifact, not a permanent
   ledger).
7. Fresh-resolution job: clean install, no lockfile, full suite — it
   catches the next upstream break on push instead of at a user's
   machine. Added to 19a's full lane through the extension contract,
   since 19a owns the workflow files.
8. Optional hygiene, NOT blocking: ask claricle/elkrb to loosen/confirm
   its constraint for 0.8 (repo dormant since 2025-11-14, no 0.8 work
   in flight; only 1.0.0 and 1.0.2 published).

## Done when

- Clean clone + `bundle install` + `bundle exec rspec`: green, with the
  local 0.7 workaround gone (the `svg_conform ~> 0.2.0` constraint added
  at step 5 stays — a declared version constraint is not a workaround
  pin).
- elkrb resolves in the same bundle at lutaml-model 0.8 (true today —
  kept as a regression guard).
- svg_conform installs alongside AND a smoke test requiring both
  `sirena` and `svg_conform` in the same unpinned bundle succeeds
  (install alone can already resolve today; the REQUIRE only works
  post-migration — that's what proves the conflict dead).
- 0 failures; the 1 pending xit is owned by item 07 (sub-track 07f).
- Ruby floor tested in CI at the declared minimum and latest stable.
- `sirena.gemspec` declares `lutaml-model ~> 0.8.0` exactly — not
  `~> 0.8`, checked by reading the line.
- The before/after corpus run over the current pass set shows zero
  differing SVGs, or each difference is traced to the prefix migration
  in the PR body.
- The fresh-resolution job exists in 19a's full lane and runs with no
  lockfile.
- Every file in the list below states the same Ruby floor, checked by
  reading each one — a grep can find the string `2.7` but cannot tell a
  stale floor claim from a changelog mention.

## Files

`lib/sirena/svg/document.rb`, `sirena.gemspec`, `Gemfile`,
`README.adoc`, `docs/_guides/installation.adoc`,
`.rubocop.yml`, and one lane entry in `.github/workflows/` (19a owns
those files).
