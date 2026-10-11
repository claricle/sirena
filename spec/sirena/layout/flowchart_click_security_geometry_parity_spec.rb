# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Flowchart do
  let(:case_ids) do
    %w[
      click_security_loose-0efe7d83
      click_security_loose-16f3fdaa
      click_security_loose-1d618623
      click_security_loose-5f02fd1e
    ]
  end

  let(:ordinary_sources) do
    [
      "flowchart TB\n  A --> B\n",
      "flowchart TB\n  A -- text --> B\n",
    ]
  end

  def first_edge_spans(source)
    [diagram_for(source).edges.first.minimum_rank_span,
     ir_for(source).edges.first.minimum_rank_span]
  end

  def source_for(name)
    File.read("spec/mermaid/flowchart/#{name}.mmd")
  end

  def diagram_for(source)
    Sirena::Parser::Flowchart.new.parse(source)
  end

  def ir_for(source)
    Sirena::Notation::Mermaid::IRAdapters::Flowchart.call(diagram_for(source))
  end

  def parity_rows
    runner = SpecSupport::LayoutParity::CohortRunner.new
    selected = case_ids.map { |name| "flowchart/#{name}.mmd" }
    results = runner.comparison_cases.filter_map do |candidate|
      runner.send(:compare, candidate) if selected.include?(candidate.case_id)
    end
    SpecSupport::LayoutParity::CaseLedger.build(results)
  end

  it "carries each long link's minimum rank span through typed IR" do
    spans = case_ids.flat_map do |name|
      ir_for(source_for(name)).edges.map(&:minimum_rank_span)
    end

    expect(spans).to eq([2, 2, 2, 2])
  end

  it "leaves an ordinary arrow without a minimum-rank override" do
    spans = ordinary_sources.flat_map { |source| first_edge_spans(source) }

    expect(spans).to eq([nil, nil, nil, nil])
  end

  context "with minimum rank spans nil, 2 and 0 on typed IR edges" do
    let(:edges) do
      [nil, 2, 0].map do |span|
        Sirena::IR::Edge.new(
          id: "a_to_b", source_id: "a", target_id: "b",
          minimum_rank_span: span
        )
      end
    end

    it "accepts only positive minimum rank spans" do
      expect(edges.map(&:valid?)).to eq([true, true, false])
    end

    it "explains why a zero span is rejected" do
      expect(edges.last.validate.map(&:message))
        .to include("minimum_rank_span must be a positive integer")
    end
  end

  it "places every click-security target one extra rank below its source" do
    geometry = case_ids.map do |name|
      scene = described_class.new.call(diagram_for(source_for(name)))
      scene.children.map { |node| [node.y, node.height] }
    end

    expect(geometry).to eq(Array.new(4) { [[8.0, 54.0], [162.0, 54.0]] })
  end

  it "brings all four click-security rows inside the parity thresholds" do
    evidence = parity_rows.map do |row|
      [row.dig("summary", "hard_failure"),
       row.dig("summary", "metrics", "worst_e_c")]
    end

    expect(evidence).to all(satisfy { |hard, center| !hard && center <= 0.08 })
  end
end
