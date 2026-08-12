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
| 07f finishing: mindmap, requirement, timeline, pie, packet, quadrant, sankey, xychart, info, error | small | 86–100% |

07f also owns: the suite's only pending example
(`spec/sirena/parser/packet_spec.rb:74` xit — implement or delete with
justification; zero pending after) and closing every 90%+ type to 100%
of oracle-valid.

## Done when

Every canonical corpus type that has oracle-valid cases sits at 100% on
the scoreboard — quantified over the CORPUS, not over registrations, so
an unregistered type is a failure, not an escape. Zero pending examples
suite-wide.
