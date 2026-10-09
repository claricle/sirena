# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/error"

RSpec.describe Sirena::Layout::Error do
  subject(:graph) { described_class.new.to_graph(diagram) }

  let(:diagram) { Sirena::Diagram::Error.new }

  it "keeps a missing message for the renderer's default" do
    expect(graph).to eq(
      id: "error",
      title: nil,
      message: nil,
      metadata: { diagram_type: :error },
    )
  end

  it "preserves explicit identity, title, and message" do
    diagram.id = "failure"
    diagram.title = "Build failed"
    diagram.message = "Dependency missing"

    expect(graph).to eq(
      id: "failure",
      title: "Build failed",
      message: "Dependency missing",
      metadata: { diagram_type: :error },
    )
  end
end
