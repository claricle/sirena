# 14 — elkrb integration + layout parity

Comparator DESIGN can start after 02b's reference regeneration (step 7)
— the design needs to know what a reference looks like, and the
references are being rebuilt. INTEGRATION and Done need **both 01 and
02**: step 1 proves elkrb works functionally under lutaml-model 0.8, and
that cannot run while the gem still crashes at require. Completion also
needs 03a and 21 (the `label-text` rule is part of the hard gate, and 21
removes the class and ER failures it reports), and raises the branch floor
80 → 90 jointly with item 07.
Blocks: 12; with item 04, blocks 16's completion; its emit/accept survey
blocks item 18's start, and its rollout — the per-type migration in step 2,
once every layout actually goes through elkrb — blocks item 18's
completion.

## Facts

`Engine#layout_graph` never calls elkrb — fallback grid
(`lib/sirena/engine.rb:160-168`, `Engine#layout_graph` calling `Layout::Grid.apply`, a
class its own header calls temporary) — while README.adoc, ARCHITECTURE.md,
and parts of `docs/` still claim ELK layout.
elkrb 1.0.2 resolves and requires cleanly under lutaml-model 0.8
(proven 2026-08-11). Its functional behavior under 0.8.95 is measured in
`docs/emit-accept-survey.md`: it lays out the seven ELK-shaped types, with the
gaps listed there; step 1 builds on that.
References for parity: the deduped `spec/fixtures_mermaid/` set
(~847 unique SVGs; item 02 dedupes). Layouts emit heterogeneous
shapes — flowchart is ELK-ish, block/quadrant are pre-positioned — so
"elkrb for all types" is per-type work, not one engine edit.

## Bars (user-ruled)

- Structural invariants: **hard gate** — all nodes present, all edges
  connecting the right nodes, no PEER overlaps, labels attached to
  owners and carrying the reference's text.
  ("No overlaps" unqualified would reject correct output;
  ancestor containment is legitimate — see the metric contract below.)
- Geometry: per-case scoreboard ratchet; **8% node-center / 15%
  dimension-aspect are the targets**. Renegotiation happens **per type
  only** (never per case — case-level waivers would hollow the target):
  measured evidence that algorithm identity, not our code, makes the
  number unreachable; the user decides. Bars raise later once stable.

## Metric contract (settled; the comparator is written against this)

The bars above are measured as follows. A change to any entry is a change to
the bar and goes to the owner, per type and with evidence.

**Frame.** The oracle is SVG-only, so the comparator compares SVG to SVG. The
reference (mmdc output) and the Sirena render are parsed by the SAME extractor
into a figure: a list of elements `{kind, key, parent, bbox, label}`. Every
number below is in root `viewBox` user units. The reference engine is dagre (12
of 1,997 corpus sources request `layout: elk`, all under `spec/mermaid/unknown`),
so the 8%/15% targets against elkrb's layered algorithm may need the per-type
renegotiation the bars already allow.

### 1. Node identity

Match by `(kind, parent, key)`. `parent` is the key of the matched container
(none at the root). `key` is the id the author wrote only where BOTH SVGs
expose that id; otherwise both sides use label text (whitespace collapsed,
tags stripped, entities decoded) or a per-type role/ordinal below. This keeps
a Sirena-only id from being compared with a reference label.

Reference ids, measured in `spec/fixtures_mermaid` (directory names, which are
not the registry names: `class`, `er`, `state`, `gitgraph`):

