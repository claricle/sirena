# Versioning and releases

Sirena is pre-1.0. This file is the contract behind each version number.

## What 0.x promises

Version `0.MINOR.PATCH`:

- **PATCH** releases fix bugs and do not change the public API below.
- **MINOR** releases may change the public API. Every such change is listed
  under `### Changed` or `### Removed` in [CHANGELOG.md](CHANGELOG.md), with
  the old and new behaviour.
- **1.0.0** is not scheduled. Until then nothing outside the public API is
  stable.

Rendered SVG is not byte-stable across any release. Diagram output improves as
the corpus pass rate rises; do not diff it.

## Public API

Only these are covered by the promise:

| Surface | Contract |
|---|---|
| `Sirena.render(source, options = {})` | Returns an SVG String; raises on unparseable or unsupported input. |
| `Sirena::Engine#render(source, options = {})` | Same behaviour; the documented `options` keys are `theme:` (name, `Theme` or Hash), `verbose:` and `today:`. Other keys are ignored. |
| CLI `sirena render`, `sirena batch`, `sirena types`, `sirena version` (`--version`, `-V`) | Command names, documented options, `render` exiting 1 on error. `batch` rescues per-file failures and exits 0; that is current behaviour, not a promise. |
| `Sirena::VERSION` | The released version string. |

## Internal

Everything else, whatever its visibility, may change in any release without a
changelog entry: parsers, grammars, diagram models, transforms, renderers,
`Sirena::Svg`, layout, `DiagramRegistry`, `Theme::Registry`, error class
hierarchy, and the notation plugin shapes that item 10 introduces. A notation
plugin shape becomes public only when this file lists it.

## Releasing

1. Merge changes; each releasable one adds a bullet under `## [Unreleased]`.
2. Open a changelog-only PR that renames `[Unreleased]` to
   `[X.Y.Z] - YYYY-MM-DD` and adds an empty `[Unreleased]`. A PR that wants a
   release says so in its body. No PR edits `lib/sirena/version.rb`.
3. The maintainer dispatches the `release` workflow (`workflow_dispatch`) with
   `next_version`. The bot bumps `lib/sirena/version.rb`, tags and pushes the
   gem.
4. The changelog preflight (`scripts/check_changelog.rb <next_version>`) must
   pass before the delegated release job starts. The script is committed; wiring
   it into `release.yml` waits for item 19a's decision on that file (see
   "Open" below).

## How a release reaches protected `main`

Decision (item 17 step 5): **the release bot gets a narrow, recorded
branch-protection bypass, and the bump is verified before it is used.**

Why not the alternatives: promoting an already-checked SHA cannot work because
`gem bump` must change `version.rb`, which makes a new SHA by definition; a
checked bump PR contradicts the convention that no PR bumps a version.

Conditions of the bypass:

- Bypass actor: the release workflow's identity only, on the `main` ruleset.
- The release job first asserts that the `main` head it is bumping has both
  lane aggregators green (the checks 19a names) and that the bump commit changes
  `lib/sirena/version.rb` and nothing else. Either assertion failing aborts
  before the push.
- Tag pushes made with `GITHUB_TOKEN` trigger no workflows; nothing downstream
  relies on them running.

Applying the bypass is a repository setting only the owner can make, and 19a
owns the protection settings. It is not applied yet.

## `repository_dispatch` (`do-release`)

`release.yml` accepts `repository_dispatch` with `types: [do-release]`. Facts
measured against `metanorma/ci` `rubygems-release.yml` at
`875ae77e781264728ec8447c11b23d3335b68d6d`:

- **What it does:** on that event the reusable workflow skips preflight and the
  bump step, then publishes the gem for whatever version is in `version.rb` at
  the default branch head. If that version is already on RubyGems the
  idempotent push guard skips the push.
- **Who may fire it:** anyone whose token can call
  `POST /repos/{owner}/{repo}/dispatches` (repository write access), plus the
  workflow token of this repo's own CI on a `v*` tag push (the `cascade` job
  of item 19a's `ci.yml`).
- **Authorization it requires:** nothing beyond that write access; the
  dispatch carries no approval step and runs no changelog preflight.

So a `do-release` publishes without the changelog check. Until the preflight is
wired to cover that event too, treat `do-release` as maintainer-only, and
prefer removing the trigger once `cascade` no longer needs it.

## Open

- Wiring the changelog preflight job into `release.yml` and deciding whether to
  drop `repository_dispatch`: blocked on the 19a branch (`p2/ci-lane-19a`),
  which edits `release.yml` and `ci.yml`.
- Applying the branch-protection bypass: owner action.
- Both pre-item-12 cuts: blocked on items 01 and 10/16 landing.
