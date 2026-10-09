# spec/plantuml

PlantUML class and sequence diagram sources extracted from PlantUML's own
test suite by `scripts/extract_plantuml_tests.rb`
(TODO.foundation/12, "Do" step 1). Layout mirrors `spec/mermaid/`:
`<type>/<case id>.puml` plus `<type>/<case id>.meta.json`.

## Provenance: upstream fixtures, NOT real-world files

Every case here is a fixture written by PlantUML's developers to test
PlantUML. **No case in this corpus has real-world provenance** (a diagram
a user wrote for their own documentation). Issue #2 asks for a corpus of
real-world files; this cohort does not satisfy that, and "100% of
oracle-valid" on it must not be read as if it did. Whether it satisfies
the criterion is the owner's decision. Each `.meta.json` carries
`"provenance": "upstream-fixture"`; a real-world case would carry a
different value and a source URL, and none exists yet.

## Selection rule

1. Source files: every `*.puml` under `src/test/resources/` and every
   `*.java` under `src/test/java/` of the pinned upstream checkout.
   `tools/perf-bench/` is a benchmark corpus, not test resources, and is
   excluded.
2. A case is one `@startuml` ... `@enduml` block. `.puml` front matter
   (`expected-*` test directives) is dropped. In Java files only text
   inside `"""` blocks is read, verbatim; Java escape sequences are NOT
   processed (`origin: java-text-block` in the meta).
3. A block is `class` only if it has an explicit class-family
   declaration (`class`, `abstract class`, `interface`, `enum`,
   `annotation`, ...) and no sequence marker. It is `sequence` only if it
   has an explicit sequence marker (`participant`, `actor`, `boundary`,
   `control`, `collections`, `queue`, `activate`, `deactivate`,
   `autonumber`, `alt`/`loop`/`opt`/`par`/`critical`/`break`, `ref over`,
   `== divider ==`, `newpage`) and no class declaration.
4. A block with a marker of another type (`usecase`, `component`, `node`,
   `state`, `start`, `object`, `map`, ...) or an `@start` other than
   `@startuml` is excluded. A block with both class and sequence markers,
   or with neither, is excluded.
5. Bare message diagrams (`A -> B : hi` with no declaration) are excluded
   on purpose: PlantUML infers the type itself, and the same line is valid
   in several diagram types. This under-selects sequence diagrams; it
   never mislabels one. The type is a heuristic, not an oracle verdict;
   step 2 may find a case PlantUML renders as a different type.

Result at the pinned SHA: 37 class, 79 sequence. `!include`/`!define`
blocks are kept and flagged `uses_preprocessor: true`.

## Case IDs

`<upstream path without src/test/ and extension, "/" as ".">[.<test>]--<first
12 hex of SHA-256 of the normalized source>`. Normalized means CRLF to LF,
trailing whitespace stripped, outer whitespace trimmed. There is no
ordinal, so inserting, removing or reordering fixtures upstream never
renames another case. Moving a file or editing a diagram changes that
case's ID, deliberately: it is a different case. Identical blocks from the
same file collapse into one case with `occurrences` counting them.

## Pin

`pin.json` holds the upstream SHA (the extractor refuses any other
checkout), PlantUML/Java/Graphviz versions as observed on the extracting
machine, the jar checksum, and a checksum over the committed corpus
(`corpus.manifest_sha256`). The observed toolchain is not yet a decision:
the installed PlantUML (1.2026.6) is older than the upstream fixtures
(1.2026.9beta4), so step 2 must pick the binary before any verdict exists.

## Regenerating

    git clone https://github.com/plantuml/plantuml.git <dir>
    git -C <dir> checkout <sha from pin.json>
    ruby scripts/extract_plantuml_tests.rb --upstream <dir>

Scoreboard rows live in `scoreboard/plantuml.json`: 0 passing, with no
oracle yet, so the denominator is unknown.
