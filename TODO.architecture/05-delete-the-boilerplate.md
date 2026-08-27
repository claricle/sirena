# 05 — Delete the boilerplate

**Goal:** parse errors that name the line, column and offending source
for all 24 types; themes that actually work; about 1,500 fewer lines.
**Size:** 3 PRs, one per part. All three are deletions.
**Prerequisite:** part A and C after item 03; part B after item 04.

---

## A — Parsers that contain no per-type logic (PR 1)

### Why

Normalising each parser (strip comments, blanks and the type name) and
comparing puts the 24 parsers into four groups:

| Group | Count | Types | Shape |
|---|---|---|---|
| 1 | 9 | `c4`, `info`, `pie`, `quadrant`, `sequence`, `gantt`, `sankey`, `timeline`, `error` | identical 22 lines; the only difference across the group is single vs double quotes |
| 2 | 3 | `block`, `flowchart`, `requirement` | identical to each other, including a copy-pasted 20-line `format_parse_error` |
| 3 | 1 | `er_diagram` | group 1, at 19 lines |
| 4 | 11 | the rest | genuine per-type logic |

**13 of 24 parsers contain no per-type logic at all** — about 280 lines
whose only job is to name three classes.

Two inconsistencies come with them:

- **Two calling conventions for the same collaborator.** 21 parsers call
  `Builders::X.new.apply(tree)`; three call `Builders::X.apply(tree)` as
  a class method (`block`, `flowchart`, `requirement`). Both work; neither
  is documented; copying the wrong one gets you a `NoMethodError`.
- **Five parse-error formats across 21 raise sites.** Counted
  2026-08-25:

  | Format | Where |
  |---|---|
  | `Syntax error at <pos>: ...` | 15 parsers |
  | line, column, source line and a caret — the good one | `Parser::Base:60`, via a `format_parse_error` that six parsers each define their own copy of (`architecture`, `block`, `class_diagram`, `flowchart`, `requirement`, `state_diagram`) |
  | a bare `parse_failure_cause.ascii_tree` | `er_diagram.rb:36` |
  | `Parse error: <ascii_tree>` | `user_journey.rb:57` |
  | `Treemap parse error: <message>` | `treemap.rb:26` |

  `user_journey.rb:116` adds a sixth message — `Score must be between 1
  and 5` — which is a semantic error wearing `ParseError`, not a format.
  It needs its own class, not the shared formatter.

### Steps

1. Move the parse body into `Parser::Base` with a declarative API:

```ruby
class Parser::Pie < Base
  grammar Grammars::Pie
  builder Builders::Pie
end
```

2. **Adopt group 2's `format_parse_error` as the base implementation.**
   All 24 types then report line, column and source context instead of a
   raw Parslet position. This is a real improvement delivered by a
   deletion — call it out in the PR.
3. Settle on one builder calling convention (instance, `.new.apply`, is
   the majority) and make all 24 match.
4. Types with real per-type parse logic keep their `parse` override.
   After item 01 moved treemap's model building out, the remaining
   overrides are genuine.

---

## B — Nine copies of document creation (PR 2)

### Why

`create_document_from_layout` is defined in nine renderers in three
variants:

- `|| 800` defaults — `block`, `architecture`, `requirement`
- padding-40 with `@offset_x` / `@offset_y` instance-variable side
  effects — `kanban`, `mindmap`, `git_graph`
- no padding — `packet`, `radar`, `xy_chart`

Plus six more bespoke `create_document_for_<type>` methods, and one
override of plain `create_document` (`renderer/quadrant.rb:60`).

**16 per-renderer definitions**, measured 2026-08-27:
`grep -rn "def create_document" lib/sirena/renderer/` returns 17, one of
which is `Renderer::Base`'s own. An inventory that counts only the two
named shapes misses quadrant.

### Steps