| Type | Reference id grammar | Key |
|---|---|---|
| flowchart | nodes `flowchart-<id>-<n>`, edges `L_<src>_<dst>_<n>`, clusters the raw id (`g.cluster id=A`; Sirena: `cluster-A`) | `<id>` |
| class | `classId-<name>-<n>` | `<name>` |
| er | `entity-<name>-<n>` | `<name>` |
| state | leaf nodes `state-<id>-<n>`; composite containers use the raw id; terminals are `state-<scope>_start-<n>` and `state-<scope>_end-<n>` in the reference, where `<scope>` is `root` or the composite's id (Sirena: `state-start_<n>`, `state-end_<n>`); they are recognised by the `_start-` or `_end-` id forms on the reference side and the `state-start_<n>` or `state-end_<n>` forms on the Sirena side, tried before the leaf grammar, because only reference start terminals carry a `state-start` class and Sirena's terminals carry none; Sirena draws a `[*]` text inside the terminal and the reference does not, so that text is not part of the compared element | `<id>`; terminals have kind `terminal-start` or `terminal-end`, the fixed key `[*]` and the container as `parent`, so several at one level are an `ambiguous identity` group |
| requirement, kanban | the raw id (kanban sections are `g.cluster id=id1`) | the id |
| architecture | services `service-<id>`, groups `group-<id>`, junctions `node-<id>` (Sirena: `junction-<id>`) | `<id>`; `kind` is service, group or junction |
| sequence | `name="<Name>"` on the participant rect/group and lifeline; the `actor<n>` ids are positional. Mermaid draws each participant twice, so `kind` is `participant-top` or `participant-bottom` from the element class | `<Name>` |
| gantt | `rect id=<task id>` (for example `a1`); a task written without an id gets `task<n>` from mermaid; Sirena's SVG rects carry no id (its `task_<s>_<t>` appears only as bar text) | the task label; the id only breaks a tie between same-label tasks, and only when both sides expose an author id, which Sirena's SVG does not today, so same-label tasks pair in order and are an `ambiguous identity` group |
| mindmap, block | `node_<n>` and `id-<random>-<n>` are not semantic | label |
| c4, timeline, pie, gitgraph, the rest | no shared semantic primitive id | label or the per-type role/ordinal in sections 2a and 6 |

The Sirena side carries `node-<id>`, `edge-<A>_to_<B>`, `cluster-<id>` and
`participant-<id>` (measured on flowchart and sequence). A type for which
either SVG carries no recoverable semantic key uses the common label or the
per-type role/ordinal on both sides.

Elements that share `(kind, parent, key)` on either side are `ambiguous
identity` (for example two siblings with the same label). The group COUNT must match (an invariant); members are paired by
order within the group, and the ambiguity is flagged in the evidence and counted
per case. It is never silently excluded.

### 2. Normalization

- **Nested transforms.** Compose every ancestor `transform` (`translate`,
  `scale`, `rotate`, `matrix`) and every nested `svg` viewport/viewBox mapping
  from the root down, then take the absolute bbox of each `rect`, `circle`,
  `ellipse`, `polygon`, `polyline`, `path` and `line`. Nested SVG mapping is
  required by architecture service and group icons, and Sirena xychart line
  series are `polyline` elements. A `text` element has no bbox without font
  metrics, so it is represented by its rendered anchor point: `x`/`y` on the
  text or its first positioned `tspan`, including `dx`/`dy`, composed through
  the same transforms. It takes `e_c` only.
  A matched pair that is zero-sized in the SAME dimension on both sides skips
  the size checks that divide by it (`e_w` or `e_h`, and `e_a`) and is counted in
  the evidence, since mermaid emits attribute-less placeholder `rect` elements.
  A pair that is zero-sized on one side only is a failure: collapsing a node to
  nothing must not pass by making its size errors undefined. Mermaid
  nests `g.root` groups with a translate, places nodes as `translate(cx, cy)`
  with `rect x=-w/2`, and puts cluster rects at absolute positions inside the
  nested roots (checked on `spec/fixtures_mermaid/flowchart/079*`).
- **Scale.** The document scale is removed by working in `viewBox` units. An
  SVG with no `viewBox` (11 of the 14 `info` references) uses its `width` and
  `height` attributes as the viewBox; where those are percentages, the root
  user space is used as is. No
  fitted similarity scale is applied, because it would hide a uniform size
  error, which is what the dimension metric exists to catch.
- **Translation.** The frame `F` is the union bbox of ALL matched compared
  elements (section 6), per side, anchor points included; its top-left is the origin. `D` is the diagonal of
  the REFERENCE frame `F_R`. A degenerate frame (`D = 0`, which is a single
  anchor point, as in `info`) removes no translation: positions are compared as
  they are in root user units, and `D` is the diagonal of the reference root
  extent (`viewBox`, else numeric `width` and `height`, else the `max-width`
  style value as the whole `D`, which is 400 for `info`; that reference declares
  no height). Using the matched set on both sides keeps a missing
  or extra node from skewing the origin (those fail the invariant gate anyway).

### 2a. Logical elements

A compared element is a LOGICAL element, which is not always one SVG primitive.
Where several primitives draw one thing, its bbox is the union of theirs: the
error icon is six `path.error-icon` elements in a reference and two circles and a
rect in Sirena, so each side's icon is the union of its own primitives. The
primitive-to-element grouping is a per-type rule of the extractor, applied to
both sides, and is validated against the corpus in the comparator PR; the
contract fixes only that the unit compared is the union bbox.

