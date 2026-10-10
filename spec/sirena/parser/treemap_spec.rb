# frozen_string_literal: true

require "spec_helper"
require "sirena/parser/treemap"

RSpec.describe Sirena::Parser::Treemap do
  subject(:diagram) { parser.parse(source) }

  let(:parser) { described_class.new }

  describe "#parse" do
    context "with basic syntax and a single child" do
      let(:source) do
        <<~MERMAID
          treemap
          "Root"
            "Child": 100
        MERMAID
      end

      let(:child) { have_attributes(label: "Child", value: 100.0) }
      let(:root) { have_attributes(label: "Root", children: [child]) }

      it "parses simple treemap with single node" do
        expect(diagram).to be_a(Sirena::Diagram::Treemap)
          .and have_attributes(root_nodes: [root])
      end
    end

    context "with the treemap-beta keyword" do
      let(:source) do
        <<~MERMAID
          treemap-beta
          "Node": 50
        MERMAID
      end

      it "parses treemap-beta keyword" do
        expect(diagram).to be_a(Sirena::Diagram::Treemap)
          .and have_attributes(root_nodes: contain_exactly(anything))
      end
    end

    context "with multiple roots" do
      let(:source) do
        <<~MERMAID
          treemap
          "Section 1"
            "Leaf 1.1": 12
          "Section 2"
            "Leaf 2.1": 20
        MERMAID
      end

      let(:expected_roots) do
        [
          have_attributes(label: "Section 1"),
          have_attributes(label: "Section 2"),
        ]
      end

      it "parses multiple root nodes" do
        expect(diagram.root_nodes).to match(expected_roots)
      end
    end

    context "with one node at each hierarchy level" do
      let(:source) do
        <<~MERMAID
          treemap-beta
          "Level 1"
              "Level 2"
                  "Level 3": 10
        MERMAID
      end

      let(:leaf_matcher) { have_attributes(label: "Level 3", value: 10.0) }
      let(:branch_matcher) do
        have_attributes(label: "Level 2", children: [leaf_matcher])
      end
      let(:root_matcher) do
        have_attributes(label: "Level 1", children: [branch_matcher])
      end

      it "parses nested nodes" do
        expect(diagram).to have_attributes(root_nodes: [root_matcher])
      end
    end

    context "with a branching hierarchy" do
      let(:source) do
        <<~MERMAID
          treemap-beta
          "Level 1"
              "Level 2A"
                  "Level 3A": 10
                  "Level 3B": 15
              "Level 2B"
                  "Level 3C": 20
        MERMAID
      end

      let(:wide_branch) do
        have_attributes(children: contain_exactly(anything, anything))
      end
      let(:narrow_branch) do
        have_attributes(children: contain_exactly(anything))
      end
      let(:root_matcher) do
        have_attributes(children: [wide_branch, narrow_branch])
      end

      it "parses complex hierarchy" do
        expect(diagram).to have_attributes(root_nodes: [root_matcher])
      end
    end

    context "with a colon value separator" do
      let(:source) do
        <<~MERMAID
          treemap
          "Root"
            "Child": 200
        MERMAID
      end

      it "parses values with colon separator" do
        expect(diagram.root_nodes.first.children.first)
          .to have_attributes(value: 200.0)
      end
    end

    context "with a comma" do
      let(:source) do
        <<~MERMAID
          treemap
          "Root"
            "Child1" , 100
        MERMAID
      end

      it "parses values with comma separator" do
        expect(diagram.root_nodes.first.children.first)
          .to have_attributes(value: 100.0)
      end
    end

    context "with a CSS class on a parent node" do
      let(:source) do
        <<~MERMAID
          treemap-beta
          "Main"
              "B":::important
                  "B1": 10
        MERMAID
      end

      it "parses nodes with CSS class" do
        expect(diagram.root_nodes.first.children.first)
          .to have_attributes(css_class: "important")
      end
    end

    context "with a class on a leaf node" do
      let(:source) do
        <<~MERMAID
          treemap-beta
          "Main"
              "C": 5:::secondary
        MERMAID
      end

      it "parses leaf nodes with value and CSS class" do
        expect(diagram.root_nodes.first.children.first).to have_attributes(
          value: 5.0, css_class: "secondary",
        )
      end
    end

    context "with one class definition" do
      let(:source) do
        <<~MERMAID
          treemap-beta
          "Main"
              "A": 20

          classDef important fill:#f96,stroke:#333,stroke-width:2px;
        MERMAID
      end

      it "parses classDef statements" do
        expect(diagram.class_defs).to include(
          "important" => include("fill:#f96"),
        )
      end
    end

    context "with multiple definitions" do
      let(:source) do
        <<~MERMAID
          treemap-beta
          "Main"
              "A": 20

          classDef important fill:#f96,stroke:#333,stroke-width:2px;
          classDef secondary fill:#6cf,stroke:#333,stroke-dasharray:5 5;
        MERMAID
      end

      it "parses multiple classDef statements" do
        expect(diagram.class_defs.keys).to include("important", "secondary")
      end
    end

    context "with title metadata" do
      let(:source) do
        <<~MERMAID
          treemap
          title My Treemap Diagram
          "Root"
            "Child": 100
        MERMAID
      end

      it "parses title" do
        expect(diagram).to have_attributes(title: "My Treemap Diagram")
      end
    end

    context "with accessibility metadata" do
      let(:source) do
        <<~MERMAID
          treemap
          title My Treemap
          accTitle: Accessible Title
          accDescr: This is description
          "Root"
            "Child": 100
        MERMAID
      end

      # accTitle and accDescr are parsed but not currently stored.
      it "parses accessibility metadata" do
        expect(diagram).to have_attributes(title: "My Treemap")
      end
    end

    context "with comments" do
      let(:source) do
        <<~MERMAID
          treemap
          %% This is a comment
          "Root"
            "Child": 100 %% inline comment
        MERMAID
      end

      it "ignores comment lines" do
        expect(diagram.root_nodes).to contain_exactly(anything)
      end
    end

    context "when calculating sibling values" do
      let(:source) do
        <<~MERMAID
          treemap
          "Root"
            "Child1": 100
            "Child2": 200
        MERMAID
      end

      it "calculates total values correctly" do
        expect(diagram).to have_attributes(total_value: 300.0)
      end
    end

    context "with nested nodes" do
      let(:source) do
        <<~MERMAID
          treemap
          "Level 1"
              "Level 2"
                  "Level 3": 10
        MERMAID
      end

      let(:leaf_matcher) { have_attributes(depth: 2) }
      let(:branch_matcher) do
        have_attributes(depth: 1, children: [leaf_matcher])
      end
      let(:root_matcher) do
        have_attributes(depth: 0, children: [branch_matcher])
      end

      it "calculates node depth correctly" do
        expect(diagram).to have_attributes(root_nodes: [root_matcher])
      end
    end

    context "with an empty label" do
      let(:source) do
        <<~MERMAID
          treemap
          ""
            "Child": 100
        MERMAID
      end

      it "handles empty labels" do
        expect(diagram.root_nodes.first).to have_attributes(label: "")
      end
    end

    context "with a long label" do
      let(:long_label) do
        "This is a very long item name that should wrap to the next line " \
          "when rendered in the treemap diagram"
      end

      let(:source) do
        <<~MERMAID
          treemap-beta
          "Main"
              "#{long_label}": 50
        MERMAID
      end

      it "handles long labels" do
        expect(diagram.root_nodes.first.children.first)
          .to have_attributes(label: long_label)
      end
    end

    context "with a decimal value" do
      let(:source) do
        <<~MERMAID
          treemap
          "Root"
            "Child": 123.45
        MERMAID
      end

      it "handles decimal values" do
        expect(diagram.root_nodes.first.children.first)
          .to have_attributes(value: 123.45)
      end
    end

    context "with fixture 001" do
      let(:source) do
        File.read(
          "spec/mermaid/treemap/001_rendering_treemap_spec_treemap_0.mmd",
        )
      end

      it "parses fixture 001" do
        expect(diagram).to be_a(Sirena::Diagram::Treemap)
      end
    end

    context "with fixture 002" do
      let(:source) do
        File.read(
          "spec/mermaid/treemap/002_rendering_treemap_spec_treemap_1.mmd",
        )
      end

      it "parses fixture 002" do
        expect(diagram).to be_a(Sirena::Diagram::Treemap)
      end
    end

    context "with fixture 008" do
      let(:source) do
        File.read("spec/mermaid/treemap/008_example_treemap_7.mmd")
      end

      it "parses fixture 008 (example)" do
        expect(diagram).to be_a(Sirena::Diagram::Treemap)
          .and have_attributes(root_nodes: contain_exactly(anything, anything))
      end
    end

    context "with fixture 010" do
      let(:source) do
        File.read(
          "spec/mermaid/treemap/010_parsertest_treemap_test_9.mmd",
        )
      end

      it "parses fixture 010 (with metadata)" do
        expect(diagram).to be_a(Sirena::Diagram::Treemap)
          .and have_attributes(title: "My Treemap Diagram")
      end
    end
  end
end
