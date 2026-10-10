# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/treemap"
require "sirena/notation/mermaid/ir_adapters/treemap"

RSpec.describe Sirena::Layout::Treemap do
  subject(:scene) { described_class.new.call(diagram) }

  let(:diagram) { Sirena::Diagram::Treemap.new }

  it "keeps empty shared data IR renderable like the private model" do
    data = Sirena::Notation::Mermaid::IRAdapters::Treemap.call(diagram)

    expect(described_class.new.call(data)).to eq(scene)
  end

  context "with a styled hierarchy" do
    subject(:ir_evidence) do
      child_scenes = ir_scene.cells.first.children
      [ir_scene, child_scenes.map { |cell| cell.label.text },
       ir_scene.cells.first.value_label,
       child_scenes.first.fill, child_scenes.first.stroke]
    end

    let(:diagram) do
      Sirena::Diagram::Treemap.new.tap do |treemap|
        treemap.title = "Allocation"
        root = Sirena::Diagram::TreemapNode.new("Root")
        small = Sirena::Diagram::TreemapNode.new("Small", 1)
        large = Sirena::Diagram::TreemapNode.new("Large", 3)
        large.css_class = "important"
        root.add_child(small)
        root.add_child(large)
        treemap.add_root_node(root)
        treemap.add_class_def("important", "fill:#f96,stroke:#123")
      end
    end
    let(:ir_scene) do
      data = Sirena::Notation::Mermaid::IRAdapters::Treemap.call(diagram)

      described_class.new.call(data)
    end
    let(:expected_evidence) do
      [scene, %w[Large Small], nil, "#f96", "#123"]
    end

    it { is_expected.to eq(expected_evidence) }
  end

  context "with an explicit parent magnitude" do
    subject(:ir_evidence) do
      [ir_scene, ir_scene.cells.first.children.first.box.height]
    end

    let(:diagram) do
      Sirena::Diagram::Treemap.new.tap do |treemap|
        root = Sirena::Diagram::TreemapNode.new("Root", 10)
        root.add_child(Sirena::Diagram::TreemapNode.new("Child", 2))
        treemap.add_root_node(root)
      end
    end
    let(:ir_scene) do
      data = Sirena::Notation::Mermaid::IRAdapters::Treemap.call(diagram)

      described_class.new.call(data)
    end

    it { is_expected.to eq([scene, 310.0]) }
  end
end
