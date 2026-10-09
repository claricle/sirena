# spec/mermaid

Mermaid diagram sources extracted from the mermaid-js test suite by
`scripts/extract_mermaid_tests.rb`. One directory per diagram type, one
case per `<NNN>_<name>.mmd` file.

## Files per case

| File | Written by | Notes |
|---|---|---|
| `<case>.mmd` | extractor | the diagram source, the only input the corpus renders |
| `<case>.meta.json` | extractor | provenance, fields below |
| `<case>.svg` | an mmdc run | reference sidecar; present for 302 cases, not reproducible by the extractor |
| `<case>.error` | an mmdc run | mmdc's error text; present for 330 cases, machine-specific |

## `.meta.json` fields

Every case has a `.meta.json` (1997 of 1997), and its `type` equals the
directory name in all of them.

| Field | Type | Meaning |
|---|---|---|
| `name` | string | extractor-assigned name; ends in a per-type ordinal, so it is not stable across re-extraction |
| `type` | string | diagram type the extractor detected; the directory name |
| `source_file` | string | upstream file the source came from. Either relative to the mermaid-js checkout (`/cypress/...`) or an absolute path on the extracting machine |
| `line_number` | integer | zero-based newline count before the match in `source_file` (`scripts/extract_mermaid_tests.rb:116` et al.); `0` in 644 files, which is a genuine match on the source's first line, not a sentinel for "no line recorded" -- the extractor always computes this value, it never leaves it unset |
| `metadata` | object | optional, absent in 1055 files; present in the other 942 -- `{}` in 459, `{"test_name": "..."}` in 483 |

There is no upstream commit SHA field yet, so a case cannot be traced to
the mermaid-js revision it came from.

## Verdicts and the scoreboard

`corpus-verdicts.yml` holds one oracle verdict per case
(`scripts/corpus_verdicts.rb`); `scoreboard/corpus.json` holds one
pass/fail row per case (`rake corpus`, checked by `rake corpus:check`).

Both key on the path `<type>/<file>.mmd`, so renaming a case changes its
key in all three places.

Cases that no sidecar, reference or byte-identical twin settles are judged by
the repository-pinned mmdc: `ruby scripts/corpus_verdicts.rb --oracle` writes
`oracle-verdicts.yml` (keyed by source hash, with the mmdc and mermaid
versions it ran under), then `--write` regenerates `corpus-verdicts.yml`
from it. A rejection is recorded only when the same diagnostic, thrown from
mermaid's own code, repeats on a second run; any other failure aborts and
writes nothing.

## Pinned oracle toolchain

Run `npm ci` before any command that asks Mermaid for a verdict or generates
a reference. `package-lock.json` fixes the complete Node dependency tree;
`config/mermaid-oracle.yml` records the exact Node, npm, mmdc, Mermaid,
Puppeteer, Chromium and Noto Sans versions (plus font checksums). Every Ruby
oracle entry point invokes `node_modules/.bin/mmdc` through
`scripts/mermaid_toolchain.rb`; an `mmdc` elsewhere on `PATH` is ignored.

Use `npm run oracle:check` (or `rake mermaid:oracle_check`) to detect drift.
Use `npm run oracle:canary` (or `rake mermaid:oracle_canary`) to additionally
launch the pinned Chromium and render a known-valid diagram. CI runs both.

The fixture command `rake mermaid:generate_fixtures` uses the same entry
point, Mermaid config and font stylesheet. Updating any pinned component is a
reviewed toolchain change: update the lockfile and provenance together, prove
the canary, then refresh verdicts and references in the separate regeneration
change. This pinning change intentionally does not regenerate either artifact.

## Known duplicate directories

`class`/`class_diagram`, `er`/`er_diagram`, `state`/`state_diagram` and
`git`/`gitgraph` each hold cases for one diagram type. They are not yet
merged; `state` and `state_diagram` share 14 file names, so a merge needs
new case IDs first.
