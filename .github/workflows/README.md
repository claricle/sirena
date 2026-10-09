# CI lanes

`ci.yml` holds two lanes. Both must pass before merge.

| Lane | Aggregator (required check) | Contents today | Budget |
|---|---|---|---|
| Fast | `fast-lane` | `unit` (`bundle exec rake` on Ruby 3.3/3.4/4.0-experimental x ubuntu/macos/windows), `pins`, `lint` (`bundle exec rubocop` and `bundle exec rake lint:debt:check`) | < 10 min |
| Full | `full-lane` | `docs-build` (build_deploy.yml), `links` (links.yml), `conformance` (`rake conformance:check`), `fresh-resolution` (no lockfile, `bundle exec rake`), `plantuml-toolchain` (pinned PlantUML jar + Java 21 + Graphviz, `spec/plantuml/toolchain_probe_spec.rb`) | < 30 min |

Reserved, not yet wired: snippet spec (16), parity (14). Corpus (02b) runs
inside `unit` (`bundle exec rake` includes `corpus:check`). The scoreboard guard (02b)
goes in BOTH lanes. `lint` (19b) is folded into the fast lane as an ordinary
job hanging off `fast-lane`; there is no standalone `lint.yml` workflow, and
no separate `lint / rubocop` required check.

Budgets are targets. No cold or warm timing has been measured (19b).

## Branch protection (owner applies; a repository setting, not YAML)

Owner action after merge (no branch protection exists today): mark `fast-lane`
and `full-lane` as required checks. Also require ONE of: "Require branches to
be up to date before merging" (strict), or a merge queue (the lanes already
run on `merge_group`). Record which, and the date, here once applied:
NOT YET APPLIED.

## Adding a gate to a lane

1. Add one job to `ci.yml`, with `timeout-minutes` (a `uses:` job cannot have one; put it inside the called workflow).
2. Add its id to the `needs:` of the aggregator for its lane. A job in `ci.yml` that no aggregator needs fails `spec/workflows/workflows_spec.rb`.
3. Never rename `fast-lane` / `full-lane`.
4. Oracle and comparison specs FAIL, not skip, when their binary is missing in CI. Skip loudly only locally.
5. Provision your own toolchain inside your job (02a: oracle, 12: PlantUML/Java/Graphviz). The PlantUML jar version and sha256 live in `spec/plantuml/pin.json`; `scripts/install_plantuml.sh` reads them and refuses a checksum mismatch. Graphviz comes from apt and is NOT version-pinned; the spec only checks that `dot` runs.

Worked example, a conformance job for the full lane:

```yaml
  conformance:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262  # v4
      - uses: ruby/setup-ruby@a0102e0972be65f351c307e2d64b9314a57c8073  # v1
        with: { ruby-version: '3.3', bundler-cache: true }
      - run: bundle exec rspec spec/svg_conformance_spec.rb
  # ...and in full-lane:  needs: [docs-build, links, conformance]
```

## External pins

Every external `uses:` is a 40-hex commit SHA with the tag in a trailing
comment; `scripts/check_workflow_pins.rb` (job `pins`) rejects anything else.

Bump procedure: `gh api repos/<owner>/<repo>/commits/<tag-or-branch> --jq .sha`,
replace the SHA, update the comment, run `bundle exec rspec spec/workflows`.

## What generic-rake ran (audit, metanorma/ci@875ae77e)

Explicit now in `unit`: checkout, `ruby/setup-ruby` with bundler cache,
`bundle exec rake` over the matrix from its `ruby-matrix.json` (3.3, 3.4,
4.0 experimental; macos, ubuntu, windows). Not carried over: Java 17 setup
(nothing here uses it), recursive submodules (there are none), the
metanorma tool installers, private fonts. Its `tests-passed` repository
dispatch moved to the `cascade` job and now fires only on push events
(generic-rake also fired on pull requests). `cascade` needs only `fast-lane`
(the `unit` matrix, pins, lint), matching the old gate on the test matrix.
The old tag-triggered `do-release` dispatch was removed: releases now start
only from `release.yml`'s manual dispatch and must pass its changelog preflight.
The Ruby/OS matrix is hard-coded in `unit`; it was previously fetched from
metanorma's `ruby-matrix.json` (identical today).

## Repository-owned release

`release.yml` is detached from Cimas; no generator is tracked here, so this
YAML is authoritative. It contains the complete release implementation and
does not call an external reusable workflow or install a release helper. Its
only external actions are checkout and Ruby setup, both pinned to immutable
commit SHAs.

The manual entrypoint first runs `scripts/check_changelog.rb` with the
requested version. The publishing job then verifies that the workflow source
is the current `main` head and that the latest `fast-lane` and `full-lane`
checks for that exact SHA succeeded. It generates a commit that may change
only `lib/sirena/version.rb`, verifies the requested version through
`scripts/check_release_source.rb`, builds the gem, atomically pushes the
version commit and tag, and publishes with the repository's RubyGems API key.

The remaining owner action is to grant the release workflow's identity a
narrow bypass on the protected `main` ruleset. Until that bypass is applied,
the repository-owned release intentionally cannot push its generated version
commit.