1. With `Layout::Scene` carrying `width` and `height` (item 04), replace
   all of them with one method on `Renderer::Base` that reads those two
   values and nothing else. **No padding argument.** Scene coordinates
   are final and `width`/`height` already include the framing
   (`04-typed-scene.md`), so a renderer that adds padding is adding it
   twice.
2. Delete the `@offset_x` / `@offset_y` side effect outright. **Do not
   replace it with a translate on the root `<g>`** — item 04's gate
   forbids an SVG `translate` for exactly this reason: it moves the
   displacement back out of the Scene while every grep still passes.
   The layout has already shifted every point; the renderer emits them
   as they are.

---

## C — Themes that are bypassed (PR 3)

### Why

Hardcoded hex colours per renderer, counted 2026-08-25: `c4` 25,
`sequence` 21, `xy_chart` 21, `class_diagram` 18, `quadrant` 17,
`pie` 15, `radar` 15, `gantt` 15. (`sequence` was 17 when this plan was
first written; three arrow commits on main since then added four. The
number drifts — re-count, do not cite.)

Five renderers define a private palette constant, **under three
different names**: `DEFAULT_COLORS` in `pie`, `radar` and `xy_chart`,
`FLOW_COLORS` in `sankey`, `SECTION_COLORS` in `timeline`. Grepping for
`DEFAULT_COLORS` finds three of the five and leaves two behind.

The theme system exists — `Theme::Registry`, four built-in YAML themes,
a `--theme` CLI flag — and is structurally unused, because
`Renderer::Base#theme_color` rescues `NoMethodError` and returns `nil`.
So every call site reads `theme_color(:x) || '#hardcoded'`, and the
hardcoded fallback is what renders.

### Steps

1. Add `theme.palette(index)` — one categorical palette, on the theme.
2. Delete all five private palette constants — `DEFAULT_COLORS`,
   `FLOW_COLORS` and `SECTION_COLORS`.
3. Replace `theme_color(:x) || '#hex'` with `theme_color(:x)`, and make
   the theme guarantee a value. A missing key is a bug in the theme
   YAML: it should fail a spec, not silently fall back at runtime.
4. Add a spec that renders one diagram of every type under all four
   built-in themes and asserts `default` and `dark` output differ. That
   is the test that would have caught this.

### Do not

- Do not redesign the theme schema or add new theme keys beyond
  `palette`. The four built-in YAML themes stay as they are.
- Do not pick "nicer" colours. Move the existing ones into the theme
  unchanged; a colour change is a separate, visible decision.

## Files

`lib/sirena/parser/*.rb`, `lib/sirena/renderer/*.rb`,
`lib/sirena/theme.rb`, `lib/sirena/theme/color_palette.rb`,
`spec/sirena/theme_spec.rb`.

---

All three parts' criteria are one list below. The plan scorer reads the
first `## Done when` in a file and stops at the next `##`, so per-part
headings silently drop everything after the first block.

## Done when

- [ ] A — no parser contains the boilerplate `parse` body; 13 files are gone or reduced to a two-line declaration
- [ ] A — one parse-error format for all 24 types, asserted by a spec that feeds each type deliberately broken source and checks the message names a line and a column
- [ ] A — `grep -rn "def format_parse_error" lib/` returns one hit, in `Parser::Base`
- [ ] A — `user_journey`'s score check raises something other than `ParseError`
- [ ] A — one builder calling convention
- [ ] B — one `create_document` on `Renderer::Base`, no per-renderer copies
- [ ] B — no renderer sets `@offset_x` / `@offset_y`
- [ ] C — `grep -rn "DEFAULT_COLORS\|FLOW_COLORS\|SECTION_COLORS" lib/sirena/renderer/` returns nothing
- [ ] C — `grep -c '#[0-9a-fA-F]\{6\}' lib/sirena/renderer/*.rb` near zero
- [ ] C — switching themes visibly changes output for every registered type
- [ ] `rake corpus:check` unchanged after every one of the three PRs — colour does not affect pass/fail either
