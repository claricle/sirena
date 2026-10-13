# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser::Block, :aggregate_failures do
  let(:parser) { described_class.new }

  context "with basic block diagram" do
    let(:source) do
      <<~MERMAID
        block-beta
          A
          B
      MERMAID
    end

    context "when parsing successfully" do
      let(:diagram) { parser.parse(source) }

      it "retains diagram" do
        expect(diagram).to be_a(Sirena::Diagram::Block)
      end

      it "retains diagram.blocks.length" do
        expect(diagram.blocks.length).to eq(2)
      end

      it "retains diagram.blocks.first.id" do
        expect(diagram.blocks.first.id).to eq("A")
      end

      it "retains diagram.blocks.last.id" do
        expect(diagram.blocks.last.id).to eq("B")
      end
    end
  end

  context "with columns statement" do
    let(:source) do
      <<~MERMAID
        block-beta
          columns 2
          A
          B
      MERMAID
    end

    context "when parsing columns value" do
      let(:diagram) { parser.parse(source) }

      it "retains diagram.columns" do
        expect(diagram.columns).to eq(2)
      end

      it "retains diagram.blocks.length" do
        expect(diagram.blocks.length).to eq(2)
      end
    end
  end

  context "with block labels" do
    let(:source) do
      <<~MERMAID
        block-beta
          A["Block A"]
          B["Block B"]
      MERMAID
    end

    context "when parsing block labels" do
      let(:diagram) { parser.parse(source) }

      it "retains diagram.blocks.first.label" do
        expect(diagram.blocks.first.label).to eq("Block A")
      end

      it "retains diagram.blocks.last.label" do
        expect(diagram.blocks.last.label).to eq("Block B")
      end
    end
  end

  context "with block widths" do
    let(:source) do
      <<~MERMAID
        block-beta
          columns 3
          A:2
          B:1
      MERMAID
    end

    context "when parsing block widths" do
      let(:diagram) { parser.parse(source) }

      it "retains diagram.blocks.first.width" do
        expect(diagram.blocks.first.width).to eq(2)
      end

      it "retains diagram.blocks.last.width" do
        expect(diagram.blocks.last.width).to eq(1)
      end
    end
  end

  context "with connections" do
    let(:source) do
      <<~MERMAID
        block-beta
          A
          B
          A --> B
      MERMAID
    end

    context "when parsing connections" do
      let(:diagram) { parser.parse(source) }

      it "retains diagram.connections.length" do
        expect(diagram.connections.length).to eq(1)
      end

      it "retains diagram.connections.first.from" do
        expect(diagram.connections.first.from).to eq("A")
      end

      it "retains diagram.connections.first.to" do
        expect(diagram.connections.first.to).to eq("B")
      end

      it "retains diagram.connections.first.connection_type" do
        expect(diagram.connections.first.connection_type).to eq("arrow")
      end
    end
  end

  context "with compound blocks" do
    let(:source) do
      <<~MERMAID
        block-beta
          block:ID
            A
            B
          end
      MERMAID
    end

    context "when parsing compound blocks" do
      let(:diagram) { parser.parse(source) }

      it "retains diagram.blocks.length" do
        expect(diagram.blocks.length).to eq(1)
      end

      it "retains compound.compound" do
        compound = diagram.blocks.first

        expect(compound.compound?).to be true
      end

      it "retains compound.id" do
        compound = diagram.blocks.first

        expect(compound.id).to eq("ID")
      end

      it "retains compound.children.length" do
        compound = diagram.blocks.first

        expect(compound.children.length).to eq(2)
      end
    end
  end

  context "with space blocks" do
    let(:source) do
      <<~MERMAID
        block-beta
          columns 2
          A
          space
          B
      MERMAID
    end

    context "when parsing space placeholders" do
      let(:diagram) { parser.parse(source) }

      it "retains diagram.blocks.length" do
        expect(diagram.blocks.length).to eq(3)
      end

      it "retains diagram.blocks 1 .space" do
        expect(diagram.blocks[1].space?).to be true
      end
    end
  end

  context "with circle shape" do
    let(:source) do
      <<~MERMAID
        block-beta
          A(("Circle"))
      MERMAID
    end

    context "when parsing circle shape" do
      let(:diagram) { parser.parse(source) }

      it "retains diagram.blocks.first.shape" do
        expect(diagram.blocks.first.shape).to eq("circle")
      end

      it "retains diagram.blocks.first.label" do
        expect(diagram.blocks.first.label).to eq("Circle")
      end
    end
  end
end
