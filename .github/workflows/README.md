# CI lanes

`ci.yml` holds two lanes. Both must pass before merge.

| Lane | Aggregator (required check) | Contents today | Budget |
|---|---|---|---|
| Fast | `fast-lane` | `unit` (`bundle exec rake` on Ruby 3.3/3.4/4.0-experimental x ubuntu/macos/windows), `pins`, `lint` (`bundle exec rubocop` and `bundle exec rake lint:debt:check`) | < 10 min |
| Full | `full-lane` | `docs-build` (build_deploy.yml), `links` (links.yml), `corpus` (`rake corpus:check`), `conformance` (`rake conformance:check` and `spec/svg_conformance_spec.rb`), `fresh-resolution` (no lockfile, no bundle cache: install, require `sirena` and `svg_conform`, full `rspec`) | < 30 min |

Reserved, not yet wired: snippet spec (16), parity (14; no comparator or
parity spec exists yet), scoreboard guard (02b; goes in BOTH lanes). `lint`
(19b) is folded into the fast lane as an ordinary job hanging off
`fast-lane`; there is no standalone `lint.yml` workflow, and no separate
`lint / rubocop` required check.

Budgets are targets. No cold or warm timing has been measured: that needs
CI runs of the lanes as they now stand (19b step 9).

`unit` runs `bundle exec rake`, whose default task already includes
`corpus:check`, so the `corpus` job repeats it once on its own: it is the
named check in the full lane, and the one place a corpus regression reads as
"corpus" instead of as a failure inside a Ruby/OS matrix cell. The
conformance spec likewise runs inside `unit` and again in `conformance`;
`rake conformance:check` (the scoreboard ratchet) runs nowhere else in CI.
`fresh-resolution` runs the whole suite again on purpose: it is the only job
that resolves gems without a cache.

## Branch protection (owner applies; a repository setting, not YAML)

Owner action after merge (no branch protection exists today): mark `fast-lane`
and `full-lane` as required checks. Also require ONE of: "Require branches to
be up to date before merging" (strict), or a merge queue (the lanes already
run on `merge_group`). Record which, and the date, here once applied:
NOT YET APPLIED. Re-checked 2026-10-07 after the full lane gained `corpus`,
`conformance` and `fresh-resolution` (19b step 10): the required names are
still exactly `fast-lane` and `full-lane`, and
`gh api repos/claricle/sirena/branches/main/protection` still answers 404
with no rulesets defined, so nothing is required today.

## Adding a gate to a lane

1. Add one job to `ci.yml`, with `timeout-minutes` (a `uses:` job cannot have one; put it inside the called workflow).
2. Add its id to the `needs:` of the aggregator for its lane. A job in `ci.yml` that no aggregator needs fails `spec/workflows/workflows_spec.rb`.
3. Never rename `fast-lane` / `full-lane`.
4. Oracle and comparison specs FAIL, not skip, when their binary is missing in CI. Skip loudly only locally.
5. Provision your own toolchain inside your job (02a: oracle, 12: PlantUML/Java/Graphviz).

Worked example, the `conformance` job as it sits in the full lane:

```yaml
  conformance:
    name: conformance
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262  # v4
      - uses: ruby/setup-ruby@a0102e0972be65f351c307e2d64b9314a57c8073  # v1
        with:
          ruby-version: '3.3'
          bundler-cache: true
      - run: bundle exec rake conformance:check
      - run: bundle exec rspec spec/svg_conformance_spec.rb
  # ...and in full-lane:  needs: [docs-build, links, corpus, conformance, fresh-resolution]
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
metanorma tool installers, private fonts. Its `tests-passed` and
`do-release` repository dispatches moved to the `cascade` job, and now fire
only on push events (generic-rake also fired on pull requests). `cascade`
needs only `fast-lane` (the `unit` matrix, pins, lint), matching the old
gate on the test matrix; `links` and the rest of `full-lane` do not gate it,
so an external-link outage cannot suppress a release. The Ruby/OS matrix is
hard-coded in `unit`; it was previously fetched from metanorma's
`ruby-matrix.json` (identical today).

## Cimas

`release.yml` is detached from Cimas; no generator is tracked here, so this
YAML is authoritative. It pins `rubygems-release.yml` by SHA, but that
workflow itself calls mutable refs (@main, @v3, @v2.1.0): `gh-rubygems-setup-action`,
`version-advisory-action`, `gem-idempotent-push-guard-action`,
`peter-evans/repository-dispatch@v3`, `rubygems/configure-rubygems-credentials`).
Those transitive refs are NOT pinned; item 17 owns vendoring that workflow.
