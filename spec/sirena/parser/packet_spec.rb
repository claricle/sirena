# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/packet"

RSpec.describe Sirena::Parser::Packet do
  let(:parser) { described_class.new }

  describe "#parse" do
    context "with minimal packet" do
      it "parses packet-beta keyword" do
        source = "packet-beta\n"

        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::Packet)
        expect(diagram.fields).to be_empty
      end
    end

    context "with title" do
      it "parses title" do
        source = <<~MERMAID
          packet-beta
            title Hello world
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.title).to eq("Hello world")
      end
    end

    context "with fields" do
      it "parses single field" do
        source = <<~MERMAID
          packet-beta
            title Hello world
            0-10: "hello"
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.fields.size).to eq(1)

        field = diagram.fields.first
        expect(field.bit_start).to eq(0)
        expect(field.bit_end).to eq(10)
        expect(field.label).to eq("hello")
      end

      it "parses multiple fields" do
        source = <<~MERMAID
          packet-beta
            0-7: "Source Port"
            8-15: "Destination Port"
            16-31: "Sequence Number"
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.fields.size).to eq(3)

        expect(diagram.fields[0].label).to eq("Source Port")
        expect(diagram.fields[0].bit_start).to eq(0)
        expect(diagram.fields[0].bit_end).to eq(7)

        expect(diagram.fields[1].label).to eq("Destination Port")
        expect(diagram.fields[1].bit_start).to eq(8)
        expect(diagram.fields[1].bit_end).to eq(15)

        expect(diagram.fields[2].label).to eq("Sequence Number")
        expect(diagram.fields[2].bit_start).to eq(16)
        expect(diagram.fields[2].bit_end).to eq(31)
      end

      it "parses fields with empty labels" do
        source = <<~MERMAID
          packet-beta
            0-7: ""
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.fields.size).to eq(1)
        expect(diagram.fields.first.label).to eq("")
      end
    end

    context "with comments" do
      it "ignores comments" do
        source = <<~MERMAID
          packet-beta
            %% This is a comment
            title My Packet
            %% Another comment
            0-10: "hello"
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.title).to eq("My Packet")
        expect(diagram.fields.size).to eq(1)
      end

      it "reads a body of only comments and blank lines as empty" do
        diagram = parser.parse("packet-beta\n%% only a comment\n\n")

        expect([diagram.title, diagram.fields]).to eq([nil, []])
      end
    end

    context "with fixture files" do
      let(:fixtures_dir) { File.join(__dir__, "../../mermaid/packet") }

      it "parses 001_rendering_packet_spec_packet_0.mmd" do
        source = File.read(File.join(fixtures_dir, "001_rendering_packet_spec_packet_0.mmd"))

        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::Packet)
        expect(diagram.title).to eq("Hello world")
        expect(diagram.fields.size).to eq(1)
        expect(diagram.fields.first.label).to eq("hello")
      end

      it "parses 002_parser_should_handle_a_packet-beta_definition_1.mmd" do
        source = File.read(File.join(fixtures_dir, "002_parser_should_handle_a_packet-beta_definition_1.mmd"))

        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::Packet)
      end

      it "parses 003_parsertest_packet_test_2.mmd" do
        source = File.read(File.join(fixtures_dir, "003_parsertest_packet_test_2.mmd"))

        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::Packet)
      end

      it "parses 004_spec_mermaidapi_spec_3.mmd" do
        source = File.read(File.join(fixtures_dir, "004_spec_mermaidapi_spec_3.mmd"))

        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::Packet)
      end
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
