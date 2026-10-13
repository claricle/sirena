# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/sequence"
require "sirena/notation/mermaid/ir_adapters/sequence"

# `create participant` and `@{ "type": ... }` change how mmdc draws a
# participant, so both must reach layout: parser -> diagram -> IR.
RSpec.describe Sirena::Parser::Sequence, :aggregate_failures do
  let(:parser) { described_class.new }

  def parse(body)
    parser.parse("sequenceDiagram\n#{body}\n")
  end

  def by_id(diagram, id)
    diagram.participants.find { |participant| participant.id == id }
  end

  describe "create" do
    let(:diagram) do
      parse("participant A\ncreate participant B\nA->>B: m\n" \
            "create actor C\nA->>C: m")
    end

    it "marks only created participants" do
      expect(diagram.participants.map(&:created))
        .to eq([false, true, true])
    end

    it "keeps the created flag in the IR" do
      ir = Sirena::Notation::Mermaid::IRAdapters::Sequence.call(diagram)

      created = ir.nodes.select { |node| node.role == "participant_created" }
      expect(created.map(&:parent_id)).to eq(%w[B C])
    end
  end

  describe "@{ type }" do
    context "when reads the type from JSON and YAML-style payloads" do
      let(:diagram) do
        parse(
          "participant A@{\"type\":\"boundary\"}\n" \
          "participant B@{ type: Database }\n" \
          "participant C@{ 'type' : 'queue' } as See\nparticipant D",
        )
      end

      it "retains diagram.participants.map shape_type" do
        expect(diagram.participants.map(&:shape_type))
          .to eq(["boundary", "database", "queue", nil])
      end
    end

    it "applies to a created participant too" do
      diagram = parse("participant A\n" \
                      "create participant B@{\"type\":\"entity\"}\n" \
                      "A->>B: m")

      expect(by_id(diagram, "B"))
        .to have_attributes(created: true, shape_type: "entity")
    end

    it "keeps the type in the IR" do
      ir = Sirena::Notation::Mermaid::IRAdapters::Sequence.call(
        parse("participant A@{\"type\":\"control\"}\nA->>A: m"),
      )

      shape = ir.nodes.find { |node| node.role == "participant_shape" }
      expect(shape).to have_attributes(label: "control", parent_id: "A")
    end
  end
end
