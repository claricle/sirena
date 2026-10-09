# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::DiagramRegistry do
  describe ".get" do
    it "returns every handler for a known type" do
      expect(described_class.get(:error)).to eq(
        parser: Sirena::Parser::Error,
        transform: Sirena::Layout::Error,
        renderer: Sirena::Renderer::Error,
        model: Sirena::Diagram::Error,
      )
    end

    it "returns nil for an unknown type" do
      expect(described_class.get(:missing)).to be_nil
    end
  end

  describe ".types" do
    it "exposes the notation's registered types in order" do
      expect(described_class.types).to eq(Sirena::Notation::Mermaid::TYPES.keys)
    end
  end

  describe ".registered?" do
    it "reports known and unknown types" do
      values = [
        described_class.registered?(:flowchart),
        described_class.registered?(:missing),
      ]

      expect(values).to eq([true, false])
    end
  end

  it "does not expose a registry mutation API" do
    expect(described_class).not_to respond_to(:register)
  end
end
