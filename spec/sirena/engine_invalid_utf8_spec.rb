# frozen_string_literal: true

require "spec_helper"

# Every source below carries a `§` where a label, title or comment sits. The
# spec swaps it for bytes that are not valid UTF-8 and holds the engine to the
# one thing mmdc does with them: node decodes the file as UTF-8, every invalid
# run becomes U+FFFD, and the diagram is drawn from the decoded text.
module EngineInvalidUtf8SpecHelpers
  # One minimal, valid source per registered type. `§` marks the slot the
  # invalid bytes go into; where a type's grammar refuses a non-ASCII word
  # (sankey) the slot is a `%%` comment, so the render still succeeds.
  SOURCES = {
    flowchart: "flowchart LR\n  A[§]-->B\n",
    sequence: "sequenceDiagram\n  Alice->>Bob: §\n",
    class_diagram: "classDiagram\n  class Animal {\n    +String name§\n  }\n",
    state_diagram: "stateDiagram-v2\n  [*] --> Still\n  Still --> Moving: §\n",
    er_diagram: "erDiagram\n  CUSTOMER ||--o{ ORDER : \"§\"\n",
    user_journey: "journey\n  title §\n  section Work\n    Task: 5: Me\n",
    pie: "pie title §\n  \"Dogs\" : 5\n  \"Cats\" : 3\n",
    gantt: "gantt\n  title §\n  dateFormat YYYY-MM-DD\n  section S\n  Task :a1, 2024-01-01, 3d\n",
    timeline: "timeline\n  title §\n  2002 : LinkedIn\n",
    quadrant: "quadrantChart\n  title §\n  x-axis Low --> High\n  y-axis Low --> High\n  A: [0.3, 0.6]\n",
    git_graph: "gitGraph\n  commit id: \"a§\"\n  commit\n",
    mindmap: "mindmap\n  root((§))\n    child\n",
    kanban: "kanban\n  todo[§]\n    t1[Task]\n",
    radar: "radar-beta\n  title §\n  axis a, b, c\n  curve k{1, 2, 3}\n",
    block: "block-beta\n  columns 2\n  a[\"§\"]\n  b\n",
    requirement: "requirementDiagram\n  requirement r {\n    id: 1\n    text: §\n    risk: high\n    verifymethod: test\n  }\n",
    xychart: "xychart-beta\n  title \"§\"\n  x-axis [a, b]\n  bar [1, 2]\n",
    architecture: "architecture-beta\n  service db(database)[§]\n",
    sankey: "sankey-beta\n%% §\nA,B,10\n",
    packet: "packet-beta\n  0-15: \"§\"\n",
    treemap: "treemap-beta\n  \"§\"\n    \"Leaf\": 10\n",
    c4: "C4Context\n  title §\n  Person(a, \"Alice\")\n",
    info: "%% §\ninfo\n",
    error: "%% §\nerror\n"
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
    "a code point past U+10FFFF" => ["\xF4\x90\x80\x80", 4]
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
end

RSpec.describe Sirena::Engine do
  it "renders a source with invalid bytes for every registered diagram type" do
    # A type registered without a row in SOURCES raises KeyError here, so a new
    # type cannot slip past this file's claim.
    rendered = Sirena::DiagramRegistry.types.to_h do |type|
      [type, EngineInvalidUtf8SpecHelpers.outcome(
        EngineInvalidUtf8SpecHelpers.with_slot(EngineInvalidUtf8SpecHelpers::SOURCES.fetch(type), "\xFF")
      ).first]
    end

    expect(rendered).to eq(Sirena::DiagramRegistry.types.to_h { |type| [type, :svg] })
  end

  EngineInvalidUtf8SpecHelpers::SOURCES.each do |type, source|
    describe "#render of #{type} with invalid UTF-8 bytes" do
      it "reads a BINARY string as UTF-8, the way mmdc reads a file" do
        binary = EngineInvalidUtf8SpecHelpers.with_slot(source, "\xFF").force_encoding(Encoding::BINARY)
        decoded = EngineInvalidUtf8SpecHelpers.with_slot(source, "\uFFFD")

        expect(EngineInvalidUtf8SpecHelpers.outcome(binary))
          .to eq(EngineInvalidUtf8SpecHelpers.outcome(decoded))
      end

      it "reads a US-ASCII string holding valid UTF-8, as `File.read` returns under LANG=C" do
        ascii = EngineInvalidUtf8SpecHelpers.with_slot(source, "é").force_encoding(Encoding::US_ASCII)
        utf8 = EngineInvalidUtf8SpecHelpers.with_slot(source, "é")

        expect(EngineInvalidUtf8SpecHelpers.outcome(ascii))
          .to eq(EngineInvalidUtf8SpecHelpers.outcome(utf8))
      end

      EngineInvalidUtf8SpecHelpers::BYTE_RUNS.each do |name, (bytes, replacements)|
        it "renders #{name} as #{replacements} U+FFFD, the way mmdc decodes it" do
          invalid = EngineInvalidUtf8SpecHelpers.with_slot(source, bytes)
          decoded = EngineInvalidUtf8SpecHelpers.outcome(
            EngineInvalidUtf8SpecHelpers.with_slot(source, "\uFFFD" * replacements)
          )

          expect(invalid).not_to be_valid_encoding
          # The first expectation is what makes the second a comparison of two
          # renders rather than of two refusals.
          expect(decoded.first).to eq(:svg)
          expect(EngineInvalidUtf8SpecHelpers.outcome(invalid)).to eq(decoded)
        end
      end
    end
  end

  # `String#encode` leaves these tagged UTF-8 without checking what it
  # wrote, and the first regexp the engine ran on the result raised.
  %w[CESU-8 UTF8-DoCoMo UTF8-KDDI UTF8-SoftBank].each do |name|
    it "renders a #{name} string holding an invalid run" do
      source = EngineInvalidUtf8SpecHelpers.with_slot("flowchart LR\n  A-->B\n%% §\n", "\xEF\xC2\x80")
        .force_encoding(name)

      expect(EngineInvalidUtf8SpecHelpers.outcome(source).first).to eq(:svg)
    end
  end
end
