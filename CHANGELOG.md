# Changelog

All releasable changes to Sirena are recorded here. The contract each version
number makes is in [VERSIONING.md](VERSIONING.md).

## Format

- Sections are `## [Unreleased]` first, then `## [X.Y.Z] - YYYY-MM-DD`, newest
  first.
- Inside a section, bullets sit under `### Added`, `### Changed`,
  `### Deprecated`, `### Removed`, `### Fixed` or `### Security`.
- A change is releasable when it alters what a user of `Sirena.render`,
  `Engine#render` or the CLI can observe. Refactors, specs and CI are not
  entries.
- **Releasable version**: the release preflight
  (`scripts/check_changelog.rb <next_version>`) passes only when a dated
  `## [X.Y.Z]` section exists for the version being cut and holds at least one
  bullet under a category above. Before dispatching a release, a
  changelog-only PR renames `[Unreleased]` to `[X.Y.Z] - date` and adds a
  fresh empty `[Unreleased]`. No PR changes `lib/sirena/version.rb`.

## [Unreleased]

## [0.1.0]

Initial tagged version (`v0.1.0`), released before this changelog existed.
