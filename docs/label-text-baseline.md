# Label text baseline: how many corpus cases the `label-text` rule fails today

Persisted result of the `label-text` rule in
`TODO.foundation/14-elkrb-layout-integration.md` section 5. The comparator is
written against that rule; the numbers below are the failures it should report
on its first run against `main`.

Measured 2026-10-08 on `main` at `30a74ebe`, Ruby 3.4.8, Nokogiri 1.19.4,
against the committed `spec/fixtures_mermaid` references. Everything printed
below comes from the three scripts at the end of this file; the commands are in
[Reproduce](#reproduce) and take under a minute. The figures are the
survey's, not the comparator's: the comparator PR owns the real extractor, and a
different count on its first run is a difference to explain, not to accept.

## What was measured

- **Population.** The 847 unique references (each `correct/` copy is the same
  case and is not counted). 47 are outside the cohort: 30 have an oracle verdict
  of `invalid` and 17 of `artifact`, and the reference of every one is mermaid's
  own syntax-error diagram. The cohort is the other 800. Sirena renders 810 of
  the 847 and all but one of the cohort (`kanban`, 1 case, which does not render,
  so it has no label text to compare).
- **Label and owner.** One label per `foreignObject`, or per `text` outside one,
  with non-empty normalized text. A reference sequence message drawn as several
  text lines is one message. Owners are resolved from the ids both SVGs expose,
  for seven types: flowchart, class, er, state, requirement, architecture, and
  sequence messages. Any other label is standalone: its key is its text, so a
  text difference is a `node-presence` failure and `label-text` adds none
  (the "figure" column below counts those cases anyway, for information).
- **The rule.** Labels of one owner pair in reading order, only for owners with
  the same label count on both sides; a pair with unequal text fails. An owner
  with different counts is a `label-presence` matter and is not text-compared.
  In ER the reference draws each cell of an attribute row (type, name) as its
  own label and Sirena draws the row as one, so the labels of one entity that
  share a row merge into one label, joined by a space in reading order, on both
  sides, before the pairing.
- **Normalization.** Whitespace collapsed, tags stripped, entities decoded, as
  section 1 of the card says. Four extractor details that sentence leaves open:
  a block boundary (`br`, `p`, `div`, `li`, `tr`, `ul`, `ol`, `h1` to `h6`)
  counts as whitespace; any Unicode space collapses; adjacent `tspan` elements
  are separated by a space; and a reference sequence message drawn as several
  text lines is one label, the lines joined by one space. The controls print the
  effect of the first two.

## Result

```text
references=847 cohort=800 excluded=47 (oracle invalid/artifact verdict, or the reference is mermaid's own error diagram)

per type: cohort, Sirena did not render, label-text failures (owner-aware types), of those only the pipe bug, other owner/count differences (label-presence), cases where a text is paired with a different text anywhere in the figure (labels left without a partner are not counted)
type          cohort no-render  label-text pipe-only  presence   figure
architecture      19         0           2         0         3        2
block              6         0         n/a         -         -        0
c4                11         0         n/a         -         -        3
class            142         0          73         0        10       81
er                 6         0           3         0         0        3
error              3         0         n/a         -         -        3
flowchart        218         0          43        21         2       43
gantt             21         0         n/a         -         -       10
gitgraph           6         0         n/a         -         -        6
info              11         0         n/a         -         -       11
kanban            39         1         n/a         -         -        9
mindmap           45         0         n/a         -         -        3
packet             4         0         n/a         -         -        0
pie               40         0         n/a         -         -        3
quadrant           9         0         n/a         -         -        0
radar             14         0         n/a         -         -        0
requirement       24         0           1         0         2        1
sequence         107         0           6         0         1        6
state             22         0           0         0         4        0
timeline          16         0         n/a         -         -        4
treemap            9         0         n/a         -         -        0
user_journey      27         0         n/a         -         -        9
xychart            1         0         n/a         -         -        1

owner-aware types: cohort=538 label-text failures=128 (21 fail only because of the pipe bug)

sensitivity of the pairing rule, cases failing label-text per owner-aware type:
type           reading    document  cancel-then-pair
flowchart           43          43                43
class               73          73                73
er                   3           3                 3
state                0           0                 0
requirement          1           1                 1
architecture         2           2                 2
sequence             6           6                 6

```

Column meanings: `label-text` is the number of cohort cases with at least one
failing pair (the number the card records); `pipe-only` is how many of those fail
only because Sirena draws a flowchart edge label as `|text|`; `presence` is the
cases where an owner exists on one side only or its label count differs; `figure`
is the cases where, anywhere in the figure, a text is paired with a different
text (equal texts cancel first; a label left without a partner is not counted).
For the types whose labels are all standalone it is information only: a text
difference there is already a node-presence failure.

## Failure shapes

Each line is one shape: how many mismatched pairs, in how many cases, and one
example (case, reference text, Sirena text). The shape names are the script's
heuristics; the examples are real.

```text
failure shapes, owner-aware types (labels = mismatched pairs, cases = distinct cases, one example each)
flowchart:
  edge label drawn with its pipes (|text|)                   labels=58  cases=30  e.g. flowchart/001_config_0 reference="Get money" sirena="|Get money|"
  literal markup or entity code (<br>, <a>, #9829;, &lt;)    labels=7   cases=7   e.g. flowchart/021_platform_xss22_flowchart_20 reference="AAA" sirena="\"<a href='javascript#9;t#colon;alert(doc"
  label kept its quote marks                                 labels=7   cases=6   e.g. flowchart/016_platform_subgraph_flowchart_15 reference="id starting with number" sirena="\"id starting with number\""
  icon syntax drawn as text (fa:fa-x)                        labels=5   cases=5   e.g. flowchart/001_config_0 reference="Car" sirena="fa:fa-car Car"
  other                                                      labels=4   cases=4   e.g. flowchart/070_parser_should_allow_back_slashes_in_lean_left_vertices_65 reference="\\This node has a \\ as text\\" sirena="\\This node has a \\\\ as text\\"
class:
  class member format (visibility prefix, spacing, colon)    labels=79  cases=36  e.g. class/033_platform_yari_class_32 reference="test" sirena="+ test"
  other                                                      labels=47  cases=27  e.g. class/031_platform_yari_class_30 reference="+String beakColor" sirena="+ beakColor: String"
  spacing or case only                                       labels=48  cases=22  e.g. class/003_rendering_classdiagram-elk-v3_spec_class_2 reference="+member1" sirena="+ member1"
  angle-bracket annotation (<<x>>, guillemets or escaped)    labels=13  cases=13  e.g. class/034_platform_yari_class_33 reference="«interface»" sirena="<<interface>>"
  literal markup or entity code (<br>, <a>, #9829;, &lt;)    labels=4   cases=4   e.g. class/003_rendering_classdiagram-elk-v3_spec_class_2 reference="<<interface>>" sirena="+ &lt;&lt;interface&gt;&gt;"
er:
  other                                                      labels=20  cases=3   e.g. er/002_platform_yari2_er_1 reference="string registrationNumber" sirena="registrationNumber string"
requirement:
  angle-bracket annotation (<<x>>, guillemets or escaped)    labels=2   cases=1   e.g. requirement/001_example_requirement_0 reference="<<satisfies>>" sirena="satisfies"
  other                                                      labels=1   cases=1   e.g. requirement/001_example_requirement_0 reference="Verification: Test" sirena="Verify: Test"
  reference adds words or symbols                            labels=1   cases=1   e.g. requirement/001_example_requirement_0 reference="Text: the test text." sirena="the test text."
architecture:
  other                                                      labels=5   cases=2   e.g. architecture/004_rendering_architecture_spec_architecture_3 reference="?" sirena="I"
sequence:
  literal markup or entity code (<br>, <a>, #9829;, &lt;)    labels=8   cases=4   e.g. sequence/030_parser_should_handle_different_line_breaks_29 reference="multiline text" sirena="multiline<br>text"
  sequence wrap:/nowrap: prefix drawn                        labels=4   cases=4   e.g. sequence/019_parser_should_draw_two_actors_notes_to_the_left_with_text_wrapped_inline__18 reference="Hello Bob, how are you? If you are not a" sirena="wrap: Hello Bob, how are you? If you are"
```

## What the survey does not resolve

- Labels that need the edge path rule to find their owner stay unowned, so they
  are not in the `label-text` count: the class cardinality terminals (`1`, `*`,
  `many`), and the connector labels of types other than the seven above (c4
  relationship labels, for one).
- Class names that Sirena prefixes with their namespace (`BaseShapes.Triangle`)
  have a different owner key from the reference's `Triangle`; that is an identity
  failure and is not text-compared.
- Architecture icon glyphs (`I`, `A`, `?`) are counted as labels. Whether a drawn
  icon letter is a label is for the comparator PR; the section 5 list of text that
  exists on one side by construction does not name it.
- State edge labels are matched by position among the edges (the reference ids
  `edge<n>` encode nothing). The 4 state cases with a presence difference each
  have a note owner on one side only, and that owner is not text-compared.
- The owner key of an edge is undirected here (endpoints sorted); the card's edge
  identity is directed. Removing the endpoint sorts changes no
  `label-text` count and the presence entries of one case
  (`class/153_parser_should_parse_diagram_with_direction_152`).
- ER attribute rows have no key or comment cells in this corpus, so the row
  merge is measured on type and name only. The 3 ER cases with attributes fail
  on column order: the reference reads `string registrationNumber`, Sirena draws
  `registrationNumber string`.

## Reproduce

From the repository root:

```sh
dir=$(mktemp -d)
for name in render_all label_text_survey report; do
  awk -v head="### $name.rb" '
    $0 == head { found = 1; next }
    found && /^```ruby$/ { inside = 1; next }
    inside && /^```$/ { exit }
    inside' docs/label-text-baseline.md > "$dir/$name.rb"
done
bundle exec ruby -Ilib "$dir/render_all.rb" "$dir/sirena"
bundle exec ruby "$dir/label_text_survey.rb" "$dir/sirena" --json "$dir/results.json"
ruby "$dir/report.rb" "$dir/results.json"
```

The survey reads `spec/mermaid/` and `spec/fixtures_mermaid/` by relative path.
`--control` compares each reference with itself and must report zero differing
cases (`bundle exec ruby "$dir/label_text_survey.rb" "$dir/sirena" --control --json "$dir/control.json"`,
then `report.rb` on it); `--no-block-space` and `--ascii-ws` switch off the
first two extractor details.

### render_all.rb

```ruby
# frozen_string_literal: true

# Renders every reference-bearing corpus input with Sirena and stores the SVG.
# usage, from the repository root: bundle exec ruby -Ilib render_all.rb OUT_DIR
require "sirena"
require "timeout"
require "json"
require "fileutils"

out = ARGV.fetch(0)
status = {}
refs = Dir.glob("spec/fixtures_mermaid/*/*.svg").sort
refs.each do |ref|
  type = File.basename(File.dirname(ref))
  name = File.basename(ref, ".svg")
  src = "spec/mermaid/#{type}/#{name}.mmd"
  key = "#{type}/#{name}"
  unless File.exist?(src)
    status[key] = { "status" => "no_input" }
    next
  end
  FileUtils.mkdir_p(File.join(out, type))
  begin
    svg = Timeout.timeout(30) { Sirena.render(File.read(src)) }
    File.write(File.join(out, type, "#{name}.svg"), svg)
    status[key] = { "status" => "rendered" }
  rescue Timeout::Error
    status[key] = { "status" => "timeout" }
  rescue StandardError, NotImplementedError, SystemStackError => e
    status[key] = { "status" => "error", "error" => "#{e.class}: #{e.message[0, 120]}" }
  end
end
File.write(File.join(out, "status.json"), JSON.pretty_generate(status))
puts "cases=#{status.size} rendered=#{status.count { |_, v| v['status'] == 'rendered' }}"
```

### label_text_survey.rb

```ruby
# frozen_string_literal: true

# Measures how many reference-bearing corpus cases a label TEXT bar would fail.
#
# For each of the 847 unique references in spec/fixtures_mermaid/<type>/ it
# pairs the matching spec/mermaid/<type>/<name>.mmd, takes Sirena's render of
# that input (from the directory render_all.rb filled), extracts the labels of
# both SVGs, normalises their text, assigns each label to an owner, and
# compares texts per owner.
#
# usage, from the repository root, after render_all.rb has filled OUT:
#   bundle exec ruby label_text_survey.rb OUT --json results.json
# --control compares each reference with itself (must report zero failures);
# --no-block-space and --ascii-ws switch off the first two extractor details below.
#
# Normalisation (card 14 section 1): whitespace collapsed, tags stripped,
# entities decoded.  Tags are stripped by taking the DOM text of the label;
# entities are decoded by the XML parser.  Four extractor details the card
# spells out beyond that: block boundaries (BLOCK_TAGS) count as whitespace,
# otherwise `a<br>b` would read `ab` (--no-block-space turns that off to
# measure its effect); any Unicode space collapses (--ascii-ws turns that off);
# adjacent tspan elements are separated by a space; and a reference sequence
# message drawn as several text lines is one label, joined by a space.

# Method.
#  * Cohort: references whose corpus verdict is valid, plus the error type (its
#    verdict is unknown; its reference is meant to be mermaid's error diagram),
#    and that are not mermaid's own syntax-error diagram.  The rest are listed as
#    excluded.
#  * Label: one foreignObject, or one text element outside a foreignObject, with
#    non-empty normalised text.  A reference sequence message drawn as several
#    text lines is merged into one label (lines up to the next message line).
#    Sirena's state terminal "[*]" and gantt bar ids are dropped (card section 5).
#  * Owner: resolved from the ids both SVGs expose, for flowchart, class, er,
#    state, requirement, architecture and sequence messages.  Every other label is
#    standalone: its key is its text (card section 1), so a text difference is a
#    node-presence difference, not a label-text one; those are reported as
#    "figure-level" only.
#  * ER: the labels of one entity that share a row merge into one label (joined
#    by a space, reading order) on both sides, before the pairing below.
#  * Per owner present on both sides with the same number of labels: labels pair
#    in reading order (anchor y, then x; same on both sides) and a pair with
#    unequal text is a label-text failure.  An owner whose label counts differ is a
#    label-presence failure and is not text-compared.  Two alternatives are
#    recorded for sensitivity: pairing in document order, and cancelling equal
#    texts then pairing the leftovers (which also evaluates owners with unequal
#    counts).
#  * Not done: cardinality terminals and other labels whose owner needs the
#    edge path rule stay unowned; namespace-qualified class ids and c4/block
#    connector labels are not resolved.

require "nokogiri"
require "yaml"
require "json"

OUT = ARGV.fetch(0)
BLOCK_SPACE = !ARGV.include?("--no-block-space")
CONTROL = ARGV.include?("--control") # ref-vs-ref: must report zero failures
JSON_OUT = ARGV.include?("--json") ? ARGV[ARGV.index("--json") + 1] : nil

BLOCK_TAGS = %w[br p div li tr ul ol h1 h2 h3 h4 h5 h6].freeze
WS = ARGV.include?("--ascii-ws") ? /\s+/ : /[[:space:]]+/

def norm(str)
  str.gsub(WS, " ").strip
end

def dom_text(node)
  out = +""
  walk = lambda do |n|
    if n.text? || n.cdata?
      out << n.content
    elsif n.element?
      block = BLOCK_SPACE && BLOCK_TAGS.include?(n.name)
      out << " " if block
      if n.name == "tspan" && n.previous_element&.name == "tspan"
        out << " "
      end
      n.children.each { |c| walk.call(c) }
      out << " " if block
    end
  end
  walk.call(node)
  norm(out)
end

Label = Struct.new(:owner, :text, :cls, :ax, :ay, keyword_init: true)

# Affine transforms [a b c d e f], enough for translate, scale, matrix and rotate.
def mat_mul(m, n)
  [m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1],
   m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3],
   m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5]]
end

def parse_transform(str)
  m = [1, 0, 0, 1, 0, 0]
  str.to_s.scan(/(\w+)\s*\(([^)]*)\)/).each do |name, args|
    a = args.split(/[\s,]+/).reject(&:empty?).map(&:to_f)
    t =
      case name
      when "translate" then [1, 0, 0, 1, a[0] || 0, a[1] || 0]
      when "scale" then [a[0] || 1, 0, 0, a[1] || a[0] || 1, 0, 0]
      when "matrix" then a.size == 6 ? a : [1, 0, 0, 1, 0, 0]
      when "rotate"
        r = (a[0] || 0) * Math::PI / 180
        rot = [Math.cos(r), Math.sin(r), -Math.sin(r), Math.cos(r), 0, 0]
        a.size == 3 ? mat_mul(mat_mul([1, 0, 0, 1, a[1], a[2]], rot), [1, 0, 0, 1, -a[1], -a[2]]) : rot
      else [1, 0, 0, 1, 0, 0]
      end
    m = mat_mul(m, t)
  end
  m
end

# Anchor point in root user units: the text's x/y (first tspan if it carries them),
# or the foreignObject rect centre, through every ancestor transform.
def anchor(node)
  m = ([node] + ancestors(node)).reverse.reduce([1, 0, 0, 1, 0, 0]) { |acc, el| mat_mul(acc, parse_transform(el["transform"])) }
  if node.name == "foreignObject"
    x = node["x"].to_f + (node["width"].to_f / 2)
    y = node["y"].to_f + (node["height"].to_f / 2)
  else
    src = [node, *node.xpath("./tspan")].find { |e| e["x"] && e["y"] } || node
    x = src["x"].to_f
    y = src["y"].to_f
  end
  [(m[0] * x) + (m[2] * y) + m[4], (m[1] * x) + (m[3] * y) + m[5]]
end

ROW_TOLERANCE = 4.0 # user units: labels whose y differs by at most this share a row

# Reading order: top to bottom by anchor y, left to right inside a row.
def reading_rows(labels)
  rows = []
  labels.each_with_index.sort_by { |l, i| [l.ay, l.ax, i] }.each do |l, _i|
    if rows.last && l.ay - rows.last.first.ay <= ROW_TOLERANCE
      rows.last << l
    else
      rows << [l]
    end
  end
  rows.map { |r| r.each_with_index.sort_by { |l, i| [l.ax, i] }.map(&:first) }
end

def reading_order(labels)
  reading_rows(labels).flatten(1)
end

# ER attribute rows: the reference draws each cell of a row (type, name, key,
# comment) as its own label, Sirena draws the row as one.  The labels of one
# entity that share a row merge into one label, joined by a space in reading
# order, on both sides.
def merge_er_rows(labels)
  labels.group_by(&:owner).flat_map do |owner, group|
    next group unless owner&.first == :node

    reading_rows(group).map do |row|
      first = row.first
      Label.new(owner: owner, text: row.map(&:text).join(" "), cls: first.cls, ax: first.ax, ay: first.ay)
    end
  end
end

def parse(path)
  doc = Nokogiri::XML(File.read(path))
  doc.remove_namespaces!
  doc
end

def ancestors(node)
  list = []
  p = node.parent
  while p&.element?
    list << p
    p = p.parent
  end
  list
end

def classes(node)
  (node["class"] || "").split
end

# Label primitives: every foreignObject and every text outside a foreignObject.
def primitives(doc)
  doc.xpath("//text[not(ancestor::foreignObject)] | //foreignObject").map do |n|
    txt = dom_text(n)
    next if txt.empty?

    [n, txt]
  end.compact
end

def split_pair(str, sep, known)
  parts = str.split(sep, -1)
  (1...parts.size).each do |i|
    a = parts[0...i].join(sep)
    b = parts[i..].join(sep)
    return [a, b] if known.include?(a) && known.include?(b)
  end
  [parts[0], parts[1..].join(sep)]
end

# ---------------------------------------------------------------- owners
# Each resolver gets (prim_node, ancestors, ctx) and returns an owner key or nil.
# ctx[:known] holds the node ids of that side; ref_rank and sirena_rank number
# parallel edges 0, 1, ... so both sides name the same edge the same way.

module Owners
  module_function

  # --- flowchart
  def flowchart_ref(_n, anc, ctx)
    anc.each do |g|
      id = g["id"].to_s
      cl = classes(g)
      return [:node, Regexp.last_match(1)] if cl.include?("node") && id =~ /\Aflowchart-(.+)-\d+\z/
      return [:cluster, id] if cl.include?("cluster") && !id.empty?
      if g["data-id"].to_s =~ /\AL_(.+)_(\d+)\z/
        a, b = split_pair(Regexp.last_match(1), "_", ctx[:known])
        return [:edge, [a, b].sort, ctx[:ref_rank].call([a, b].sort, Regexp.last_match(2).to_i)]
      end
    end
    nil
  end

  def flowchart_sirena(_n, anc, ctx)
    anc.each do |g|
      id = g["id"].to_s
      return [:node, Regexp.last_match(1)] if id =~ /\Anode-(.+)\z/
      return [:cluster, Regexp.last_match(1)] if id =~ /\Acluster-(.+)\z/
      next unless id =~ /\Aedge-(.+)\z/

      a, b = split_pair(Regexp.last_match(1), "_to_", ctx[:known])
      return [:edge, [a, b].sort, ctx[:sirena_rank].call([a, b].sort, g)]
    end
    nil
  end

  # --- class
  def class_ref(_n, anc, ctx)
    anc.each do |g|
      id = g["id"].to_s
      return [:node, Regexp.last_match(1)] if id =~ /\AclassId-(.+)-\d+\z/
      if g["data-id"].to_s =~ /\Aid_(.+)_(\d+)\z/
        a, b = split_pair(Regexp.last_match(1), "_", ctx[:known])
        return [:edge, [a, b].sort, ctx[:ref_rank].call([a, b].sort, Regexp.last_match(2).to_i)]
      end
    end
    nil
  end

  def class_sirena(_n, anc, ctx)
    anc.each do |g|
      id = g["id"].to_s
      return [:node, Regexp.last_match(1)] if id =~ /\Aclass-(.+)\z/
      next unless id =~ /\Arel-(.+)\z/

      a, b = split_pair(Regexp.last_match(1), "_to_", ctx[:known])
      return [:edge, [a, b].sort, ctx[:sirena_rank].call([a, b].sort, g)]
    end
    nil
  end

  # --- er
  def er_ref(_n, anc, ctx)
    anc.each do |g|
      id = g["id"].to_s
      return [:node, Regexp.last_match(1)] if id =~ /\Aentity-(.+)-\d+\z/
      if g["data-id"].to_s =~ /\Aid_entity-(.+)-\d+_entity-(.+)-\d+_(\d+)\z/
        a = Regexp.last_match(1)
        b = Regexp.last_match(2)
        return [:edge, [a, b].sort, ctx[:ref_rank].call([a, b].sort, Regexp.last_match(3).to_i)]
      end
    end
    nil
  end

  def er_sirena(_n, anc, ctx)
    anc.each do |g|
      id = g["id"].to_s
      return [:node, Regexp.last_match(1)] if id =~ /\Aentity-(.+)\z/
      next unless id =~ /\Arel-(.+)\z/

      a, b = split_pair(Regexp.last_match(1), "_to_", ctx[:known])
      return [:edge, [a, b].sort, ctx[:sirena_rank].call([a, b].sort, g)]
    end
    nil
  end

  # --- state
  def state_ref(_n, anc, ctx)
    anc.each do |g|
      id = g["id"].to_s
      cl = classes(g)
      return [:node, Regexp.last_match(1)] if cl.include?("node") && id =~ /\Astate-(.+)-\d+\z/
      return [:node, id] if cl.include?("statediagram-cluster")
      return [:edge_idx, Regexp.last_match(1).to_i] if g["data-id"].to_s =~ /\Aedge(\d+)\z/
    end
    nil
  end

  def state_sirena(_n, anc, ctx)
    anc.each do |g|
      id = g["id"].to_s
      return [:node, Regexp.last_match(1)] if id =~ /\Astate-(.+)\z/
      return [:edge_idx, ctx[:transition_index].call(g)] if id =~ /\Atransition-/
    end
    nil
  end

  # --- requirement
  def requirement_ref(_n, anc, ctx)
    anc.each do |g|
      id = g["id"].to_s
      cl = classes(g)
      return [:node, id] if cl.include?("node") && !id.empty?
      if g["data-id"].to_s =~ /\A(.+)-(\d+)\z/
        a, b = split_pair(Regexp.last_match(1), "-", ctx[:known])
        return [:edge, [a, b].sort, ctx[:ref_rank].call([a, b].sort, Regexp.last_match(2).to_i)]
      end
    end
    nil
  end

  def requirement_sirena(_n, anc, ctx)
    anc.each do |g|
      id = g["id"].to_s
      return [:node, Regexp.last_match(1)] if id =~ /\A(?:requirement|element)-(.+)\z/
      next unless id =~ /\Arelationship-(.+)\z/

      a, b = split_pair(Regexp.last_match(1), "-", ctx[:known])
      return [:edge, [a, b].sort, ctx[:sirena_rank].call([a, b].sort, g)]
    end
    nil
  end

  # --- architecture
  def architecture_ref(_n, anc, _ctx)
    anc.each do |g|
      id = g["id"].to_s
      return [:node, Regexp.last_match(1)] if id =~ /\A(?:service|group)-(.+)\z/
    end
    nil
  end

  def architecture_sirena(_n, anc, _ctx)
    anc.each do |g|
      id = g["id"].to_s
      return [:node, Regexp.last_match(1)] if id =~ /\A(?:service|group)-(.+)\z/
    end
    nil
  end

  # --- sequence: messages by ordinal
  def sequence_ref(n, _anc, ctx)
    return [:message, ctx[:msg_index].call(n)] if classes(n).include?("messageText")

    nil
  end

  def sequence_sirena(_n, anc, _ctx)
    anc.each do |g|
      return [:message, Regexp.last_match(1).to_i] if g["id"].to_s =~ /\Amessage-(\d+)\z/
    end
    nil
  end
end

OWNER_TYPES = %w[flowchart class er state requirement architecture sequence].freeze

def known_ids(doc, type, side)
  ids = []
  doc.xpath("//g[@id]").each do |g|
    id = g["id"]
    case [type, side]
    when ["flowchart", :ref] then ids << Regexp.last_match(1) if id =~ /\Aflowchart-(.+)-\d+\z/
    when ["flowchart", :sirena] then ids << Regexp.last_match(1) if id =~ /\Anode-(.+)\z/
    when ["class", :ref] then ids << Regexp.last_match(1) if id =~ /\AclassId-(.+)-\d+\z/
    when ["class", :sirena] then ids << Regexp.last_match(1) if id =~ /\Aclass-(.+)\z/
    when ["er", :ref] then ids << Regexp.last_match(1) if id =~ /\Aentity-(.+)-\d+\z/
    when ["er", :sirena] then ids << Regexp.last_match(1) if id =~ /\Aentity-(.+)\z/
    when ["requirement", :ref] then ids << id if classes(g).include?("node")
    when ["requirement", :sirena] then ids << Regexp.last_match(1) if id =~ /\A(?:requirement|element)-(.+)\z/
    end
  end
  ids.to_a
end

def extract(doc, type, side, mmd)
  prims = primitives(doc)
  ctx = { known: known_ids(doc, type, side) }
  # parallel edge rank: ref ordinals are rank-normalised; sirena by document order
  ref_nums = Hash.new { |h, k| h[k] = [] }
  if side == :ref
    doc.xpath("//*[@data-id]").each do |g|
      did = g["data-id"].to_s
      pair =
        case type
        when "flowchart" then did =~ /\AL_(.+)_(\d+)\z/ && [Regexp.last_match(1), Regexp.last_match(2).to_i, :flow]
        when "class" then did =~ /\Aid_(.+)_(\d+)\z/ && [Regexp.last_match(1), Regexp.last_match(2).to_i, :cls]
        when "er" then did =~ /\Aid_entity-(.+)-\d+_entity-(.+)-\d+_(\d+)\z/ && [[Regexp.last_match(1), Regexp.last_match(2)], Regexp.last_match(3).to_i, :er]
        when "requirement" then did =~ /\A(.+)-(\d+)\z/ && [Regexp.last_match(1), Regexp.last_match(2).to_i, :req]
        end
      next unless pair

      key, num, kind = pair
      pr =
        case kind
        when :er then key.sort
        when :flow, :cls then split_pair(key, "_", ctx[:known]).sort
        when :req then split_pair(key, "-", ctx[:known]).sort
        end
      ref_nums[pr] << num unless ref_nums[pr].include?(num)
    end
    ref_nums.each_value(&:sort!)
  end
  ctx[:ref_rank] = ->(pair, num) { ref_nums[pair].index(num) || num }
  seen = Hash.new { |h, k| h[k] = [] }
  ctx[:sirena_rank] = lambda do |pair, g|
    seen[pair] << g unless seen[pair].include?(g)
    seen[pair].index(g)
  end
  transitions = doc.xpath("//g[starts-with(@id,'transition-')]").to_a
  ctx[:transition_index] = ->(g) { transitions.index(g) }
  # Reference: a multi-line message is several text.messageText elements followed by
  # one line.messageLine*; texts up to the next message line form one logical message.
  msg_group = {}
  group = 0
  pending = false
  doc.xpath("//*[(self::text and contains(concat(' ',normalize-space(@class),' '),' messageText ')) or ((self::line or self::path) and contains(@class,'messageLine'))]").each do |el|
    if el.name == "text"
      msg_group[el] = group
      pending = true
    elsif pending
      group += 1
      pending = false
    end
  end
  ctx[:msg_index] = ->(n) { msg_group[n] }

  resolver = OWNER_TYPES.include?(type) ? Owners.method("#{type}_#{side == :ref ? 'ref' : 'sirena'}") : nil
  task_ids = type == "gantt" ? mmd.scan(/:\s*(?:(?:crit|done|active|milestone)\s*,\s*)*([A-Za-z_][\w-]*)\s*,/).flatten : []
  prims.filter_map do |n, txt|
    next if side == :sirena && txt == "[*]"
    next if side == :sirena && type == "gantt" && task_ids.include?(txt)

    anc = ancestors(n)
    owner = resolver&.call(n, anc, ctx)
    ax, ay = anchor(n)
    Label.new(owner: owner, text: txt, cls: classes(n).join("."), ax: ax, ay: ay)
  end.then do |labels|
    next labels unless type == "sequence" && side == :ref

    merged = {}
    labels.each_with_object([]) do |l, acc|
      if l.owner&.first == :message
        if (m = merged[l.owner])
          m.text = "#{m.text} #{l.text}"
          next
        end
        merged[l.owner] = l
      end
      acc << l
    end
  end
end

# State edge labels: the reference numbers every edge (edge0, edge1 ...) even
# when it has no text; Sirena draws a transition group per transition.  Map the
# k-th Sirena transition to reference edge k.  Verified per case by checking the
# two counts; on a mismatch the edge labels fall back to one bucket.
def fix_state_edges!(ref_labels, sir_labels, rdoc, sdoc)
  r_edges = rdoc.xpath("//*[@data-id]").map { |g| g["data-id"] =~ /\Aedge(\d+)\z/ ? Regexp.last_match(1).to_i : nil }.compact.sort
  s_edges = sdoc.xpath("//g[starts-with(@id,'transition-')]").size
  consistent = r_edges.size == s_edges
  [ref_labels, sir_labels].each do |ls|
    ls.each do |l|
      next unless l.owner&.first == :edge_idx

      l.owner = [:edge_bucket] unless consistent
    end
  end
  consistent
end

# Cancel the texts both sides share; leftovers pair in order.  Used for the
# figure-level view and as the sensitivity alternative to reading-order pairing.
def compare_owner(ref_texts, sir_texts)
  r = ref_texts.dup
  s = sir_texts.dup
  common = []
  r.dup.each do |t|
    if (i = s.index(t))
      common << t
      s.delete_at(i)
      r.delete_at(r.index(t))
    end
  end
  both = [r.size, s.size].min
  mismatched = r.first(both).zip(s.first(both)) # leftovers on both sides: text differs
  extra_ref = r.drop(both)
  extra_sir = s.drop(both)
  order_only = r.empty? && s.empty? && ref_texts != sir_texts
  { mismatched: mismatched, extra_ref: extra_ref, extra_sir: extra_sir, order_only: order_only }
end

def shape(rt, st)
  return "edge label drawn with its pipes (|text|)" if st == "|#{rt}|"
  return "label kept its quote marks" if st == "\"#{rt}\""
  return "icon syntax drawn as text (fa:fa-x)" if st =~ /\bfa[blrs]?:fa-/
  return "sequence wrap:/nowrap: prefix drawn" if st =~ /\A(?:no)?wrap: / && st.sub(/\A(?:no)?wrap: /, "").start_with?(rt)
  return "literal markup or entity code (<br>, <a>, #9829;, &lt;)" if st =~ %r{<\s*/?\s*(?:br|a|b|i|u|strong|em|span|p)\b|#\w+;|&(?:lt|gt|amp|quot|#\d+);}i
  return "angle-bracket annotation (<<x>>, guillemets or escaped)" if (rt + st) =~ /<<\w+>>|\u00ab\w+\u00bb|&lt;&lt;/
  return "spacing or case only" if rt.downcase.delete(" ") == st.downcase.delete(" ")
  strip = ->(x) { x.gsub(/[\s+\-#~:]/, "") }
  return "class member format (visibility prefix, spacing, colon)" if strip.call(rt) == strip.call(st)
  return "reference adds words or symbols" if st.length > 1 && rt.include?(st)
  return "sirena adds words or symbols" if rt.length > 1 && st.include?(rt)
  return "truncated with ellipsis" if st.end_with?("...", "\u2026")
  "other"
end

verdicts = YAML.load_file("spec/mermaid/corpus-verdicts.yml").to_h { |h| [h["case"], h["verdict"]] }
status = JSON.parse(File.read(File.join(OUT, "status.json")))

results = []
Dir.glob("spec/fixtures_mermaid/*/*.svg").sort.each do |ref|
  type = File.basename(File.dirname(ref))
  name = File.basename(ref, ".svg")
  key = "#{type}/#{name}"
  verdict = verdicts["#{key}.mmd"] || "none"
  rec = { case: key, type: type, verdict: verdict }
  rsvg = File.read(ref)
  rec[:ref_is_error_svg] = rsvg.include?("Syntax error in text") && type != "error"
  if rec[:ref_is_error_svg] || !(verdict == "valid" || type == "error")
    rec[:cohort] = false
    results << rec
    next
  end
  rec[:cohort] = true
  rec[:sirena_status] = status.dig(key, "status")
  unless rec[:sirena_status] == "rendered"
    results << rec
    next
  end
  mmd = File.read("spec/mermaid/#{key}.mmd")
  rdoc = parse(ref)
  sdoc = CONTROL ? parse(ref) : parse(File.join(OUT, "#{key}.svg"))
  rl = extract(rdoc, type, :ref, mmd)
  sl = extract(sdoc, type, CONTROL ? :ref : :sirena, mmd)
  fix_state_edges!(rl, sl, rdoc, sdoc) if type == "state"
  rl, sl = merge_er_rows(rl), merge_er_rows(sl) if type == "er"

  owned_r = rl.select(&:owner).group_by(&:owner)
  owned_s = sl.select(&:owner).group_by(&:owner)
  rec[:owned_ref] = rl.count(&:owner)
  rec[:owned_sirena] = sl.count(&:owner)
  rec[:standalone_ref] = rl.count { |l| l.owner.nil? }
  rec[:standalone_sirena] = sl.count { |l| l.owner.nil? }

  mism = []
  leftover = []
  doc_order = []
  presence = []
  (owned_r.keys & owned_s.keys).each do |o|
    rls = owned_r[o]
    sls = owned_s[o]
    # Alternative rule, kept for the sensitivity line: cancel equal texts, pair leftovers.
    compare_owner(rls.map(&:text), sls.map(&:text))[:mismatched].each { |rt, st| leftover << { owner: o, ref: rt, sirena: st } }
    if rls.size != sls.size
      presence << { owner: o, ref_count: rls.size, sirena_count: sls.size }
      next
    end
    reading_order(rls).zip(reading_order(sls)).each do |rl1, sl1|
      mism << { owner: o, ref: rl1.text, sirena: sl1.text, shape: shape(rl1.text, sl1.text) } if rl1.text != sl1.text
    end
    rls.zip(sls).each { |rl1, sl1| doc_order << { owner: o } if rl1.text != sl1.text }
  end
  rec[:owner_only_ref] = (owned_r.keys - owned_s.keys).size
  rec[:owner_only_sirena] = (owned_s.keys - owned_r.keys).size
  rec[:text_mismatches] = mism
  rec[:presence_diffs] = presence
  rec[:leftover_mismatches] = leftover
  rec[:doc_order_mismatches] = doc_order

  # figure-level multiset over ALL labels (owned and standalone)
  fig = compare_owner(rl.map(&:text), sl.map(&:text))
  rec[:figure_mismatched] = fig[:mismatched].map { |rt, st| { ref: rt, sirena: st, shape: shape(rt, st) } }
  rec[:figure_extra_ref] = fig[:extra_ref]
  rec[:figure_extra_sirena] = fig[:extra_sir]
  # standalone-only multiset (text-keyed groups; a difference is a node-presence matter)
  st_r = rl.select { |l| l.owner.nil? }.map(&:text)
  st_s = sl.select { |l| l.owner.nil? }.map(&:text)
  sa = compare_owner(st_r, st_s)
  rec[:standalone_mismatched] = sa[:mismatched].map { |rt, st| { ref: rt, sirena: st, shape: shape(rt, st) } }
  rec[:standalone_extra_ref] = sa[:extra_ref]
  rec[:standalone_extra_sirena] = sa[:extra_sir]
  results << rec
end

File.write(JSON_OUT, JSON.pretty_generate(results)) if JSON_OUT
puts "records=#{results.size} cohort=#{results.count { |r| r[:cohort] }} "
```

### report.rb

```ruby
# frozen_string_literal: true

# usage: ruby report.rb results.json
require "json"
rs = JSON.parse(File.read(ARGV.fetch(0)))
OWNER = %w[flowchart class er state requirement architecture sequence].freeze
PIPE = "edge label drawn with its pipes (|text|)"
coh = rs.select { |r| r["cohort"] }
puts "references=#{rs.size} cohort=#{coh.size} excluded=#{rs.size - coh.size} " \
     "(oracle invalid/artifact verdict, or the reference is mermaid's own error diagram)"
puts
puts "per type: cohort, Sirena did not render, label-text failures (owner-aware types), " \
     "of those only the pipe bug, other owner/count differences (label-presence), " \
     "cases where a text is paired with a different text anywhere in the figure (labels left without a partner are not counted)"
puts format("%-13s %6s %9s %11s %9s %9s %8s", "type", "cohort", "no-render", "label-text", "pipe-only", "presence", "figure")
tot = Hash.new(0)
coh.group_by { |r| r["type"] }.sort.each do |t, a|
  rend = a.select { |r| r["sirena_status"] == "rendered" }
  own = OWNER.include?(t)
  tf = rend.select { |r| r["text_mismatches"].any? }
  pipe = tf.count { |r| r["text_mismatches"].all? { |m| m["shape"] == PIPE } }
  pres = rend.count { |r| r["presence_diffs"].any? || r["owner_only_ref"].positive? || r["owner_only_sirena"].positive? }
  fg = rend.count { |r| r["figure_mismatched"].any? }
  puts format("%-13s %6d %9d %11s %9s %9s %8d", t, a.size, a.size - rend.size,
              own ? tf.size : "n/a", own ? pipe : "-", own ? pres : "-", fg)
  next unless own

  tot[:cohort] += a.size
  tot[:tf] += tf.size
  tot[:pipe] += pipe
end
puts
puts "owner-aware types: cohort=#{tot[:cohort]} label-text failures=#{tot[:tf]} " \
     "(#{tot[:pipe]} fail only because of the pipe bug)"
puts
puts "sensitivity of the pairing rule, cases failing label-text per owner-aware type:"
puts format("%-13s %8s %11s %17s", "type", "reading", "document", "cancel-then-pair")
OWNER.each do |t|
  a = coh.select { |r| r["type"] == t && r["sirena_status"] == "rendered" }
  puts format("%-13s %8d %11d %17d", t, a.count { |r| r["text_mismatches"].any? },
              a.count { |r| r["doc_order_mismatches"].any? }, a.count { |r| r["leftover_mismatches"].any? })
end
puts
puts "failure shapes, owner-aware types (labels = mismatched pairs, cases = distinct cases, one example each)"
OWNER.each do |t|
  shapes = Hash.new { |h, k| h[k] = [] }
  rs.select { |r| r["type"] == t && r["text_mismatches"].to_a.any? }.each do |r|
    r["text_mismatches"].each { |m| shapes[m["shape"]] << [r["case"], m] }
  end
  next if shapes.empty?

  puts "#{t}:"
  shapes.sort_by { |k, v| [-v.map(&:first).uniq.size, k] }.each do |k, v|
    c, m = v.first
    puts format("  %-58s labels=%-3d cases=%-3d e.g. %s reference=%s sirena=%s", k, v.size, v.map(&:first).uniq.size,
                c, m["ref"][0, 40].inspect, m["sirena"][0, 40].inspect)
  end
end
```
