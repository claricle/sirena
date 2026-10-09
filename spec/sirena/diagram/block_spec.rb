# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Diagram::Block do
  describe Sirena::Diagram::BlockConnection do
    it "distinguishes arrow and line connections" do
      arrow = described_class.new(connection_type: "arrow")
      line = described_class.new(connection_type: "line")
      predicates = [[arrow.arrow?, arrow.line?], [line.arrow?, line.line?]]

      expect(predicates).to eq([[true, false], [false, true]])
    end
  end

  subject(:diagram) { described_class.new }

  describe "#add_style" do
    it "appends the exact style object" do
      style = Sirena::Diagram::BlockStyle.new(block_id: "A")

      diagram.add_style(style)

      expect(diagram.styles.first).to equal(style)
    end
  end

  describe "#diagram_type" do
    it "returns :block" do
      expect(diagram.diagram_type).to eq(:block)
    end
  end
end
