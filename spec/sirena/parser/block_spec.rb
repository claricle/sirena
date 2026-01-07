# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Parser::BlockParser do
  let(:parser) { described_class.new }

  describe '#parse' do
    context 'with basic block diagram' do
      let(:source) do
        <<~MERMAID
          block-beta
            A
            B
        MERMAID
      end

      it 'parses successfully' do
        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::BlockDiagram)
        expect(diagram.blocks.length).to eq(2)
        expect(diagram.blocks.first.id).to eq('A')
        expect(diagram.blocks.last.id).to eq('B')
      end
    end

    context 'with columns statement' do
      let(:source) do
        <<~MERMAID
          block-beta
            columns 2
            A
            B
        MERMAID
      end

      it 'parses columns value' do
        diagram = parser.parse(source)
        expect(diagram.columns).to eq(2)
        expect(diagram.blocks.length).to eq(2)
      end
    end

    context 'with block labels' do
      let(:source) do
        <<~MERMAID
          block-beta
            A["Block A"]
            B["Block B"]
        MERMAID
      end

      it 'parses block labels' do
        diagram = parser.parse(source)
        expect(diagram.blocks.first.label).to eq('Block A')
        expect(diagram.blocks.last.label).to eq('Block B')
      end
    end

    context 'with block widths' do
      let(:source) do
        <<~MERMAID
          block-beta
            columns 3
            A:2
            B:1
        MERMAID
      end

      it 'parses block widths' do
        diagram = parser.parse(source)
        expect(diagram.blocks.first.width).to eq(2)
        expect(diagram.blocks.last.width).to eq(1)
      end
    end

    context 'with connections' do
      let(:source) do
        <<~MERMAID
          block-beta
            A
            B
            A --> B
        MERMAID
      end

      it 'parses connections' do
        diagram = parser.parse(source)
        expect(diagram.connections.length).to eq(1)
        expect(diagram.connections.first.from).to eq('A')
        expect(diagram.connections.first.to).to eq('B')
        expect(diagram.connections.first.connection_type).to eq('arrow')
      end
    end

    context 'with compound blocks' do
      let(:source) do
        <<~MERMAID
          block-beta
            block:ID
              A
              B
            end
        MERMAID
      end

      it 'parses compound blocks' do
        diagram = parser.parse(source)
        expect(diagram.blocks.length).to eq(1)
        compound = diagram.blocks.first
        expect(compound.compound?).to be true
        expect(compound.id).to eq('ID')
        expect(compound.children.length).to eq(2)
      end
    end

    context 'with space blocks' do
      let(:source) do
        <<~MERMAID
          block-beta
            columns 2
            A
            space
            B
        MERMAID
      end

      it 'parses space placeholders' do
        diagram = parser.parse(source)
        expect(diagram.blocks.length).to eq(3)
        expect(diagram.blocks[1].space?).to be true
      end
    end

    context 'with circle shape' do
      let(:source) do
        <<~MERMAID
          block-beta
            A(("Circle"))
        MERMAID
      end

      it 'parses circle shape' do
        diagram = parser.parse(source)
        expect(diagram.blocks.first.shape).to eq('circle')
        expect(diagram.blocks.first.label).to eq('Circle')
      end
    end
  end
end