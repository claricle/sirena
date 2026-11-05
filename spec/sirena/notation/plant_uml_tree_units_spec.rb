# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

# Edges of the PlantUML tree and gantt classes that no rendered source
# reaches, called directly.
RSpec.describe Sirena::Notation::PlantUML do
  describe Sirena::Notation::PlantUML::Tree::Role do
    it "reads a role that names no side as a right-hand box" do
      role = described_class.parse(nil)
      expect([role.side, role.boxless, role.fill]).to eq(["right", false, nil])
    end
  end

  describe Sirena::Notation::PlantUML::Tree::Layout do
    subject(:layout) { Class.new(described_class).new }

    it "leaves the font size to a subclass" do
      expect { layout.send(:font_size) }.to raise_error(NotImplementedError)
    end

    it "leaves the gap between trees to a subclass" do
      expect { layout.send(:gap_between_trees) }
        .to raise_error(NotImplementedError)
    end

    it "leaves placing a tree to a subclass" do
      expect { layout.send(:place_tree, nil, 0.0) }
        .to raise_error(NotImplementedError)
    end
  end

  describe Sirena::Notation::PlantUML::Tree::WbsLayout do
    subject(:layout) { described_class.new }

    let(:ends) { [[9.0, nil], [7.0, nil]] }

    before { layout.instance_variable_set(:@segments, []) }

    it "returns the lowest bottom when no column has a last box" do
      expect(layout.send(:join_columns, 5.0, 1.0, ends)).to eq(9.0)
    end

    it "draws no trunk when no column has a last box" do
      layout.send(:join_columns, 5.0, 1.0, ends)
      expect(layout.instance_variable_get(:@segments)).to be_empty
    end
  end

  describe Sirena::Notation::PlantUML::Gantt::Scene do
    it "starts with every collection empty" do
      scene = described_class.new
      expect([scene.grid_lines, scene.rules, scene.bars, scene.diamonds,
              scene.texts]).to all(eq([]))
    end
  end
end
