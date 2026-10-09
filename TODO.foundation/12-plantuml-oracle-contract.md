# PlantUML oracle contract (item 12, step 2)

Code: `scripts/plantuml_oracle.rb`. Specs: `spec/scripts/plantuml_oracle_spec.rb`.
Measured on PlantUML 1.2026.6, OpenJDK 21.0.2, Graphviz 15.1.1.

## Command

`plantuml --svg --pipe --charset UTF-8`, source on stdin, SVG on stdout, stderr captured.
Binary name is a parameter. Exit codes: 0 rendered, 200 syntax error.

## Predicate (read the SVG, not just the exit code)

Every rendered diagram has a `data-diagram-type` attribute on `<svg>`; the error
image has none. Checked in this order:

| Observed | State |
|---|---|
| spawn failure, timeout, signal | infrastructure |
| stderr names OutOfMemoryError, StackOverflowError, `java.lang.`, IOException, "Cannot run program", "Cannot find Graphviz", missing jar | infrastructure |
| exit other than 0 or 200 | infrastructure |
| stdout is not a well-formed `<svg>` | infrastructure |
| `data-diagram-type` present and exit 0 | **valid** |
| `data-diagram-type` present and exit 200 | infrastructure (contradiction) |
| no `data-diagram-type` and (exit 200, or error text in the SVG) | **rejected** |
| anything else | infrastructure |

Unknown shapes are never a verdict. Infrastructure failure is never written to a verdict file.
Not measured: an exit-0 error image (this version exits 200); the 0 + error-text rule is
defensive for other versions. A Graphviz path that does not exist falls back silently on this
build (exit 0, rendered), so missing Graphviz is detected through stderr and the version probe.

## Timeout

60 s default. On expiry the whole process group gets TERM, then KILL after 2 s, and the run
is infrastructure. Spec: `sh -c "sleep 30 & wait"` with a 1 s timeout returns in under 10 s.

## Canary

Before a refresh: a good source must be valid AND a bad source must be rejected. Either
failing raises `CanaryFailure` and no case is judged.

## Refresh

All-or-nothing. Any infrastructure failure, failed canary, or unreadable version aborts and
the verdict file is untouched (temp file + rename).

## Provenance, per record

`source_sha256`, `svg_sha256`, `plantuml`, `java`, `graphviz` versions, `command`,
`contract` version. A version that cannot be read aborts the refresh.
