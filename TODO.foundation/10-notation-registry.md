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

## Design (shape settled; the API contract below is not)

Two-level registry: notation → notation plugin → (diagram type →
parser/transform/renderer). No flat tuple map; no type-switch inside a
renderer object. `Sirena::Notation::Mermaid` owns detection rules and
its type table; the engine holds no notation constants.

**IR boundary (settled, enforced here):** the per-type graph shapes
transforms emit are PRIVATE to each notation plugin — never public API,
never cross-notation, no notation branching in the engine. The typed-IR
phase (item 18 stub) replaces them later, designed from Mermaid AND
PlantUML evidence.

## API contract (settle before implementing)

The plan cannot leave these to the implementer — each one is a public
behavior nobody can change later without a breaking release:

- Where `notation:` lives: `Engine.new`, `render`, or both.
- What a notation identifier is: symbol, string, or class.
- Precedence when signals disagree: explicit `notation:` → path/extension
  hint → content sniffing. First match wins; later signals never
  override an earlier one.
- What happens on mismatch (explicit `notation: :plantuml`, Mermaid
  source) and on an unknown notation — which error class, which message.
- Stdin: no path hint exists, so sniffing is the only signal.
- **Discovery**: today every implementation is loaded by an explicit
  `require_relative` in `lib/sirena.rb:42`. Ruby will not find a
  newly-shipped notation gem on its own. Pick one — built-in manifest,
  directory loader, RubyGems plugin hook, or "the consumer requires it"
  — and write it down.

## Do

1. Build the notation layer; collapse the registration blob; delete the
   stray `self.render`.
2. Engine flow per the contract above. Public Ruby API backward
   compatible.
3. CLI, all of it — not just the render path:
   - `commands/render.rb` sends source only today; pass the path hint.
   - `commands/batch.rb` globs `*.mmd` only; extend to registered
     notation extensions.
   - `commands/types.rb:19` consumes the flat registry directly; decide
     whether output groups by notation or namespaces the type names.
   - `cli.rb:15` help text advertises Mermaid-only render and
     `.mmd`-only batch; update it.
   - Specs: `render` and `batch` have NO coverage at all and need it
     from scratch; `types` and `help` already have behavioral specs
     (`spec/sirena/cli_spec.rb:15`) that need extending for the
     multi-notation output.
4. Coordinate the canonical type-name table with item 02 step 6 — 02
   publishes it, 10 relocates the registry that holds it. Settle the
   location once, in whichever lands first.
5. Pure refactor gate: corpus-pass set byte-identical before/after
   (whatever the scoreboard says it is on the day — never a hardcoded
   count).
6. OCP proof: a spec-only fake notation registers through the public
   path, participates in sniffing, renders — touching zero lib files.

## Done when

Fake-notation spec passes; a boundary spec asserts no cross-notation
model sharing and no notation branching in the engine (the assertion
item 18 relies on); a **cold-subprocess CLI spec** renders a fake
external notation without editing central boot code, proving the
discovery mechanism actually works out of process; `lib/sirena.rb` ≤ 40
lines; scoreboard unchanged; CLI extended with specs.

## Files

`lib/sirena/notation{,/mermaid}.rb`, `lib/sirena.rb`,
`lib/sirena/engine.rb`, `lib/sirena/diagram_registry.rb`,
`lib/sirena/cli.rb`, `lib/sirena/commands/{render,batch,types}.rb`,
`spec/sirena/notation_spec.rb`.
