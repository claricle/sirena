# 16 — PlantUML class spike (the weekend surprise)

Can start: after 10. The IMPLEMENTATION is small by design — a thin
vertical slice, not a small dependency list. **Completion also needs
04** (its cases must be valid under the chosen profile) **and item 14's
comparator** (structural invariants have to be measurable before they
can hold), so the spike lands its code early and closes later.
Blocks: 12 (informs it).

## Purpose

Two jobs in one thin slice:
1. Prove the notation registry with a REAL second notation, not a fake —
   the abstraction is only honest once something non-Mermaid ships
   through it.
2. Be the weekend demo: `sirena render diagram.puml` producing a clean
   class diagram is the "PlantUML is real" moment for the issue author.

## Scope — deliberately minimal

- `@startuml`/`@enduml` detection, `.puml` extension.
- Class diagrams only. The supported subset is ENUMERATED in the spike's
  spec file (committed list, reviewed like code — not implementer's
  choice at coding time): class declarations, attribute/method
  compartments with visibility markers, extends/implements arrows,
  association/aggregation/composition arrows, relation labels,
  multiplicities.
- Anything outside the enumerated subset fails with a CLEAR "not yet
  supported" error — never a partial render.
- Reference comparison: side-by-side with pinned PlantUML on a case set
  committed under `spec/plantuml_spike/` (15–20 cases covering every
  enumerated construct — coverage of the list is the selection rule,
  not hand-picking); structural invariants must hold on all.
- **Where those references come from.** Item 12 owns CI provisioning of
  PlantUML/Java/Graphviz, and 12 cannot start until this spike is done —
  so the spike's references are generated LOCALLY against a pinned
  PlantUML and committed. That is accepted deliberately, with one
  condition: every reference records its PlantUML, Java and Graphviz
  versions plus a content hash, so item 12 can re-verify them the moment
  its lane exists. Unprovenanced local references would rot in silence.

## Explicitly NOT here

Sequence diagrams, full grammar coverage, corpus extraction, CI
provisioning — all item 12. The spike's corpus IS its 15–20 cases.

## Done when

- The spike renders its case set, valid under item 04's profile.
- Registered purely through the item-10 public path (zero engine edits —
  the real OCP proof).
- A demo-able README example, executed by a spec THIS item ships (item
  11's snippet framework absorbs it later — no dependency on 11).

## Files

`lib/sirena/notation/plantuml/**` (new), `spec/plantuml_spike_spec.rb`,
`spec/plantuml_spike/` (the committed case set + its provenance records).
Item 12 absorbs both into `spec/plantuml/`.
