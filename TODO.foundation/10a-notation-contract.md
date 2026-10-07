# 10a — Notation contract

Status: approved (Reading A). 10b lands in two PRs. Part 1 moves Mermaid detection,
parsing and the type table into `Notation::Mermaid`; `Engine` still calls it directly.
Part 2 adds `Notation.register`/`resolve`, the `notation:` option, the CLI and the
section 8 gates. A second notation needs part 2. 10b blocks 16, 12, 18.
Measured against `origin/main` at `df0c8c05`, ruby 3.4.8, macOS. Every `file:line` below
was read off that tree; every probe line is a command that was run.

Tags: **[B-removes]** marks a row or section that exists only because of a multi-notation
registry and disappears under Reading B (section 0). **[B-keeps]** marks what survives.
Section 10 lists the surviving rows exactly; anything not listed there is [B-removes].

## 0. The one question

`TODO.architecture/06-registry-as-data.md:224-233` ("Do not") and
`TODO.architecture/DO-NOT-BUILD.md:14-27` say: do not build a notation plugin system,
a two-level registry, a RubyGems discovery hook or a directory loader; a
`Notation::Mermaid` module with its own `TYPES` table is "the whole seam required".
`TODO.architecture/MAPPING.md:40` maps card 10 onto architecture 06 for that reason.
DO-NOT-BUILD's trigger is "the PlantUML PR, expected within months".

Card 10 (`TODO.foundation/10-notation-registry.md`) requires the opposite: two-level
registry, an external discovery mechanism, and a cold-subprocess proof. It ranks first
in `~/claricle/status/reports/sirena-task-priorities.md` (PlantUML first, ruling
2026-10-05), which is the trigger DO-NOT-BUILD named.

This contract assumes **card 10 supersedes architecture 06 and DO-NOT-BUILD for the
notation seam**. If the owner instead wants architecture 06's smaller seam, everything not listed in
section 10 is deleted and 10b shrinks to what section 10 names.

Approving this document approves that assumption.

## 1. Corrections to card 10 (code wins over the card)  [B-keeps]

1. The stray `def self.render` is at `lib/sirena.rb:36`, not `:38`, and it is **not**
   a latent NameError. It sits inside `module Sirena`, so bare `Engine` resolves
   lexically. Probe:
   `bundle exec ruby -Ilib -e 'require "sirena"; puts Sirena.render("graph TD\nA-->B")[0,60]'`
   printed `<svg`. `Sirena.method(:render).source_location` is `lib/sirena.rb:36`.
   It is documented public API ("Convenience method", `lib/sirena.rb:30-38`) with 102
   references (`git grep -n "Sirena\.render\b" | wc -l`), including
   `lib/sirena/commands/batch.rb:97`. **Contract: keep `Sirena.render`; do not delete
   it.** `TODO.architecture/06` agrees ("one `def self.render`, inside `module Sirena`").
2. "`render` and `batch` have NO coverage at all" is false: `spec/sirena/commands/render_spec.rb`
   (200 lines), `spec/sirena/commands/batch_spec.rb` (289 lines), and
   `spec/sirena/cli_spec.rb` describe blocks for render (`:40`), batch (`:130`),
   version (`:161`), types (`:169`), help (`:187`). 10b extends them; it does not write
   them from scratch.
3. Stale cites: `lib/sirena.rb` is 369 lines, not ~330, with 24 `DiagramRegistry.register`
   blocks (`grep -c "DiagramRegistry.register" lib/sirena.rb`). The registry consumer in
   `types` is `commands/types.rb:23`, not `:19`. The `cli_spec.rb:15` cite points at
   nothing relevant.
4. The conflict in section 0.
5. "Blocks 16, 12" is confirmed by card text (16: "after 10"; 18: "after 10").

## 2. Decisions

Each row is one choice. "Anchor" is where today's behavior lives.

