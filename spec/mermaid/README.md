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
| `line_number` | integer | line of the match in `source_file`; `0` in 644 files, where the extractor recorded no line |
| `metadata` | object | optional, absent in 1055 files. Empty, or `{"test_name": "..."}` in 483 files |

There is no upstream commit SHA field yet, so a case cannot be traced to
the mermaid-js revision it came from.

## Verdicts and the scoreboard

`corpus-verdicts.yml` holds one oracle verdict per case
(`scripts/corpus_verdicts.rb`); `scoreboard/corpus.json` holds one
pass/fail row per case (`rake corpus`, checked by `rake corpus:check`).
Both key on the path `<type>/<file>.mmd`, so renaming a case changes its
key in all three places.

## Known duplicate directories

`class`/`class_diagram`, `er`/`er_diagram`, `state`/`state_diagram` and
`git`/`gitgraph` each hold cases for one diagram type. They are not yet
merged; `state` and `state_diagram` share 14 file names, so a merge needs
new case IDs first.
