# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/packet"

RSpec.describe Sirena::Parser::Packet do
  let(:parser) { described_class.new }

  context "with minimal packet" do
    context "when parsing packet-beta keyword" do
      let(:source) { "packet-beta\n" }
      let(:diagram) { parser.parse(source) }

      it "retains diagram" do
        expect(diagram).to be_a(Sirena::Diagram::Packet)
      end

      it "retains diagram.fields" do
        expect(diagram.fields).to be_empty
      end
    end
  end

  context "with title" do
    context "when parsing title" do
      let(:source) do
        <<~MERMAID
          packet-beta
            title Hello world
        MERMAID
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.title" do
        expect(diagram.title).to eq("Hello world")
      end
    end
  end

  context "with fields" do
    context "when parsing single field" do
      let(:source) do
        <<~MERMAID
          packet-beta
            title Hello world
            0-10: "hello"
        MERMAID
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.fields.size" do
        expect(diagram.fields.size).to eq(1)
      end

      it "retains field.bit_start" do
        field = diagram.fields.first

        expect(field.bit_start).to eq(0)
      end

      it "retains field.bit_end" do
        field = diagram.fields.first

        expect(field.bit_end).to eq(10)
      end

      it "retains field.label" do
        field = diagram.fields.first

        expect(field.label).to eq("hello")
      end
    end

    context "when parsing multiple fields" do
      let(:source) do
        <<~MERMAID
          packet-beta
            0-7: "Source Port"
            8-15: "Destination Port"
            16-31: "Sequence Number"
        MERMAID
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.fields.size" do
        expect(diagram.fields.size).to eq(3)
      end

      it "retains diagram.fields 0 .label" do
        expect(diagram.fields[0].label).to eq("Source Port")
      end

      it "retains diagram.fields 0 .bit_start" do
        expect(diagram.fields[0].bit_start).to eq(0)
      end

      it "retains diagram.fields 0 .bit_end" do
        expect(diagram.fields[0].bit_end).to eq(7)
      end

      it "retains diagram.fields 1 .label" do
        expect(diagram.fields[1].label).to eq("Destination Port")
      end

      it "retains diagram.fields 1 .bit_start" do
        expect(diagram.fields[1].bit_start).to eq(8)
      end

      it "retains diagram.fields 1 .bit_end" do
        expect(diagram.fields[1].bit_end).to eq(15)
      end

      it "retains diagram.fields 2 .label" do
        expect(diagram.fields[2].label).to eq("Sequence Number")
      end

      it "retains diagram.fields 2 .bit_start" do
        expect(diagram.fields[2].bit_start).to eq(16)
      end

      it "retains diagram.fields 2 .bit_end" do
        expect(diagram.fields[2].bit_end).to eq(31)
      end
    end

    context "when parsing fields with empty labels" do
      let(:source) do
        <<~MERMAID
          packet-beta
            0-7: ""
        MERMAID
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.fields.size" do
        expect(diagram.fields.size).to eq(1)
      end

      it "retains diagram.fields.first.label" do
        expect(diagram.fields.first.label).to eq("")
      end
    end
  end

  context "with comments" do
    context "when ignores comments" do
      let(:source) do
        <<~MERMAID
          packet-beta
            %% This is a comment
            title My Packet
            %% Another comment
            0-10: "hello"
        MERMAID
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram.title" do
        expect(diagram.title).to eq("My Packet")
      end

      it "retains diagram.fields.size" do
        expect(diagram.fields.size).to eq(1)
      end
    end

    it "reads a body of only comments and blank lines as empty" do
      diagram = parser.parse("packet-beta\n%% only a comment\n\n")

      expect([diagram.title, diagram.fields]).to eq([nil, []])
    end
  end

  context "with fixture files" do
    let(:fixtures_dir) { File.join(__dir__, "../../mermaid/packet") }
    let(:packet_beta_fixture) do
      "should_handle_a_packet_beta_definition-5a378b93.mmd"
    end

    context "when parsing packet_spec-d819b9e5.mmd" do
      let(:source) do
        File.read(File.join(fixtures_dir,
                            "packet_spec-d819b9e5.mmd"))
      end
      let(:diagram) { parser.parse(source) }

      it "retains diagram" do
        expect(diagram).to be_a(Sirena::Diagram::Packet)
      end

      it "retains diagram.title" do
        expect(diagram.title).to eq("Hello world")
      end

      it "retains diagram.fields.size" do
        expect(diagram.fields.size).to eq(1)
      end

      it "retains diagram.fields.first.label" do
        expect(diagram.fields.first.label).to eq("hello")
      end
    end

    it "parses should_handle_a_packet_beta_definition-5a378b93.mmd" do
      source = File.read(File.join(fixtures_dir, packet_beta_fixture))

      diagram = parser.parse(source)
      expect(diagram).to be_a(Sirena::Diagram::Packet)
    end

    it "parses packet_test-bc44629d.mmd" do
      source = File.read(File.join(fixtures_dir,
                                   "packet_test-bc44629d.mmd"))

      diagram = parser.parse(source)
      expect(diagram).to be_a(Sirena::Diagram::Packet)
    end

    it "parses mermaidapi_spec-a11cf9f6.mmd" do
      source = File.read(File.join(fixtures_dir,
                                   "mermaidapi_spec-a11cf9f6.mmd"))

      diagram = parser.parse(source)
      expect(diagram).to be_a(Sirena::Diagram::Packet)
    end
  end

  describe "packet geometry" do
    it "reports one row for an empty diagram" do
      diagram = Sirena::Diagram::Packet.new

      expect([diagram.max_bit_position, diagram.row_count]).to eq([0, 1])
    end

    it "reports extents from the furthest field" do
      diagram = Sirena::Diagram::Packet.new
      diagram.add_field(Sirena::Diagram::PacketField.new(0, 31, "first"))
      diagram.add_field(Sirena::Diagram::PacketField.new(32, 47, "second"))

      expect([diagram.max_bit_position, diagram.row_count]).to eq([47, 2])
    end

    it "reports geometry for a field spanning two rows" do
      field = Sirena::Diagram::PacketField.new(28, 35, "split")

      geometry = [field.size, field.start_row, field.end_row, field.spans_rows?,
                  field.start_bit_in_row, field.end_bit_in_row]
      expect(geometry).to eq([8, 0, 1, true, 28, 3])
    end

    it "reports a field contained within one row" do
      field = Sirena::Diagram::PacketField.new(8, 15, "whole")

      expect(field.spans_rows?).to be(false)
    end
  end
end