| # | Question | Choice | Anchor / probe |
|---|---|---|---|
| D1 | Where `notation:` lives [B-removes] | **Both**: `Engine.new(notation:)` is the default, `Engine#render(src, notation:)` overrides it. `path:` is a **render-only** option (it is per document). `Sirena.render(src, notation: :x, path: "a.puml")` works because it forwards its options hash. | `engine.rb:155` (ctor kwargs), `:189-198` (render options: `:verbose`, `:theme`, `:today`), `lib/sirena.rb:36`. Today `Engine.new(notation: :x)` raises `ArgumentError: unknown keyword: :notation` and `render(path: "x.puml")` is silently ignored (probe `p1.rb`, run). |
| D2 | Identifier [B-removes] | A lowercase **Symbol** matching `/\A[a-z][a-z0-9_]*\z/` (`:mermaid`, `:plantuml`). Parameters accept a Symbol or a String (String goes through `to_sym`, no case folding). A class or instance is **not** accepted: any value that is not a Symbol or String raises `Engine::PipelineError` `Invalid notation: <inspect>. Notation must be a Symbol or String`; a String or Symbol failing the pattern raises the D5 unknown-notation error. Today `Object.new.to_sym` raises an incidental `NoMethodError` (probe, run), which is not the contract. | n/a, new |
| D3 | Precedence [B-removes] | `notation:` explicit, then path-extension hint, then content sniff, then **default `:mermaid`**. The first signal that yields a notation wins; later signals never override. | see below |
| D4 | Mismatch (explicit or hint selects a notation that cannot read the source) [B-removes] | The selected notation's `parse` raises `Engine::DiagramTypeError`. The engine does **not** pre-check `claims?`. Every notation's message must begin exactly `Unable to detect diagram type from source.` and then name its own headers (`Source must start with one of: ...`). | `DiagramTypeError < Sirena::Error`, `lib/sirena/error/diagram_type_error.rb:8`; raised at `engine.rb:270-278`. |
| D5 | Unknown notation [B-removes] | `Engine::PipelineError`, message `Unknown notation: <given>. Valid notations: <ids sorted, joined ", ">`. Raised at `Engine.new(notation:)` **and** at `render(notation:)`. `nil` means "not given". | Mirrors theme: `engine.rb:434-439`. Probe: `Engine.new(theme: "nope")` raised `PipelineError: "Unknown theme: nope. Valid themes: dark, default, high_contrast, light"`. |
| D6 | Stdin [B-removes] | No path exists, so only explicit, then sniff, then default apply. `render -` and `render` with no FILE pass no `path:`. `--notation` can force. | `commands/render.rb:56-65`. |
| D7 | External discovery | **"The consumer requires it."** See section 3. [B-removes] | |
| D8 | Plugin interface | Five methods, validated at `register`. See section 4. [B-removes] | |
| D9 | Plug points for 12/16/18 | See section 7. [B-removes] | |
| D10 | CLI | See section 6. [B-removes] | |
| D11 | `DiagramRegistry`, `DIAGRAM_TYPE_PATTERNS`, `Sirena.render` [B-keeps] | `Sirena.render` kept. `DiagramRegistry` stays for one release as a thin facade over `Notation::Mermaid`'s type table. `Engine::DIAGRAM_TYPE_PATTERNS` and `DIAGRAM_TYPE_KEYWORDS` stay as deprecated aliases to the same table. `lib/sirena.rb` is at most 40 lines. | Specs that use them: `spec/contract_spec.rb` (parity spec near `:28`), `spec/sirena/engine_spec.rb`, `spec/sirena/engine_invalid_utf8_spec.rb`, `spec/sirena/svg/registry_spec.rb`, six `spec/integration/*`, `scripts/diagram_fuzz_report.rb`, `commands/types.rb:23` (found with `git grep -ln "DiagramRegistry\|DIAGRAM_TYPE_PATTERNS" -- spec scripts lib tasks`). `scripts/extract_mermaid_tests.rb` is NOT a consumer: it defines its own `DIAGRAM_TYPES` (`:17`) and never references the registry; it is a parallel inventory for card 02 step 6 to fold in. 10b does not delete the facade. |
| D12 | Canonical type-name table (card 02 step 6) [B-keeps] | The single canonical table is `Notation::Mermaid`'s type table. Card 02 consumes it; card 10 lands first per the priorities report. | |
| D13 | 10b gates | See section 8; each gate is tagged. | |

