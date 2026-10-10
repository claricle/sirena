# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::Mermaid do
  it "raises the requested layer error when the type's class is absent" do
    layer = stub_const("MissingMermaidLayer", Module.new)

    expect do
      described_class.layer_class(layer, :pie, Sirena::Layout::LayoutError)
    end.to raise_error(
      Sirena::Layout::LayoutError,
      "No MissingMermaidLayer::Pie class for diagram type: pie",
    )
  end
end
