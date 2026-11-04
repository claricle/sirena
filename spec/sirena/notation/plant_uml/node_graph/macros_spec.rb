# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::PlantUML::NodeGraph::Macros do
  describe ".expand" do
    it "drops a definition and expands later whole words",
       :aggregate_failures do
      entries = [["!define Box rectangle", 1], ["Box A", 2], ["BoxX B", 3]]

      expect(described_class.expand(entries))
        .to eq([["rectangle A", 2], ["BoxX B", 3]])
    end

    it "expands a definition with an empty body" do
      expect(described_class.expand([["!define NOTHING", 1], ["a NOTHING", 2]]))
        .to eq([["a ", 2]])
    end

    it "leaves a macro with parameters for the parser to name" do
      expect(described_class.expand([["!define F(x) rectangle x", 1]]))
        .to eq([["!define F(x) rectangle x", 1]])
    end

    it "applies a definition to a later one" do
      entries = [["!define A circle", 1], ["!define B A #red", 2], ["B x", 3]]

      expect(described_class.expand(entries).last).to eq(["circle #red x", 3])
    end
  end
end
