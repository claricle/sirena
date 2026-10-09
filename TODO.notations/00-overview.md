# Sirena notation roadmap

This roadmap starts after the foundation phase closes. It carries the notation
list from [issue #2](https://github.com/claricle/sirena/issues/2) forward without
scheduling it inside the foundation plan.

The first implementation is **Graphviz / DOT**. The typed intermediate
representation is not a notation task and is not the first roadmap entry:
foundation item 18 must establish and prove that shared boundary before this
roadmap executes. PlantUML class and sequence remain owned by foundation item
12 rather than being repeated here.

## Fixed architecture contract

Sirena's core remains notation-neutral. A notation is added by registering its
renderer module, never by extending a central notation switch. Every renderer
follows the same path:

```text
source text -> notation parser -> typed IR -> elkrb layout -> SVG
```

Notation-specific syntax and semantics stop at the IR boundary. Layout geometry
is delegated to `claricle/elkrb`, and every emitted document must pass the
chosen `claricle/svg_conform` profile. Editing, notation-to-notation
round-tripping, and custom themes remain out of scope.

## Delivery order

Work through the tiers in order while allowing independent notation work to
proceed in parallel.

### Priority 1 — standards and publication pipelines

1. **Graphviz / DOT**
2. **D2**
3. **BPMN 2.0**
4. **C4 / Structurizr**
5. **BlockDiag family**
   - BlockDiag
   - SeqDiag
   - ActDiag
   - Nwdiag
   - RackDiag
   - PacketDiag

### Priority 2 — specialist but established

1. **TikZ** — assess and record whether a LaTeX bridge is required before
   implementation.
2. **WaveDrom**
3. **Syntrax**
4. **Excalidraw**
5. **draw.io / drawio** (`.drawio` XML)

### Priority 3 — when marginal cost is low

1. **Vega / Vega-Lite**
2. **PlantUMLMindMap**
3. **ER diagrams** — Barker and Crow's Foot notations

## Acceptance criteria for every notation

A notation is complete only when all five criteria are demonstrated:

1. Its parser accepts a representative corpus of real-world files.
2. Its rendered SVG is structurally valid under `svg_conform`.
3. Its layout matches the notation's reference renderer, modulo styling.
4. Its specs cover common syntax and at least one edge case.
5. Its README section contains a runnable example.

Each notation's implementation plan must identify the corpus and provenance,
pin the reference renderer used for parity, map its semantics into the shared
typed IR, and record evidence for all five criteria before completion.
