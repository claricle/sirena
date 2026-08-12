# 18 — Typed IR (stub for the next phase)

Design-only in this phase. Not scheduled. Exists so the boundary item
10 enforces has a named owner instead of a hand-wave.

## Decision already settled

The typed intermediate representation is deliberately NOT built in this
phase. Reason: an IR designed from Mermaid alone encodes Mermaid's
assumptions; it gets designed AFTER PlantUML ships, from two notations'
demonstrated commonality. It is the first entry of the `TODO.notations`
roadmap (item 12's close-out), landing before DOT.

## What this phase must preserve for it

- Item 10's boundary: transform output shapes stay private per notation
  plugin; engine holds no notation knowledge.
- Item 14's contract notes: what each transform actually emits vs what
  elkrb accepts — that survey IS the IR's raw material.
- Item 16/12's PlantUML shapes: kept private, documented, expected to
  migrate.

## Done when (this phase)

The boundary held: no cross-notation shape sharing, no engine
notation-branching — asserted by item 10's specs. The IR design work
itself is out of scope here.
