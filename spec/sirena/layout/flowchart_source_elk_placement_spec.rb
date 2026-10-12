# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Flowchart do
  let(:body) do
    <<~MERMAID
      a[hello] --> b[world]
      b --> c{test}
      c --> one
      c --> two
      c --> three
    MERMAID
  end

  it "uses direct 35px ELK placement for the flowchart-elk header" do
    directed_calls = 0
    spacing = nil
    allow(Sirena::Layout::Flowchart::DirectedPlacement).to receive(:apply)
      .and_wrap_original do |original, *arguments, **keywords|
        directed_calls += 1
        original.call(*arguments, **keywords)
      end
    allow(Sirena::Layout::ElkPlacement).to receive(:apply)
      .and_wrap_original do |original, graph|
        options = graph.fetch(:layoutOptions)
        spacing = [
          options.fetch(Sirena::Layout::Base::ElkOptions::NODE_NODE_SPACING),
          options.fetch(Sirena::Layout::Base::ElkOptions::LAYER_SPACING),
        ]
        original.call(graph)
      end

    Sirena.render("flowchart-elk\n#{body}")

    expect([directed_calls, spacing]).to eq([0, [35, 35]])
  end

  it "keeps ordinary flowcharts on dagre-compatible placement" do
    expect(directed_placement_calls("flowchart TD\n#{body}")).to eq(1)
  end

  it "keeps an explicit caller engine ahead of the source header" do
    calls = directed_placement_calls(
      "flowchart-elk\n#{body}", layout_engine: :elk
    )

    expect(calls).to eq(1)
  end

  def directed_placement_calls(source, **options)
    calls = 0
    allow(Sirena::Layout::Flowchart::DirectedPlacement).to receive(:apply)
      .and_wrap_original do |original, *arguments, **keywords|
        calls += 1
        original.call(*arguments, **keywords)
      end
    Sirena.render(source, **options)
    calls
  end
end
