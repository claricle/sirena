# frozen_string_literal: true

require "stringio"
require "spec_helper"

RSpec.describe Sirena::Layout::ElkNotices do
  let(:output) { StringIO.new }
  let(:logger) { described_class.new(output, level: Logger::WARN) }

  it "drops the partially-honoured notice for an option Sirena uses" do
    logger.warn("elkrb: option elk.direction is partially honoured: x")

    expect(output.string).to eq("")
  end

  it "keeps the notice for an option elkrb does not honour at all" do
    logger.warn("elkrb: option elk.foo is accepted but not honoured")

    expect(output.string).to include("accepted but not honoured")
  end

  it "keeps other messages, including block-built ones" do
    logger.error { "boom" }

    expect(output.string).to include("boom")
  end

  it "is the logger elkrb reports through once layout is loaded" do
    expect(Elkrb.logger).to be_a(described_class)
  end

  context "when Sirena lays a graph out" do
    let(:options) do
      { "elk.direction" => "DOWN", "elk.spacing.edgeNode" => 30,
        "elk.layered.nodePlacement.strategy" => "SIMPLE" }
    end
    let(:graph) do
      { id: "root", layoutOptions: options,
        children: [{ id: "a", width: 10, height: 10 },
                   { id: "b", width: 10, height: 10 }],
        edges: [{ id: "e", sources: ["a"], targets: ["b"] }] }
    end

    around do |example|
      original = Elkrb.logger
      Elkrb.logger = logger
      example.run
    ensure
      Elkrb.logger = original
    end

    it "prints no elkrb notice for options elkrb ignores or part-honours" do
      Sirena::Layout::ElkPlacement.apply(graph)

      expect(output.string).to eq("")
    end
  end
end
