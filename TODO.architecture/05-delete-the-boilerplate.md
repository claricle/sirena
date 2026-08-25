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
- **Three parse-error formats.** Group 1 raises `"Syntax error at
  <pos>: ..."`. Treemap raises `"Treemap parse error: ..."`. Group 2
  raises the good one — line number, column, the offending source line,
  and a caret under the column.

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

### Done when

- [ ] no parser contains the boilerplate `parse` body; 13 files are gone
      or reduced to a two-line declaration
- [ ] one parse-error format for all 24 types, asserted by a spec that
      feeds each type deliberately broken source and checks the message
      names a line and a column
- [ ] one builder calling convention
- [ ] `rake corpus:check` unchanged

---

## B — Nine copies of document creation (PR 2)

### Why

`create_document_from_layout` is defined in nine renderers in three
variants:

- `|| 800` defaults — `block`, `architecture`, `requirement`
- padding-40 with `@offset_x` / `@offset_y` instance-variable side
  effects — `kanban`, `mindmap`, `git_graph`
- no padding — `packet`, `radar`, `xy_chart`

Plus six more bespoke `create_document_for_<type>` methods.

### Steps

1. With `Layout::Scene` carrying `width` and `height` (item 04), replace
   all of them with one method on `Renderer::Base` taking a padding
   argument.
2. Replace the `@offset_x` / `@offset_y` side effect with an explicit
   translate on the root `<g>`. Hidden instance-variable state set by a
   document-creation method is the kind of thing that breaks silently
   when someone reorders two calls.

### Done when

- [ ] one `create_document` on `Renderer::Base`, no per-renderer copies
- [ ] no renderer sets `@offset_x` / `@offset_y`
- [ ] `rake corpus:check` unchanged

---

## C — Themes that are bypassed (PR 3)

### Why

Hardcoded hex colours per renderer: `c4` 25, `xy_chart` 21,
`class_diagram` 18, `quadrant` 17, `sequence` 17, `pie` 15, `radar` 15,
`gantt` 15. Five renderers define a private `DEFAULT_COLORS` palette
(`pie`, `sankey`, `radar`, `timeline`, `xy_chart`).

The theme system exists — `Theme::Registry`, four built-in YAML themes,
a `--theme` CLI flag — and is structurally unused, because
`Renderer::Base#theme_color` rescues `NoMethodError` and returns `nil`.
So every call site reads `theme_color(:x) || '#hardcoded'`, and the
hardcoded fallback is what renders.

### Steps

1. Add `theme.palette(index)` — one categorical palette, on the theme.
2. Delete the five private `DEFAULT_COLORS` constants.
3. Replace `theme_color(:x) || '#hex'` with `theme_color(:x)`, and make
   the theme guarantee a value. A missing key is a bug in the theme
   YAML: it should fail a spec, not silently fall back at runtime.
4. Add a spec that renders one diagram of every type under all four
   built-in themes and asserts `default` and `dark` output differ. That
   is the test that would have caught this.

### Done when

- [ ] no `DEFAULT_COLORS` in `lib/sirena/renderer/`
- [ ] `grep -c '#[0-9a-fA-F]\{6\}' lib/sirena/renderer/*.rb` near zero
- [ ] switching themes visibly changes output for every registered type
- [ ] `rake corpus:check` unchanged — colour does not affect pass/fail

### Do not

- Do not redesign the theme schema or add new theme keys beyond
  `palette`. The four built-in YAML themes stay as they are.
- Do not pick "nicer" colours. Move the existing ones into the theme
  unchanged; a colour change is a separate, visible decision.

## Files

`lib/sirena/parser/*.rb`, `lib/sirena/renderer/*.rb`,
`lib/sirena/theme.rb`, `lib/sirena/theme/color_palette.rb`,
`spec/sirena/theme_spec.rb`.