### D3 details [B-removes]

- **Default exists for back-compat.** Every source Sirena handled before this change,
  and every error it raised, must stay Mermaid's own and byte-identical. Probes
  (current behavior, to be preserved):
  - `printf 'hello' | bundle exec exe/sirena render; echo $?` printed
    `Error: Unable to detect diagram type from source. Source must start with one of: architecture-beta, block-beta, C4Context, ... xychart-beta` and `rc=1`.
  - `Sirena.render("\xff\xfe graph TD".b)` raised `Engine::DiagramTypeError` with the same sentence.
- **Sniff** iterates registered notations in **registration order**; the first whose
  `claims?(source)` is true wins. Built-ins register first, so no later notation can
  steal a source Mermaid claims.
- **Unknown extension** (`.txt`, none) is "no hint". It falls through. It is not an error.
- **Ambiguity is rejected at registration, not at run time.** An extension claimed by
  two notations raises `Sirena::NotationRegistrationError < Sirena::Error` from
  `Notation.register`. A duplicate id raises the same.
- **Mermaid's own table order is not exercised by the corpus.** Probe over
  `spec/mermaid/**/*.mmd` (1997 files, `p3.rb`, run): 0 sources match more than one of
  the 24 `DIAGRAM_TYPE_PATTERNS`; 64 match none (those raise `DiagramTypeError`).
  Order stays stable anyway; it is first-match-wins at `engine.rb:41-66`.
- **Extension matching is case-insensitive** (`File.extname(path.to_s).downcase`).
  Probe, `batch` over a dir containing `a.mmd b.mermaid C.MMD` on macOS (case-insensitive
  filesystem): only `a.mmd` and `C.MMD` were rendered, and the output was `a.svg` and
  **`C.MMD`** (an SVG body in a file still named `.MMD`, because
  `batch.rb:89` renames with the case-sensitive `/\.mmd$/`). On a case-sensitive
  filesystem `C.MMD` would not be globbed at all (`batch.rb:68`). 10b fixes both: batch
  becomes case-insensitive on every platform and `C.MMD` becomes `C.svg`. This is one of
  the deliberate output changes in section 6.1. [B-removes]

## 3. Discovery (D7) [B-removes]

An external notation is any file that, when loaded, calls
`Sirena::Notation.register(plugin)`. Nothing else is required.

- Library use: `require "sirena"; require "my_notation"`.
- CLI use: `--require FEATURE_OR_PATH` / `-r` (repeatable) on `render`, `batch`, `types`.
  Processed first, before notation resolution and before `batch` globbing. A
  `LoadError` becomes `Error: Cannot load notation: <arg>` and exit 1. Trust is the
  same as `ruby -r`. Ruby's own `-r` and `RUBYOPT=-r...` also work, because
  registration happens at `require` time.
- Built-in notations load through one internal manifest, `lib/sirena/notation/builtin.rb`,
  required once from `lib/sirena.rb` (target at most 40 lines). That file is **not**
  contract; it may change without a breaking release.

Rejected, with reasons:

- **RubyGems plugin hook.** `Gem.load_plugins` (`rubygems.rb:1126`) and
  `Gem.load_env_plugins` (`:1135`) exist, but their only caller is
  `rubygems/gem_runner.rb:37,41`, i.e. the `gem` command. Probe:
  `grep -n "load_plugins\|load_env_plugins" rubygems/*.rb rubygems/commands/*.rb` found
  only `gem_runner.rb`. A `rubygems_plugin.rb` is therefore never loaded by
  `exe/sirena`, and making it load would mean Sirena calling `Gem.load_env_plugins`,
  which executes every installed gem's `rubygems_plugin.rb` on every run.
- **Directory loader** (`.sirena/` or an env path). It executes code from the working
  directory on every `sirena` run, in whatever directory the user happens to be in. The
  project defines no `SIRENA_*` environment variables (repo `CLAUDE.md`, "CLI").

