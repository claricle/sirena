# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"

RSpec.describe Sirena::Notation::Mermaid do
  def fixture(type)
    File.read("spec/fixtures/contract/#{type}.mmd")
  end

  def private_model(type)
    Sirena::Parser.for(type).parse(fixture(type))
  end

  def shared_ir?(value)
    [Sirena::IR::Graph, Sirena::IR::Data, Sirena::IR::Prepositioned]
      .any? { |shape| value.is_a?(shape) }
  end

  it "keeps every Mermaid parser model private before adaptation" do
    models = described_class.types.map { |type| private_model(type) }

    expect(models).to all(satisfy { |model| !shared_ir?(model) })
  end

  it "hands every Mermaid type to layout as shared IR" do
    diagrams = described_class.types.map do |type|
      described_class.parse(fixture(type)).diagram
    end

    expect(diagrams).to all(satisfy { |diagram| shared_ir?(diagram) })
  end

  it "renders every Mermaid type through the shared boundary" do
    rendered = described_class.types.map do |type|
      Sirena.render(fixture(type))
    end

    expect(rendered).to all(start_with("<svg").and(include("</svg>")))
  end
end
