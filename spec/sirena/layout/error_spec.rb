# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/error"

RSpec.describe Sirena::Layout::Error do
  subject(:graph) { described_class.new.to_graph(diagram) }

  let(:diagram) { Sirena::Diagram::Error.new }

  it "keeps a missing message for the renderer's default" do
    expect(graph).to eq(default_graph)
  end

  it "preserves explicit identity, title, and message" do
    populate_diagram
    expect(graph).to eq(populated_graph)
  end

  def default_graph
    {
      id: "error",
      title: nil,
      message: nil,
      metadata: { diagram_type: :error },
    }
  end

  def populate_diagram
    diagram.id = "failure"
    diagram.title = "Build failed"
    diagram.message = "Dependency missing"
  end

  def populated_graph
    {
      id: "failure",
      title: "Build failed",
      message: "Dependency missing",
      metadata: { diagram_type: :error },
    }
  end
end