## 4. Plugin interface (D8) [B-removes, except the `Notation::Mermaid` paragraph]

A module or object. `Notation.register` validates every item and raises
`NotationRegistrationError` naming the missing or malformed one.

| Member | Contract |
|---|---|
| `id` | Symbol per D2. |
| `extensions` | Frozen Array of lowercase dotted Strings, may be empty (stdin and explicit only). Mermaid is `[".mmd"]` and nothing else; adding `.mermaid` would change batch's output set for no requirement, and is additive later. |
| `claims?(source)` | Pure. True or false. **Never raises for any String**, including ASCII-8BIT and invalid UTF-8: `commands/render.rb:56-65` reads raw bytes (`File.binread`, `$stdin.binmode.read`). Mermaid returns false on any `Source` refusal, so the default step lets Mermaid raise its own byte-identical error. |
| `parse(source)` | Returns `Notation::Parsed`, a frozen plain class with keyword-only `type`, `diagram`, `transform`, `renderer`. Raises `DiagramTypeError`, `Parser::ParseError` or `PipelineError` exactly as today. Owns preamble, type detection, the degenerate-preamble rules, and **applies the frontmatter title to the diagram** before returning (`apply_frontmatter_title`, `engine.rb:223`, moves into Mermaid's `parse`; the title is still read before detection so `title: [` is refused as today, `engine.rb:206-209`). |
| `types` | Array of Symbols, in display order, for the `types` command. |

Errors a notation raises must be `Sirena::Error` subclasses or the engine wraps them as
`PipelineError "Rendering failed: Class: msg"` (`engine.rb:233-260`).

`Notation::Mermaid` takes over what lives in `Engine` today and is Mermaid-specific
[B-keeps, see section 10; under Reading B the `parse` entry point below is replaced by
architecture 06's lookups]:
`DIAGRAM_TYPE_PATTERNS` (`engine.rb:41`), `DIAGRAM_TYPE_KEYWORDS` (`:76`),
`REFUSES_BARE_COMMENT` (`:106`), `REFUSED_PREAMBLE` (`:132`), `Source.split` /
`Source.title` use (`:204`, `:209`; `git grep "Source\.split\|Source\.title" -- lib`
shows only the engine), `detect_diagram_type` (`:270`) and `reject_degenerate_preamble`
(`:297`). The engine holds **no notation branching** and no notation constants beyond the two deprecated aliases D11 keeps.

Per-type tuple stays `{parser:, transform:, renderer:, model:}`, the same kwargs as
`DiagramRegistry.register` (`lib/sirena/diagram_registry.rb:30`). The slot is named
`transform:` although the classes are `Layout::*`; renaming is out of scope.

Example, a complete external notation (15 lines):

```ruby
module Fake
  extend self
  def id = :fake
  def extensions = %w[.fake].freeze
  def types = %i[fake_box]
  def claims?(src) = src.b.start_with?("@fake")
  def parse(src)
    raise Sirena::Engine::DiagramTypeError, "Unable to detect diagram type from source. Source must start with one of: @fake" unless claims?(src)
    Sirena::Notation::Parsed.new(type: :fake_box, diagram: src, transform: FakeLayout, renderer: FakeRenderer)
  end
end
Sirena::Notation.register(Fake)
```

## 5. Engine flow (pseudo-code) [B-removes]

```
render(source, options):
  theme/today/verbose resolved as today                (engine.rb:190-198)
  notation = Notation.resolve(explicit: options[:notation] || @notation,   # D5 raises on unknown
                              path:     options[:path],                    # D3 hint
                              source:   source)                            # D3 sniff, then DEFAULT
  parsed   = notation.parse(source)                    # D4: mismatch raises here
  graph    = transform_diagram(parsed.diagram, parsed.transform, today, theme)  # engine.rb:224 shape, unchanged
  graph    = layout_graph(graph)                       # Layout::Grid fallback, engine.rb:371-379
  svg      = render_svg(graph, parsed.renderer, theme) # engine.rb:388
  svg.to_xml
rescue Error then raise                                # engine.rb:233, new errors pass through
rescue StandardError => PipelineError "Rendering failed: ..."   # unchanged
```

Resolution order inside `Notation.resolve` is exactly D3. `Source.split` runs inside
Mermaid's `parse`, not in the engine.

## 6. CLI (D10) [B-removes]

Existing options today: `-o -f -t -v -i` (`cli.rb`). No `-n`, no `-r`.

- `render`: passes `path: file` unless the file is `-` or nil (`commands/render.rb:25-29`
  currently calls `engine.render(source)` with no path). New: `--notation NAME` (long
  only), `--require` / `-r` (repeatable). [B-removes]
- `batch`: globs every file whose downcased extension belongs to a registered notation
  (`Notation.for_extension`), or only the `--notation` notation's extensions when given.
  Output name: if the downcased extension of `relative` is a registered notation
  extension, replace it (case-insensitively) with `.svg`; **otherwise leave the name
  unchanged**. The second half keeps today's single-file behavior byte-identical:
  probe `batch -i one.txt -o o2` wrote `o2/one.txt` at `df0c8c05` (run), because
  `batch.rb:89` only rewrites `.mmd`. A blanket extension-swap would have written
  `one.svg`; that is rejected. `-i` accepting a single file (`batch.rb:66-72`) is
  therefore unchanged and takes the path hint from that file. It still calls `Sirena.render` per file (`batch.rb:97`). Exit code is
  unchanged: it is already `exit 1 unless command.success?` (`cli.rb:112`,
  `batch.rb:60`); the repo `CLAUDE.md` line saying batch exits 0 on failure is stale on
  this base. [B-removes]
- `types`: output today is `Supported diagram types:`, a blank line, then `  <type>`
  per type (probe: `exe/sirena types | head -6`). New: same header, blank line, then
  per notation a line `<id>:` followed by the unchanged `  <type>` lines, a blank line
  between groups. `cli_spec.rb:169-185` (asserts the header and every registered type
  name) stays green. Type names are **not** namespaced; `(notation, type)` is the
  identity and two notations may share a type symbol. [B-removes]
- Help text (`cli.rb:15`, `:77-88`) says "diagram", not "Mermaid diagram", and lists
  `--notation` and `--require`. [B-removes]
- Unknown notation on the CLI: the `PipelineError` of D5, printed as `Error: <msg>`,
  exit 1 (`cli.rb:140`, `:112`). [B-removes]

### 6.1 Every deliberate output change (the complete list)

Everything else must be byte-identical (section 8). Decision: these changes are
accepted and listed, and the gate is written around them; the alternative (keeping the
old `types` output and the case-sensitive rename) was rejected because it would leave
`types` blind to a second notation and leave `C.MMD` output misnamed.

1. `batch` globs and renames extensions case-insensitively on every platform:
   `C.MMD` becomes `C.svg` (today on macOS it is rendered into a file still named
   `C.MMD`; on a case-sensitive filesystem it is skipped). Unregistered extensions
   (single-file `-i one.txt`) keep today's name, `one.txt`.
2. `batch` also picks up files of any other registered notation's extensions. With only
   the built-in notation registered this adds nothing.
3. `types` stdout gains a `mermaid:` group line and a blank line between groups.
4. `render`/`batch` `--help` text changes (section 6, help bullet) and `--notation` /
   `--require` appear in it.
5. New error texts that cannot occur today: D5, D2 invalid identifier,
   `Cannot load notation: <arg>`, `NotationRegistrationError`.

## 7. Plug points for 12 / 16 / 18 (D9) [B-removes]

- **PlantUML (cards 12, 16):** `lib/sirena/notation/plantuml/**`, id `:plantuml`.
  Zero engine edits. Card 16 owns the extension list (the contract requires only
  lowercase, dotted, unique). `claims?` recognises `@startuml` after leading blank or
  `'` comment lines. `parse` raises `DiagramTypeError` / "not yet supported" naming the
  construct, per card 16's done criterion. Type inference inside `@startuml` is the
  plugin's business (a PlantUML class diagram has no keyword).
- **Typed IR (card 18):** the IR changes what `Parsed#transform` produces and what
  `layout_graph` / `render_svg` accept. It does **not** change the plugin interface.
  Each notation's parse output stays private. The boundary spec 10b writes asserts
  "no notation constants in the engine, no cross-notation model sharing"; card 18
  step 6 flips that to "IR shared, parse output private". Today's per-type transform
  shapes are interim and are not described as permanent anywhere in code or docs.

## 8. Gates 10b must restate

- **Pure refactor.** Before/after checksum manifest over the corpus-pass set from
  `scoreboard/corpus.json` (never a hardcoded count), each surface compared to itself:
  Ruby API bytes and error text; CLI stdout, stderr, exit code and the set of batch
  output file names and bytes. Only the section 6.1 changes may differ, and each is
  pinned by its own spec asserting the NEW exact output (`types` stdout, `--help`,
  `C.MMD` to `C.svg`, `one.txt` unchanged). Anything else differing fails the gate. [B-keeps,
  minus the 6.1 items, which are all [B-removes]]
- **Truth-table spec rows** [B-removes]: explicit/hint/sniff all three disagreeing; mismatch (D4);
  unknown notation at ctor and at render (D5); stdin with no path (D6); ambiguous claim
  resolved by registration order; duplicate id and duplicate extension raise;
  `claims?` never raises on binary or invalid UTF-8.
- **Plugin conformance spec** [B-removes]: each registered notation, given a source it cannot
  recognise, raises `DiagramTypeError` starting `Unable to detect diagram type from source.`
- **Fake-notation OCP spec** [B-removes] (spec-only, public path, touches zero `lib` files) renders.
- **Cold-subprocess spec** [B-removes]: `ruby exe/sirena render --require <fake.rb> x.fake`, no edit
  to `exe/sirena` or `lib/sirena.rb`.
- **Boundary spec** [B-keeps]: no notation constants in the engine. ("No notation branching" and "no cross-notation model sharing" are [B-removes]: with one notation there is nothing to branch between.)
- `lib/sirena.rb` at most 40 lines, with `Sirena.render` kept. Version not bumped. [B-keeps]
  `contract_spec.rb` parity is kept by iterating each notation's table. [B-keeps; under B the table is `Notation::Mermaid::TYPES`]

## 9. Explicitly out of scope

Parser/layout/renderer `.for` lookups and convention-based class resolution
(architecture 06); the typed IR (card 18); PlantUML grammar (cards 12/16); renaming the
`transform:` slot; adding `.mermaid` to
Mermaid's extensions. 10b must not contradict architecture 06's `Notation::Mermaid::TYPES`
single-table-per-notation shape or its fixtures-parity contract spec.

## 10. Reading B: exactly what survives

If the owner chooses Reading B, 10b delivers only:

1. `Notation::Mermaid` owns `DIAGRAM_TYPE_PATTERNS`, `DIAGRAM_TYPE_KEYWORDS`,
   `REFUSES_BARE_COMMENT`, `REFUSED_PREAMBLE`, `Source.split`/`Source.title` use,
   detection, and the degenerate-preamble rule (section 4, second paragraph), plus its
   one type table (`TYPES` per architecture 06). The engine holds no notation constants.
   The entry point is architecture 06's lookup, not `Notation::Parsed`.
2. D11: `Sirena.render` kept; `DiagramRegistry` facade and constant aliases for one
   release; `lib/sirena.rb` at most 40 lines.
3. D12: that table is the canonical type-name table for card 02.
4. Section 8: the pure-refactor gate (with no 6.1 items), the boundary spec's
   "no notation constants in the engine" half, the `lib/sirena.rb` and version lines.
5. Section 1 corrections (all of them) and section 9.

Removed under B: D1-D6, D7-D10 and sections 2 (D3 details), 3, 4 (interface table and
example), 5, 6, 6.1, 7, and the truth-table, plugin-conformance, fake-notation,
cold-subprocess gates. The CLI is then untouched, so `types`, `--help`, and `batch`
output stay byte-identical.
