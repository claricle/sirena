# frozen_string_literal: true

require "spec_helper"
require "sirena/ir"

RSpec.describe Sirena::Notation::Mermaid do
  def parsed(source)
    described_class.parse(source).diagram
  end

  it "hands migrated graph types to layout as shared IR" do
    sankey = parsed("sankey-beta\nA,B,1\n")
    mindmap = parsed("mindmap\n  root\n    child\n")

    expect([sankey, mindmap]).to all(be_a(Sirena::IR::Graph))
  end

  it "keeps unmigrated parser models private until their adapter lands" do
    flowchart = parsed("flowchart TD\nA --> B\n")

    expect(flowchart).to be_a(Sirena::Diagram::Flowchart)
  end

  it "renders both migrated types through the shared boundary" do
    sources = ["sankey-beta\nA,B,1\n", "mindmap\n  root\n    child\n"]

    expect(sources.map { |source| Sirena.render(source) })
      .to all(start_with("<svg").and(include("</svg>")))
  end
end
