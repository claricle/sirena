# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Kanban do
  describe ".from_graph without a theme" do
    let(:graph) do
      { columns: [], cards: [], width: 100, height: 50 }
    end

    it "pads the canvas using the default theme" do
      expect(described_class.from_graph(graph).width).to eq(180)
    end

    it "keeps the view box in step with the canvas" do
      expect(described_class.from_graph(graph).view_box).to eq("0 0 180 130")
    end
  end
end
