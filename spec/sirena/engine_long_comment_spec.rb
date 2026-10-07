# frozen_string_literal: true

require "spec_helper"
require "date"

# The shared `comment` rule (Grammars::Common, and Grammars::Treemap's own
# copy) must scan a comment in one run. A per-character walk makes a 100 KB
# comment take several CPU seconds in every type that uses the rule.
RSpec.describe Sirena::Engine do
  include CpuTiming

  # One minimal valid diagram per type that parses its comments through the
  # shared rule. kanban refuses a comment at these places, and mindmap reads
  # a comment line as a node through its own rule, so neither shows this fix.
  diagrams = {
    "flowchart" => "flowchart TD\n  A --> B\n",
    "sequenceDiagram" => "sequenceDiagram\n  A->>B: hi\n",
    "classDiagram" => "classDiagram\n  class A\n",
    "stateDiagram-v2" => "stateDiagram-v2\n  [*] --> A\n",
    "erDiagram" => "erDiagram\n  A ||--o{ B : has\n",
    "gantt" => "gantt\n  title t\n  section s\n  a :a1, 2024-01-01, 1d\n",
    "pie" => "pie\n  \"a\" : 1\n",
    "timeline" => "timeline\n  title t\n  2020 : a\n",
    "quadrantChart" => "quadrantChart\n  title t\n  x-axis L --> R\n  " \
                       "y-axis L --> H\n  A: [0.3, 0.6]\n",
    "gitGraph" => "gitGraph\n  commit\n",
    "radar-beta" => "radar-beta\n  axis a, b, c\n  curve c1{1,2,3}\n",
    "block-beta" => "block-beta\n  columns 1\n  a\n",
    "requirementDiagram" => "requirementDiagram\n  requirement r {\n    " \
                            "id: 1\n    text: t\n    risk: low\n    " \
                            "verifymethod: test\n  }\n",
    "xychart-beta" => "xychart-beta\n  x-axis [a, b]\n  bar [1, 2]\n",
    "architecture-beta" => "architecture-beta\n  service a(server)[A]\n",
    "sankey-beta" => "sankey-beta\n\na,b,1\n",
    "packet-beta" => "packet-beta\n  0-7: \"a\"\n",
    "treemap-beta" => "treemap-beta\n  \"a\": 1\n",
    "C4Context" => "C4Context\n  Person(a, \"A\")\n",
    "info" => "info\n",
    "error" => "error\n",
  }

  # Right after the keyword line, and after the last statement.
  placements = {
    "after the keyword" => ->(src, text) { src.sub("\n", "\n#{text}\n") },
    "after the last statement" => ->(src, text) { "#{src}#{text}\n" },
  }

  let(:engine) { described_class.new(today: Date.new(2024, 1, 1)) }

  # CPU time, not wall time, so a busy machine cannot move it. An absolute
  # bound rather than the ratio `CpuTiming` recommends: the fixed parse is a
  # few milliseconds, too small for a stable ratio. The unfixed parse takes
  # 2.3 s or more and the fixed one 0.02 s or less, so 0.5 s has a wide
  # margin on both sides.
  describe "#render with a 100 KB comment" do
    diagrams.each do |keyword, source|
      placements.each do |where, place|
        context "with #{keyword} and the comment #{where}" do
          let(:short) { place.call(source, "%% x") }
          let(:long) { place.call(source, "%% #{'x' * 100_000}") }

          it "renders as with a short one, in bounded CPU time",
             :aggregate_failures do
            expected = engine.render(short)
            output = nil
            elapsed = cpu_time { output = engine.render(long) }
            expect(output).to eq(expected)
            expect(elapsed).to be < 0.5
          end
        end
      end
    end
  end

  # Keep these: they are the only check that the rule still accepts a
  # comment with nothing in it and does not take `%%{` for a different
  # construct. Both stay green against the old per-character rule; they go
  # red when the run is made to require a character (`min: 1`) or to refuse
  # `{`.
  describe "#render with an empty comment or a directive-shaped one" do
    comments = ["%%", "%%{x}%%"]
    {
      "pie" => "pie\n  \"a\" : 1\n",
      "treemap-beta" => "treemap-beta\n  \"a\": 1\n",
    }.each do |keyword, source|
      comments.each do |comment|
        it "renders #{keyword} ending in #{comment.inspect} as without it" do
          expect(engine.render("#{source}#{comment}\n"))
            .to eq(engine.render(source))
        end
      end
    end
  end
end
