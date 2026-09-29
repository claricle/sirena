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

### Changed

#62 renamed most of the gem's parser, renderer, layout and diagram-model
classes. Every rename below is a plain name change: nothing was removed
except where a row says so.

- Diagram model classes (`Sirena::Diagram`):

  | Old name | New name |
  | --- | --- |
  | `Diagram::GanttChart` | `Diagram::Gantt` |
  | `Diagram::QuadrantChart` | `Diagram::Quadrant` |
  | `Diagram::RadarChart` | `Diagram::Radar` |
  | `Diagram::ArchitectureDiagram` | `Diagram::Architecture` |
  | `Diagram::ArchitectureDiagram::Group` | `Diagram::Architecture::Group` |
  | `Diagram::ArchitectureDiagram::Service` | `Diagram::Architecture::Service` |
  | `Diagram::ArchitectureDiagram::Edge` | `Diagram::Architecture::Edge` |
  | `Diagram::SankeyDiagram` | `Diagram::Sankey` |
  | `Diagram::PacketDiagram` | `Diagram::Packet` |
  | `Diagram::TreemapDiagram` | `Diagram::Treemap` |
  | `Diagram::XYChart` | `Diagram::XyChart` |
  | `Diagram::BlockDiagram` | `Diagram::Block` |
  | `Diagram::Block` (single block) | `Diagram::BlockNode` |
  | `Diagram::RequirementDiagram` | `Diagram::Requirement` |
  | `Diagram::Requirement` (single requirement) | `Diagram::RequirementNode` |

  The last two pairs each reuse a name: the old per-item class moves aside so
  the whole-diagram class can take its plain name.

- Parser classes (`Sirena::Parser`): every class ending in `Parser` dropped
  that suffix, e.g. `Parser::FlowchartParser` -> `Parser::Flowchart`. Applies
  to `Block`, `C4`, `ClassDiagram`, `ErDiagram`, `Error`, `Flowchart`,
  `Gantt`, `GitGraph`, `Info`, `Kanban`, `Mindmap`, `Packet`, `Pie`,
  `Quadrant`, `Radar`, `Requirement`, `Sankey`, `Sequence`, `StateDiagram`,
  `Timeline`, `Treemap`, `UserJourney`. `Parser::XYChartParser` became
  `Parser::XyChart` (suffix dropped and capitalization changed).
  `Parser::Architecture` already had a plain name and did not change.
  `Parser::Grammars::XYChart` became `Parser::Grammars::XyChart`
  (capitalization only; every other grammar class kept its name).

- Renderer classes (`Sirena::Renderer`): every class ending in `Renderer`
  dropped that suffix, e.g. `Renderer::FlowchartRenderer` ->
  `Renderer::Flowchart`. Applies to `Architecture`, `Block`, `C4`,
  `ClassDiagram`, `ErDiagram`, `Error`, `Flowchart`, `Gantt`, `Info`, `Pie`,
  `Quadrant`, `Requirement`, `Sankey`, `Sequence`, `StateDiagram`,
  `Timeline`, `UserJourney`. `Renderer::XYChart` became `Renderer::XyChart`
  (capitalization only).

- The `Sirena::Transform` module was renamed to `Sirena::Layout`, and every
  class ending in `Transform` dropped that suffix at the same time, e.g.
  `Transform::FlowchartTransform` -> `Layout::Flowchart`. Applies to
  `Architecture`, `Block`, `C4`, `ClassDiagram`, `ErDiagram`, `Error`,
  `Flowchart`, `Gantt`, `Info`, `Pie`, `Quadrant`, `Requirement`, `Sankey`,
  `Sequence`, `StateDiagram`, `Timeline`, `UserJourney`. Classes that already
  had a plain name only moved namespace: `Transform::GitGraph`,
  `Transform::Kanban`, `Transform::Mindmap`, `Transform::Packet`,
  `Transform::Radar`, `Transform::Treemap`, `Transform::Base` became
  `Layout::GitGraph`, `Layout::Kanban`, `Layout::Mindmap`, `Layout::Packet`,
  `Layout::Radar`, `Layout::Treemap`, `Layout::Base`.
  `Transform::XYChart` became `Layout::XyChart` (namespace and
  capitalization). `Transform::TransformError` was removed; its replacement
  is `Sirena::Layout::LayoutError`.

- The `Sirena::Parser::Transforms` module was renamed to
  `Sirena::Parser::Builders`; class names inside it did not change, e.g.
  `Parser::Transforms::Flowchart` -> `Parser::Builders::Flowchart`,
  `Parser::Transforms::Kanban::BoardBuilder` ->
  `Parser::Builders::Kanban::BoardBuilder`. `Parser::Transforms::XYChart`
  became `Parser::Builders::XyChart` (capitalization only, on top of the
  namespace rename).

## [0.1.0]

Initial tagged version (`v0.1.0`), released before this changelog existed.
