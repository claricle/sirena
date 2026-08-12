# 07 — Corpus burndown: class and all remaining types

Can start: after 02. Same target, method, and parallelism as item 06.

## Sub-tracks (parallel; ordered by failing-case count)

| Sub-todo | Cases | Today |
|---|---|---|
| 07a class (+class_diagram) | 465 | ~27% — biggest absolute slice |
| 07b sequence | 126 | 48% |
| 07c git (+gitgraph) | 168 | 66% |
| 07d gantt, radar, kanban, user_journey | ~144 | 24–39% |
| 07e architecture, c4, block | ~92 | 31–60% |
| 07f finishing: mindmap, requirement, timeline, pie, packet, quadrant, sankey, xychart, info, error | small | 92–100% |

07f also owns: the suite's only pending example
(`spec/sirena/parser/packet_spec.rb:74` xit — implement or delete with
justification; zero pending after) and closing every type in this
tier to 100% of oracle-valid.

Known bucket for 07d (found in the radar rehearsal, 2026-08-10): the
**parslet singleton-capture crash family** — a single-element capture
comes back as a Hash, not a one-element Array. `curve c1{A: 1}` →
NoMethodError in `parser/radar.rb:80-94`; `axis A` → TypeError from
the `Array(hash)` idiom in `transforms/radar.rb:66`. Every sub-track's
first triage step includes a grep-audit for the same
single-capture/`Array(...)` idiom in its own type's parser+transform —
the family likely affects other types.

## Done when

Every canonical corpus type that has oracle-valid cases sits at 100% on
the scoreboard — quantified over the CORPUS, not over registrations, so
an unregistered type is a failure, not an escape. Zero pending examples
suite-wide.
