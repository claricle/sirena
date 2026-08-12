# 10 — Notation registry (two-level), fast-tracked

Can start: after 01. Blocks: 16, 12. The corpus tracks (06/07) run
CONCURRENTLY — no dependency — with one coordination rule: this
refactor lands as a fast-tracked PR and burndown PRs rebase onto it.
(Landing it while the pass set is small is cheaper; that's why it's
fast-tracked, not why others wait.)

## Problem

- `DiagramRegistry` is a flat Mermaid-type map; `lib/sirena.rb` is ~330
  lines of copy-pasted require+register; detection is hardcoded in the
  engine. Issue #2 demands: adding a notation = adding a renderer.
- Latent bug to delete by name: `lib/sirena.rb:38` defines a stray
  top-level `def self.render` on `main`, referencing bare `Engine`
  (NameError if ever called).

## Design (settled)

Two-level registry: notation → notation plugin → (diagram type →
parser/transform/renderer). No flat tuple map; no type-switch inside a
renderer object. `Sirena::Notation::Mermaid` owns detection rules and
its type table; the engine holds no notation constants.

**IR boundary (settled, enforced here):** the per-type graph shapes
transforms emit are PRIVATE to each notation plugin — never public API,
never cross-notation, no notation branching in the engine. The typed-IR
phase (item 18 stub) replaces them later, designed from Mermaid AND
PlantUML evidence.

## Do

1. Build the notation layer; collapse the registration blob; delete the
   stray `self.render`.
2. Engine flow: `notation:` option or sniffing → notation detects type →
   pipeline. Public Ruby API backward compatible.
3. CLI: pass the file path/extension hint through (`render.rb` sends
   source only today; `batch` globs `*.mmd` only) — extend both, with
   new specs (render/batch currently have none).
4. Pure refactor gate: corpus-pass set byte-identical before/after
   (whatever the scoreboard says it is on the day — not a hardcoded 604).
5. OCP proof: a spec-only fake notation registers through the public
   path, participates in sniffing, renders — touching zero lib files.

## Done when

Fake-notation spec passes; `lib/sirena.rb` ≤ 40 lines; scoreboard
unchanged; CLI extended with specs.

## Files

`lib/sirena/notation{,/mermaid}.rb`, `lib/sirena.rb`,
`lib/sirena/engine.rb`, `lib/sirena/diagram_registry.rb`,
`lib/sirena/commands/{render,batch}.rb`, `spec/sirena/notation_spec.rb`.
