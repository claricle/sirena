# 07 — Corpus burndown: class and all remaining types

Can start: after 02. Same target, method, and parallelism rules as item
06 — including the serialized shared-grammar track for anything touching
`grammars/common.rb`. Completion also needs 03a. Shares two
second-finisher floor raises: 70 → 80 with item 06, and 80 → 90 with
item 14 (see Done).
The plan-wide "every type at 100%" claim additionally needs 05 and 06 —
see Done.

## Sub-tracks (parallel; ordered by total cases)

Counts measured 2026-08-11 by `ls spec/mermaid/<type>/*.mmd`.

| Sub-todo | Cases | Today |
|---|---|---|
| 07a class (+class_diagram) | 465 | ~27% — the largest single type by case count |
| 07b sequence | 126 | 48% |
| 07c git (+gitgraph) | 168 | 66% |
| 07d gantt, radar, kanban, user_journey | 144 | 24–39% |
| 07e architecture, c4, block | 92 | 31–60% |
| 07f finishing: mindmap, requirement, timeline, pie, packet, quadrant, sankey, xychart, info, error | 181 | 92–100% |

Item 07 owns 1,176 cases; item 06 owns 736; item 05's `unknown/` holds
85. 1,176 + 736 + 85 = 1,997, the whole corpus — every case has an
owner, and the arithmetic is checkable.

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

Every sub-track records its singleton-capture grep audit result,
including an explicit "zero hits" where that is the answer — an audit
with no artifact is indistinguishable from one nobody ran.

Every canonical corpus type that has oracle-valid cases sits at 100% on
the scoreboard — quantified over the CORPUS, not over registrations, so
an unregistered type is a failure, not an escape. Zero pending examples
suite-wide.

Floor raises are acceptance criteria of this item, not side effects.
Both are second-finisher rules, because the tracks run concurrently:
70 → 80 fires when the last of item 06 and 07a/07b/07c completes, and
80 → 90 when the later of item 07 and item 14 completes. The first
finisher records the handoff in its PR body and closes; the second
performs the raise.

This item OWNS the types in 07a–07f. The all-types statement above can
only be evaluated once item 06 has closed flowchart/state/er/treemap and
item 05 has cleared the `unknown/` detection cases — so 07's own gate is
its enumerated types, and the plan-wide "every type at 100%" claim
closes when 05, 06 and 07 are all done. Record that as completion edges
05 → 07 and 06 → 07; it does not delay 07's parallel start.
