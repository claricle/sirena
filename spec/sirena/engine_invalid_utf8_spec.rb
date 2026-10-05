# frozen_string_literal: true

require "spec_helper"

# Every source below carries a `§` where a label, title or comment sits. The
# spec swaps it for bytes that are not valid UTF-8 and holds the engine to the
# one thing mmdc does with them: node decodes the file as UTF-8, every invalid
# run becomes U+FFFD, and the diagram is drawn from the decoded text.
module InvalidUtf8Helpers
  # One minimal, valid source per registered type. `§` marks the slot the
  # invalid bytes go into; where a type's grammar refuses a non-ASCII word
  # (sankey) the slot is a `%%` comment, so the render still succeeds.
  def self.lines(*rows)
    "#{rows.join("\n")}\n"
  end

  SOURCES = {
    flowchart: lines("flowchart LR", "  A[§]-->B"),
    sequence: lines("sequenceDiagram", "  Alice->>Bob: §"),
    class_diagram: lines("classDiagram", "  class Animal {",
                         "    +String name§", "  }"),
    state_diagram: lines("stateDiagram-v2", "  [*] --> Still",
                         "  Still --> Moving: §"),
    er_diagram: lines("erDiagram", '  CUSTOMER ||--o{ ORDER : "§"'),
    user_journey: lines("journey", "  title §", "  section Work",
                        "    Task: 5: Me"),
    pie: lines("pie title §", '  "Dogs" : 5', '  "Cats" : 3'),
    gantt: lines("gantt", "  title §", "  dateFormat YYYY-MM-DD",
                 "  section S", "  Task :a1, 2024-01-01, 3d"),
    timeline: lines("timeline", "  title §", "  2002 : LinkedIn"),
    quadrant: lines("quadrantChart", "  title §", "  x-axis Low --> High",
                    "  y-axis Low --> High", "  A: [0.3, 0.6]"),
    git_graph: lines("gitGraph", '  commit id: "a§"', "  commit"),
    mindmap: lines("mindmap", "  root((§))", "    child"),
    kanban: lines("kanban", "  todo[§]", "    t1[Task]"),
    radar: lines("radar-beta", "  title §", "  axis a, b, c",
                 "  curve k{1, 2, 3}"),
    block: lines("block-beta", "  columns 2", '  a["§"]', "  b"),
    requirement: lines("requirementDiagram", "  requirement r {",
                       "    id: 1", "    text: §", "    risk: high",
                       "    verifymethod: test", "  }"),
    xychart: lines("xychart-beta", '  title "§"', "  x-axis [a, b]",
                   "  bar [1, 2]"),
    architecture: lines("architecture-beta", "  service db(database)[§]"),
    sankey: lines("sankey-beta", "%% §", "A,B,10"),
    packet: lines("packet-beta", '  0-15: "§"'),
    treemap: lines("treemap-beta", '  "§"', '    "Leaf": 10'),
    c4: lines("C4Context", "  title §", '  Person(a, "Alice")'),
    info: lines("%% §", "info"),
    error: lines("%% §", "error"),
  }.freeze

  # Invalid byte runs and how many U+FFFD node's decoder (and so mmdc)
  # turns each into. The counts are `Buffer.toString("utf8")`'s; change one
  # only against that.
  BYTE_RUNS = {
    "a lone 0xFF" => ["\xFF", 1],
    "a stray continuation byte" => ["\x80", 1],
    "a truncated three-byte sequence" => ["\xE2\x82", 1],
    "an overlong two-byte sequence" => ["\xC0\xAF", 2],
    "an encoded surrogate" => ["\xED\xA0\x80", 3],
    "a code point past U+10FFFF" => ["\xF4\x90\x80\x80", 4],
  }.freeze

  def with_slot(source, filler)
    source.b.gsub("§".b, filler.b).force_encoding(Encoding::UTF_8)
  end
  module_function :with_slot

  def outcome(source)
    [:svg, Sirena::Engine.new(today: Date.new(2024, 1, 1)).render(source)]
  rescue Sirena::Error => e
    [e.class, e.message]
  end
  module_function :outcome

  def svg_kinds(slot)
    Sirena::DiagramRegistry.types.to_h do |type|
      [type, outcome(with_slot(SOURCES.fetch(type), slot)).first]
    end
  end
  module_function :svg_kinds
end

RSpec.describe Sirena::Engine do
  include InvalidUtf8Helpers

  it "renders a source with invalid bytes for every registered type" do
    # A type registered without a row in SOURCES raises KeyError here, so a
    # new type cannot slip past this file's claim.
    expected = Sirena::DiagramRegistry.types.to_h { |type| [type, :svg] }

    expect(svg_kinds("\xFF")).to eq(expected)
  end

  InvalidUtf8Helpers::SOURCES.each do |type, source|
    describe "#render of #{type} with invalid UTF-8 bytes" do
      it "reads a BINARY string as UTF-8, the way mmdc reads a file" do
        binary = with_slot(source, "\xFF")
          .force_encoding(Encoding::BINARY)
        decoded = with_slot(source, "\uFFFD")

        expect(outcome(binary)).to eq(outcome(decoded))
      end

      it "reads US-ASCII holding valid UTF-8, as `File.read` does in LANG=C" do
        ascii = with_slot(source, "é")
          .force_encoding(Encoding::US_ASCII)
        utf8 = with_slot(source, "é")

        expect(outcome(ascii)).to eq(outcome(utf8))
      end

      InvalidUtf8Helpers::BYTE_RUNS.each do |name, (bytes, replacements)|
        context "with #{name}" do
          let(:invalid) { with_slot(source, bytes) }
          let(:decoded) do
            outcome(with_slot(source, "\uFFFD" * replacements))
          end

          # The first two expectations are what make the third a comparison of
          # two renders rather than of two refusals; they pass without the
          # fix, so they stay in this example rather than standing alone.
          it "renders the same as the decoded source", :aggregate_failures do
            expect(invalid).not_to be_valid_encoding
            expect(decoded.first).to eq(:svg)
            expect(outcome(invalid)).to eq(decoded)
          end
        end
      end
    end
  end

  # `String#encode` leaves these tagged UTF-8 without checking what it
  # wrote, and the first regexp the engine ran on the result raised.
  %w[CESU-8 UTF8-DoCoMo UTF8-KDDI UTF8-SoftBank].each do |name|
    it "renders a #{name} string holding an invalid run" do
      source = with_slot("flowchart LR\n  A-->B\n%% §\n", "\xEF\xC2\x80")
        .force_encoding(name)

      expect(outcome(source).first).to eq(:svg)
    end
  end
end
