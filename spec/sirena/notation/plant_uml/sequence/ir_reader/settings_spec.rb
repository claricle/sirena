# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"
require "sirena/notation/plantuml/sequence/ir_reader/index"
require "sirena/notation/plantuml/sequence/ir_reader/settings"

RSpec.describe Sirena::Notation::PlantUML::Sequence::IRReader::Settings do
  subject(:settings) { described_class.call(index) }

  let(:node) { Sirena::IR::Node.new(id: "appearance", role: "appearance") }
  let(:graph) { Sirena::IR::Graph.new(id: "graph", nodes: [node]) }
  let(:index) do
    Sirena::Notation::PlantUML::Sequence::IRReader::Index.new(graph)
  end

  it "defaults optional settings absent from the index" do
    values = [settings[:appearance].alignment, settings[:chrome].legend_place,
              settings[:footbox], settings[:warnings], settings[:title]]
    expect(values).to eq([:center, "bottom center", true, [], nil])
  end
end