Some SVGs do not attach their semantic label to the primitive they draw. The
extractor therefore defines and corpus-validates these associations: sequence message end points to participants; pie paths
to legend labels; radar curve primitives to legend labels; quadrant point and
quadrant rect primitives to their labels; timeline wrappers/markers to their
time, section or event labels; and sankey path endpoints to node rects.
Gitgraph commit keys are the commit ordinal (from the reference's generated
marker class where present, otherwise marker order; Sirena uses marker order),
with an author id used only when both sides expose one. Xychart series keys are
`(chart type, ordinal among that type)`; bars use their index within the series,
while the candidate's point circles are grouped into its line series because
the reference has only a path. These are the only positional keys; they are
reported as extractor-defined rather than presented as semantic SVG ids.

### 3. Equations and threshold

For each matched element, with `c` the bbox center after translation and `w`,
`h` the bbox width and height:

```
e_c = hypot(c_S - c_R) / D          center error, target <= 0.08
e_w = |w_S / w_R - 1|               width error, target <= 0.15
e_h = |h_S / h_R - 1|               height error, target <= 0.15
e_a = |(w_S / h_S) / (w_R / h_R) - 1|   aspect error, target <= 0.15
```

**Reading of "15% dimension-aspect".** All three of `e_w`, `e_h` and `e_a` must
be at most 15%: width, height and aspect ratio each within 15% of the reference.
`e_w` and `e_h` each at 15% alone would still allow `e_a` up to about 35%, so
dropping `e_a` would loosen the bar. The bar itself is unchanged.

**Statistic.** Per case, the MAX over matched elements (the worst element), not
a mean or percentile, because a mean hides one wildly misplaced node. The
scoreboard records, per case: worst `e_c`, worst `e_w`, `e_h` and `e_a`, and the
worst scalar analog error (radius, sweep angle, flow thickness) of section 6, with the
key that produced each, matched count and ambiguous count. The ratchet is that a
case's worst error may not increase, and an improvement must be recorded.

### 4. Overlap and containment

Ancestry comes from the REFERENCE, not from Sirena, so the check is not circular:
two elements are ancestor-related when the reference child bbox lies inside the
reference container bbox (clusters, subgraphs, treemap sections, block groups).

- **Allowed:** ancestor containment. `Layout::Treemap` (`treemap.rb:72-85`) and
  `Layout::Block` (`parent_id`, `block.rb:127`) nest children inside parent
  bounds on purpose.
- **Failure, peer overlap:** two NON-ancestor-related node-like elements (the
  node-like elements in section 6's first row, plus participant shapes,
  treemap cells, packet fields, kanban cards and gantt task shapes) in the
  Sirena render whose bbox
  intersection exceeds 0.5 user units on BOTH axes. Touching is not overlap
  (block cells share edges). Non-rect node shapes use their bbox. Elements that
  meet or cross by construction are exempt: pie sectors (their bboxes overlap
  at the center), radar curves and axes, sankey flows, gitgraph lane lines and
  chart series.
- **Failure, containment:** every reference containment pair must hold in Sirena
  (child inside container), and nothing else may lie inside a container unless
  the reference says so.

### 5. Edges and labels

Part of the hard gate, together with all-nodes-present.

