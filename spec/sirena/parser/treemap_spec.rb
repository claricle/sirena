# frozen_string_literal: true

require 'spec_helper'
require 'sirena/parser/treemap'

RSpec.describe Sirena::Parser::TreemapParser do
  let(:parser) { described_class.new }

  describe '#parse' do
    context 'with basic treemap syntax' do
      it 'parses simple treemap with single node' do
        source = <<~MERMAID
          treemap
          "Root"
            "Child": 100
        MERMAID

        diagram = parser.parse(source)

        expect(diagram).to be_a(Sirena::Diagram::TreemapDiagram)
        expect(diagram.root_nodes.length).to eq(1)
        expect(diagram.root_nodes.first.label).to eq('Root')
        expect(diagram.root_nodes.first.children.length).to eq(1)
        expect(diagram.root_nodes.first.children.first.label).to eq('Child')
        expect(diagram.root_nodes.first.children.first.value).to eq(100.0)
      end

      it 'parses treemap-beta keyword' do
        source = <<~MERMAID
          treemap-beta
          "Node": 50
        MERMAID

        diagram = parser.parse(source)

        expect(diagram).to be_a(Sirena::Diagram::TreemapDiagram)
        expect(diagram.root_nodes.length).to eq(1)
      end

      it 'parses multiple root nodes' do
        source = <<~MERMAID
          treemap
          "Section 1"
            "Leaf 1.1": 12
          "Section 2"
            "Leaf 2.1": 20
        MERMAID

        diagram = parser.parse(source)

        expect(diagram.root_nodes.length).to eq(2)
        expect(diagram.root_nodes[0].label).to eq('Section 1')
        expect(diagram.root_nodes[1].label).to eq('Section 2')
      end
    end

    context 'with hierarchical structure' do
      it 'parses nested nodes' do
        source = <<~MERMAID
          treemap-beta
          "Level 1"
              "Level 2"
                  "Level 3": 10
        MERMAID

        diagram = parser.parse(source)

        level1 = diagram.root_nodes.first
        expect(level1.label).to eq('Level 1')
        expect(level1.children.length).to eq(1)

        level2 = level1.children.first
        expect(level2.label).to eq('Level 2')
        expect(level2.children.length).to eq(1)

        level3 = level2.children.first
        expect(level3.label).to eq('Level 3')
        expect(level3.value).to eq(10.0)
      end

      it 'parses complex hierarchy' do
        source = <<~MERMAID
          treemap-beta
          "Level 1"
              "Level 2A"
                  "Level 3A": 10
                  "Level 3B": 15
              "Level 2B"
                  "Level 3C": 20
        MERMAID

        diagram = parser.parse(source)

        level1 = diagram.root_nodes.first
        expect(level1.children.length).to eq(2)
        expect(level1.children[0].children.length).to eq(2)
        expect(level1.children[1].children.length).to eq(1)
      end
    end

    context 'with value separators' do
      it 'parses values with colon separator' do
        source = <<~MERMAID
          treemap
          "Root"
            "Child": 200
        MERMAID

        diagram = parser.parse(source)
        child = diagram.root_nodes.first.children.first
        expect(child.value).to eq(200.0)
      end

      it 'parses values with comma separator' do
        source = <<~MERMAID
          treemap
          "Root"
            "Child1" , 100
        MERMAID

        diagram = parser.parse(source)
        child = diagram.root_nodes.first.children.first
        expect(child.value).to eq(100.0)
      end
    end

    context 'with CSS classes' do
      it 'parses nodes with CSS class' do
        source = <<~MERMAID
          treemap-beta
          "Main"
              "B":::important
                  "B1": 10
        MERMAID

        diagram = parser.parse(source)
        node_b = diagram.root_nodes.first.children.first
        expect(node_b.css_class).to eq('important')
      end

      it 'parses leaf nodes with value and CSS class' do
        source = <<~MERMAID
          treemap-beta
          "Main"
              "C": 5:::secondary
        MERMAID

        diagram = parser.parse(source)
        node_c = diagram.root_nodes.first.children.first
        expect(node_c.value).to eq(5.0)
        expect(node_c.css_class).to eq('secondary')
      end
    end

    context 'with class definitions' do
      it 'parses classDef statements' do
        source = <<~MERMAID
          treemap-beta
          "Main"
              "A": 20

          classDef important fill:#f96,stroke:#333,stroke-width:2px;
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.class_defs).to have_key('important')
        expect(diagram.class_defs['important']).to include('fill:#f96')
      end

      it 'parses multiple classDef statements' do
        source = <<~MERMAID
          treemap-beta
          "Main"
              "A": 20

          classDef important fill:#f96,stroke:#333,stroke-width:2px;
          classDef secondary fill:#6cf,stroke:#333,stroke-dasharray:5 5;
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.class_defs.keys).to include('important', 'secondary')
      end
    end

    context 'with metadata' do
      it 'parses title' do
        source = <<~MERMAID
          treemap
          title My Treemap Diagram
          "Root"
            "Child": 100
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.title).to eq('My Treemap Diagram')
      end

      it 'parses accessibility metadata' do
        source = <<~MERMAID
          treemap
          title My Treemap
          accTitle: Accessible Title
          accDescr: This is description
          "Root"
            "Child": 100
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.title).to eq('My Treemap')
        # Note: accTitle and accDescr are parsed but not currently stored
      end
    end

    context 'with comments' do
      it 'ignores comment lines' do
        source = <<~MERMAID
          treemap
          %% This is a comment
          "Root"
            "Child": 100 %% inline comment
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root_nodes.length).to eq(1)
      end
    end

    context 'with node calculations' do
      it 'calculates total values correctly' do
        source = <<~MERMAID
          treemap
          "Root"
            "Child1": 100
            "Child2": 200
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.total_value).to eq(300.0)
      end

      it 'calculates node depth correctly' do
        source = <<~MERMAID
          treemap
          "Level 1"
              "Level 2"
                  "Level 3": 10
        MERMAID

        diagram = parser.parse(source)
        level1 = diagram.root_nodes.first
        level2 = level1.children.first
        level3 = level2.children.first

        expect(level1.depth).to eq(0)
        expect(level2.depth).to eq(1)
        expect(level3.depth).to eq(2)
      end
    end

    context 'with edge cases' do
      it 'handles empty labels' do
        source = <<~MERMAID
          treemap
          ""
            "Child": 100
        MERMAID

        diagram = parser.parse(source)
        expect(diagram.root_nodes.first.label).to eq('')
      end

      it 'handles long labels' do
        long_label = 'This is a very long item name that should wrap to the next line when rendered in the treemap diagram'
        source = <<~MERMAID
          treemap-beta
          "Main"
              "#{long_label}": 50
        MERMAID

        diagram = parser.parse(source)
        child = diagram.root_nodes.first.children.first
        expect(child.label).to eq(long_label)
      end

      it 'handles decimal values' do
        source = <<~MERMAID
          treemap
          "Root"
            "Child": 123.45
        MERMAID

        diagram = parser.parse(source)
        child = diagram.root_nodes.first.children.first
        expect(child.value).to eq(123.45)
      end
    end

    context 'with fixtures' do
      it 'parses fixture 001' do
        source = File.read('spec/mermaid/treemap/001_rendering_treemap_spec_treemap_0.mmd')
        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::TreemapDiagram)
      end

      it 'parses fixture 002' do
        source = File.read('spec/mermaid/treemap/002_rendering_treemap_spec_treemap_1.mmd')
        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::TreemapDiagram)
      end

      it 'parses fixture 008 (example)' do
        source = File.read('spec/mermaid/treemap/008_example_treemap_7.mmd')
        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::TreemapDiagram)
        expect(diagram.root_nodes.length).to eq(2)
      end

      it 'parses fixture 010 (with metadata)' do
        source = File.read('spec/mermaid/treemap/010_parsertest_treemap_test_9.mmd')
        diagram = parser.parse(source)
        expect(diagram).to be_a(Sirena::Diagram::TreemapDiagram)
        expect(diagram.title).to eq('My Treemap Diagram')
      end
    end
  end
end