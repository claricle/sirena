# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/info"

RSpec.describe Sirena::Layout::Info do
  subject(:graph) { described_class.new.to_graph(diagram) }

  let(:diagram) { Sirena::Diagram::Info.new }

  it "defaults the identifier and showInfo state" do
    expect(graph).to eq(default_graph)
  end

  it "preserves an explicit identifier, title, and enabled showInfo state" do
    populate_diagram
    expect(graph).to eq(populated_graph)
  end

  def default_graph
    {
      id: "info",
      title: nil,
      show_info: false,
      metadata: { diagram_type: :info },
    }
  end

  def populate_diagram
    diagram.id = "status"
    diagram.title = "System status"
    diagram.show_info = true
  end

  def populated_graph
    {
      id: "status",
      title: "System status",
      show_info: true,
      metadata: { diagram_type: :info },
    }
  end
end