- **Presence comes first.** The checks below run only on elements the
  extractor found, so each is vacuous for an element the render dropped. The
  gate therefore compares counts in both directions, per case, before any
  endpoint or ownership check; a mismatch is a failure whose evidence names
  the rule and the expected and actual counts:
  - `node-presence`: for each `(kind, parent, key)` group of section 1, the
    Sirena count equals the reference count. A missing or extra node or
    container fails.
  - `edge-presence`: an edge is any connector element of the type: the edges
    of the node-and-edge types, sequence messages, sankey flows, and any other
    relationship connector the extractor finds. The per-case total of edges
    equals the reference total. Where this section or section 6 defines an
    identity for the connector (the edge identity below, sequence messages,
    sankey flows), each identity group also has equal counts, so a dropped,
    extra or merged parallel edge fails even when every node is present.
    A connector type with no endpoint identity defined here (mindmap) is
    compared by total only, and the comparator PR defines its endpoint rule;
    an edge whose end is unresolved or `ambiguous endpoint` counts in the
    totals and is reported.
  - `label-presence`: a label is one logical label, the extractor's per-type
    grouping of text primitives (section 2a), applied identically to both
    sides, so a renderer that splits one row over several `foreignObject`s
    still yields one label (ER attribute rows are one, see `label-text`);
    text with empty normalized text (a structural empty cell) is not a label. A label belongs to one owner. Ownership is the
    association this section and sections 2a and 6 define per type (a gantt
    row text belongs to its bar, a pie legend text to its sector); where none
    applies, a node or container label belongs to the innermost owner whose
    bbox contains its anchor, ancestry from the reference (section 4). For
    each owner the number of its labels equals the reference's, zero
    included. A node keyed by an id (any type whose section 1 key is an id)
    therefore still fails when its label is dropped, which the node check
    cannot see. Text that exists on only one side by construction is not a
    label: the Sirena state terminal's `[*]` and the id text Sirena draws on a
    gantt bar (section 1). Every remaining text resolves to an owner by the
    rules above or is a standalone label, a `(kind text, parent, key)` group
    whose counts must match like any other node group, with `key` resolved as
    section 1 resolves any key: the normalized text unless section 2a or 6
    fixes a key or role (`info-text`, `error-icon`). Gitgraph commit ids and tags, drawn outside their marker's bbox on
    both sides, are standalone labels. A text the extractor cannot place in
    either way is a classification failure, reported and never skipped.
    This rule counts owned labels; their text is the `label-text` rule below.
- **Edge identity** is `(source key, target key, ordinal among parallel edges in
  source order)`. Reference endpoints come from the id where it encodes them:
  flowchart `L_<src>_<dst>_<n>`, class `id_<src>_<dst>_<n>` and er `id_entity-<name>-<n>_entity-<name>-<n>_<n>`. Node keys may
  contain underscores, so the id is split by matching against the known node
  keys, and a split that is not unique falls back to the path rule. State edge
  ids (`edge<n>`) encode nothing and always use the path rule: the endpoint is
  the node whose bbox boundary is nearest the path end, within 6 units. A tie is
  recorded as `ambiguous endpoint`.
- **Labels attach to owners.** A node label's anchor lies inside its owner's
  bbox. An edge label's owner is the edge whose path passes nearest its anchor,
  and the owner in the Sirena render must be the same edge (by edge identity) as
  in the reference; no distance threshold is needed. The anchor is the text
  anchor point, or the `foreignObject` rect center.
- **Label text** (`label-text`, its own failure class, separate from
  `label-presence`): an owned label has the reference's text. Text is
  normalized as section 1 says for a key (whitespace collapsed, tags stripped,
  entities decoded) and by nothing else; no new normalization is needed. Four
  extractor details that sentence leaves open: a block boundary (`br`, `p`,
  `div`, `li`, `tr`, `ul`, `ol`, `h1` to `h6`) counts as whitespace, because
  without it `a<br>b` reads `ab` and Sirena's correct text then fails against
  it (`flowchart/054_parser_multi_line_strings_should_be_supported_49`); any
  Unicode space collapses, so a decoded `&nbsp;` does; adjacent `tspan`
  elements are separated by a space; and a reference sequence message drawn as
  several text lines is one label, the lines joined by one space. Label counts
  are taken after the ER row merge below. For each owner present on both
  sides with the same number of labels, the labels pair in reading order, the same on both sides:
  top to bottom by anchor y (an anchor within 4 user units of the row's
  first anchor shares its row), then left to right. ER attribute rows are the
  one place a label is not one cell: the reference draws the type and the name
  as two labels, Sirena draws the row as one. Before pairing, on both sides, the
  labels of one entity that share a row merge into one label, their texts
  joined by one space in reading order, so `string` and `registrationNumber`
  become `string registrationNumber`. A pair with
  unequal normalized text is a failure. Reading order rather than "equal texts
  pair first", because the second passes two labels that carry each other's
  text; on the corpus the two give the same failing cases for every type (see
  the baseline). An owner whose label counts differ is a `label-presence`
  failure and is not text-compared, since pairing labels that do not correspond
  only reports a shifted list; its text is checked once the counts agree. An
  owner present on one side only is a `node-presence` or `label-presence`
  failure. Standalone labels are not compared here: their key is their text, so
  a different text is a `node-presence` failure (except `info-text`, `error-icon`
  and the error text lines of section 6, whose keys are fixed or role-based
  because the two renderers word them differently). The hard gate does not
  compare the wording of those texts.

**Label-text baseline.** The failures `label-text` should report on `main` at
`30a74ebe`, cohort cases only (oracle-valid or the `error` type, and the
reference is not mermaid's own syntax-error diagram), from
[`docs/label-text-baseline.md`](../docs/label-text-baseline.md). Its Reproduce
block regenerates this table in under a minute. The comparator's first run
should match it; a difference means the two extractors disagree and is
explained, not accepted. `label-text` is part of the hard gate, so the gate
starts red on these cases.

| Type | Cohort | `label-text` failures | Shapes (cases, one example) |
|---|---|---|---|
| flowchart | 218 | 43, of which 21 fail only the pipe bug | edge label drawn as `\|text\|` (30, `flowchart/001_config_0`); markup or entity code kept (7, `flowchart/021_platform_xss22_flowchart_20`); quote marks kept (6, `flowchart/016_platform_subgraph_flowchart_15`); `fa:fa-car` drawn as text (5, `flowchart/001_config_0`) |
| class | 142 | 73 | member text rewritten: `+ ` prefix, `name: type` order, spacing (`class/033_platform_yari_class_32`: `test` against `+ test`); `«interface»` against `<<interface>>` (13, `class/034_platform_yari_class_33`); class-name generics `Car<T>` against `Car~T~` (7, `class/108_parser_should_handle_generic_class_107`) |
| sequence | 107 | 6 | markup or entity code kept in a message (4, `sequence/030_parser_should_handle_different_line_breaks_29`); `wrap:` prefix drawn (4, `sequence/019_parser_should_draw_two_actors_notes_to_the_left_with_text_wrapped_inline__18`) |
| architecture | 19 | 2 | icon placeholder, `?` against `I` (`architecture/004_rendering_architecture_spec_architecture_3`) |
| requirement | 24 | 1 | `<<satisfies>>` against `satisfies`, `Verification: Test` against `Verify: Test` (`requirement/001_example_requirement_0`) |
| er | 6 | 3 | attribute rows read type then name in the reference, name then type in Sirena (3, `er/002_platform_yari2_er_1`: `string registrationNumber` against `registrationNumber string`) |
| state | 22 | 0 | 4 cases have a note owner on one side only (presence) and are not text-compared; no compared state label differs |
| other 16 types | 1 to 45 each | 0 by construction | keyed by label text: a text difference is a `node-presence` failure |

Reading the table. 128 of the 538 cohort cases of the seven owner-aware types
fail. A flowchart edge-label fix removes the 21 pipe-only cases, which would
leave 22. Class and ER fail because Sirena draws text that differs from the
reference's; that counts as a failure, so item 21 fixes it and the gate cannot
pass before 21 lands. Owners are resolved
for these seven types only; class cardinality terminals and the
connector labels of other types need the edge path rule, so they are in no
count and the numbers are a floor for them. The shapes, the pairing
sensitivity, the controls and the scripts are in the document.

### 6. Every type has a metric

Every compared element reduces to a bbox or, for text, an anchor point, so the
equations in section 3 apply to all 24 types (anchor points take `e_c` only),
plus the per-type analogs below. No type is "not applicable".
Every bbox with nonzero width and height takes all three strict size checks:
`e_w`, `e_h` and `e_a`. Every scalar size analog `q` below (radius, flow
thickness or sweep angle) takes `|q_S / q_R - 1| <= 0.15`; this is the same 15%
size bar, not another threshold.

| Type | Elements and identity | Position | Size |
|---|---|---|---|
| flowchart, class, er, state, requirement, c4, mindmap, user_journey, architecture, block, kanban | logical node shapes and containers/clusters; section 1 keys and section 2a grouping | `e_c` | bbox `e_w`, `e_h`, `e_a` |
| sequence | participant logical shapes by `name` and top or bottom; messages by (from, to, ordinal), with from and to recovered by the extractor from the message line end points against the participant lifelines (section 2a); note boxes by label; fragment and activation boxes by extractor-defined role plus participant/message interval | participants, notes and boxes `e_c`; message y order must match, endpoint x within 6 units | every nondegenerate bbox `e_w`, `e_h`, `e_a` |
| pie | sector path by the section 2a label association | sector-bbox center, `e_c` | sector bbox `e_w`, `e_h`, `e_a`; radius and sweep angle from the arc endpoints about the group translate (`path.pieCircle` in a `translate(225,225)` group) |
| gantt | task shape by task label (rect bar or milestone polygon, associated with its row text; section 1 for the id rule); date axis ticks by label | task bbox `e_c`; tick text anchor `e_c` | task bbox `e_w`, `e_h`, `e_a` |
| timeline | time, section and event logical elements by their labels; reference wrappers may have a path while Sirena may expose only a text anchor/marker, associated per section 2a | bbox center or text anchor `e_c` | nondegenerate bbox `e_w`, `e_h`, `e_a`; text-only pairs take `e_c` only per section 2 |
| quadrant | quadrant rects and point circles by the section 2a label associations | bbox `e_c` | bbox `e_w`, `e_h`, `e_a`; point radius |
| radar | axes by label (line end point); curves by the section 2a legend association (union of path/polygon and any point markers); graticule circles by radius order | axis end point and curve bbox `e_c` | curve bbox `e_w`, `e_h`, `e_a`; circle radius |
| xychart | plot frame as the extractor-defined union of axis primitives; series by `(chart type, ordinal)`; each bar by its index; each line path/polyline plus candidate point markers as one series element | bbox `e_c` | bbox `e_w`, `e_h`, `e_a` |
| sankey | node rects by label; flow paths by endpoints associated with node rects per section 2a, keyed by (source, target, parallel ordinal) | node and flow bbox `e_c` | bbox `e_w`, `e_h`, `e_a`; flow thickness (SVG stroke width where present, otherwise path thickness at its endpoint) |
| packet | field rects by their contained label | `e_c` | `e_w`, `e_h`, `e_a` |
| treemap | leaf and section rects by label path, with the path recovered from reference containment | `e_c` | `e_w`, `e_h`, `e_a` |
| gitgraph | commit marker by section 2a ordinal (unioning highlight/merge primitives); branch labels by text; lane lines associated with the branch label | marker `e_c`; branch label anchor `e_c`; lane line end points `e_c` | marker bbox `e_w`, `e_h`, `e_a`; radius when the marker is circular |
| info | the sole version/info text, with fixed key `info-text` because the two renderers use different wording | anchor `e_c` | none (a text element has no bbox) |
| error | the error icon (one logical element, the union of its primitives) with fixed key `error-icon`; error text lines use extractor-defined roles because the reference has syntax and version lines while Sirena currently has one message | icon `e_c`; text anchor `e_c` | icon `e_w`, `e_h`, `e_a` |

`info` and `error` are degenerate (one or a few elements) but still non-vacuous:
a missing or misplaced element fails. Sequence is a known gap on arrival:
Sirena draws one top shape per participant, so the reference's bottom
participants have no counterpart and the all-nodes-present invariant fails
until the sequence renderer draws them. Reference-only note, fragment and
activation elements fail the same invariant where present; the comparator
records those gaps, it does not excuse them. Sankey has no reference in
`spec/fixtures_mermaid` today; item 02b step 7 generates it.

### 7. Failure evidence

A failing case records one JSON object:

```
{ case, type, reference,
  sirena_status: "rendered" | {error_stage},
  invariants: [{ rule, subject_keys, expected, actual,
                 bbox_sirena, bbox_reference, normalized }],
  geometry: { worst_e_c, worst_e_w, worst_e_h, worst_e_a, worst_analog, worst_keys,
              matched, ambiguous, top5: [{ key, bbox_sirena, bbox_reference }] },
  reproduce: "<command>" }
```

A `label-text` record uses the same shape: `rule` is `label-text`, `subject_keys`
is the owner key and the pair's index in reading order, `expected` and `actual`
are the reference's and Sirena's normalized texts, and `bbox_sirena` and
`bbox_reference` are the two label anchors; `normalized` is unused. For the
flowchart edge `A` to `B` in `flowchart/001_config_0`:

```
{ rule: "label-text", subject_keys: [["edge", "A", "B", 0], 0],
  expected: "Get money", actual: "|Get money|", bbox_sirena: <anchor>,
  bbox_reference: <anchor> }
```

A missing reference is a FAIL record, never a skip. A Sirena render that raised
records the stage that raised.

### 8. Not in this contract

Golden fixtures (nested transforms, scale and translation normalization,
ancestor containment versus peer collision, one non-box type) and the extractor
belong to the comparator PR. The contract is the spec they are written against.

## Reference cohort (scoping the hard gate)

Two different gaps, and conflating them is how "all reference cases"
became meaningless:

- **Not every corpus case has a reference.** There are 1,997 corpus
  inputs and only ~847 references. mmdc renders cases that have no
  reference at all (`class_diagram/001_platform_click_security_loose_0.mmd`
  is one), and the comparator silently skips a missing reference
  (`tasks/generate_mermaid_fixtures.rake:284`). So corpus completion does NOT
  produce references — reference GENERATION does. That is item 02b step
  7, which regenerates a reference for every oracle-valid case under the
  02a pin. `spec/fixtures_mermaid/` also has 23 type dirs and no sankey
  directory despite sankey being registered; the same step generates
  the missing references. There is no N/A escape: the universal rule in
  `00-overview.md` is that a case leaves a denominator ONLY when the
  oracle rejects it, and "we have no reference" is not an oracle
  rejection.
- **Not every case Sirena can render.** At most today's 614 pass cases
  produce candidate output to compare.

So the critical-path cohort is **oracle-valid ∩ has-a-reference ∩
currently Sirena-pass**. Every newly-passing corpus PR (items 05/06/07)
adds or updates its own parity row, so the cohort grows with the pass
set instead of gating on it. Global closure needs BOTH 02b's reference
generation and the corpus tracks — and a skipped missing reference must
fail rather than pass silently.

## Do

0. **The metric contract above is settled and committed to this file.**
   The comparator is written against it; a change to an entry is a change
   to the bar and goes to the owner.
1. Prove elkrb on ONE type first (flowchart — already ELK-shaped),
   behind the invariants + ratchet. Explicit failure if elkrb errors —
   no silent fallback; decide whether the grid survives as opt-in.
2. Verify what each layout emits vs what elkrb accepts against the
   REAL gem (dependency-contract-check), then roll out per type.
   **Persist the result** as `docs/emit-accept-survey.md` — one row per
   layout: what it emits, what elkrb accepts, and the gap. Item 18
   cannot start without it, so a verification that lives only in a PR
   discussion does not count.
3. Comparator: invariants + normalized geometry vs references; baseline
   fallback first (honest start), then elkrb; scoreboard per case.
4. After each type flips, refresh every doc statement about its layout
   (owned here, not hoped from item 11).

## Done when

- Every type whose layout elkrb can meaningfully own is on elkrb. Some
  cannot be: pie has no node boxes, and block/quadrant are
  pre-positioned by construction. Each such type carries a recorded,
  user-approved exception with its evidence — the point is that no type
  is left undecided, not that elkrb runs everywhere.
- **Zero invariant failures across the cohort** (oracle-valid ∩
  has-a-reference ∩ Sirena-pass) — the hard gate, stated as the
  completion bar, not just a mechanism. It includes `label-text`, so item
  21 must have landed. Cohort membership is read from
  the scoreboard, never hardcoded.
- `docs/emit-accept-survey.md` is committed and covers every layout
  — item 18's start gate.
- A seeded elkrb error fails the render loudly — no silent fall back to
  the grid — and the grid's fate is recorded: removed, or kept as an
  explicit opt-in with a named flag.
- A reference-completeness assertion passes: every oracle-valid case has
  a reference, and every registered type has at least one (sankey has
  none today). A missing reference FAILS the comparator instead of
  being skipped, and cannot be waived — only an oracle rejection removes
  a case from the denominator.
- Every type's geometry at 8%/15% OR at its user-approved renegotiated
  per-type threshold — no third state. Non-box types meet their own
  analogous metric at the equivalent threshold.
- The metric contract above is settled and committed to this file BEFORE
  comparator code is written (done), and golden fixtures cover nested
  transforms, scale/translation normalization, ancestor containment
  versus peer collision, and at least one non-box type.
- The branch floor 80 → 90: if this item finishes first it records the
  handoff in its PR body and closes; if it finishes second it performs
  the raise. Item 07 carries the mirror of this. Neither blocks the
  other, so item 12 is not gated on item 07 finishing.
- Comparator in CI (full lane). Every ELK mention across `README*`,
  `ARCHITECTURE.md`, `docs/` and `sirena.gemspec` has a row
  in item 11's committed manifest resolved as verified / corrected /
  removed. Grep finds the mentions; the manifest decides which are true,
  because after this item lands some ELK claims become correct. The
  gemspec description still claims
  ELK layout; it counts.

## Files

`lib/sirena/engine.rb`, `lib/sirena/layout/*`,
`spec/layout_parity_spec.rb` + comparator lib, scoreboard.
