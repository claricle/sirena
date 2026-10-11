# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::StateDiagram do
  include SpecSupport::LayoutParity::FigureHelpers

  let(:parser) { Sirena::Parser::StateDiagram.new }
  let(:recognizer) { SpecSupport::LayoutParity::StateDiagramRecognizer.new }

  def source(name)
    File.read("spec/mermaid/state_diagram/#{name}.mmd")
  end

  def rendered_hierarchy(name)
    extract(Sirena.render(source(name)), recognizer).elements.map do |element|
      [element.kind, element.parent, element.key]
    end
  end

  def forward_composite_evidence
    name = "should_handle_notes_for_composite_nested_states-0033e4b1"
    diagram = parser.parse(source(name))
    parent = diagram.find_state("NotShooting")
    scene = described_class.new.scene(diagram)
    [parent.children.map(&:id), diagram.notes.map(&:target_id),
     scene.children.map(&:id)]
  end

  def live_behavior_rows
    names = %w[
      should_handle_floating_notes-bbec0e37
      should_handle_notes_for_composite_nested_states-0033e4b1
      statediagram_v2_spec-13deff6f
      statediagram_v2_spec-3249fd2d
      statediagram_v2_spec-c351b77a
      statediagram_v2_spec-ed4440fd
    ]
    runner = SpecSupport::LayoutParity::CohortRunner.new
    results = runner.comparison_cases.filter_map do |candidate|
      next unless names.any? { |name| candidate.case_id.include?(name) }

      runner.send(:compare, candidate)
    end
    SpecSupport::LayoutParity::CaseLedger.build(results)
  end

  def composite_geometry_rows
    live_behavior_rows.select do |row|
      row.fetch("case").match?(
        /(?:0033e4b1|13deff6f|3249fd2d)\.mmd\z/,
      )
    end
  end

  it "omits an unconnected declaration-only state" do
    scene = described_class.new.scene(
      parser.parse(source("should_handle_floating_notes-bbec0e37")),
    )

    expect(scene.children).to be_empty
  end

  it "nests a forward-declared composite and attaches its note" do
    expect(forward_composite_evidence)
      .to eq([%w[Idle Configuring start_2], ["NotShooting"],
              %w[start_1 NotShooting NotShooting----note]])
  end

  it "retains concurrent regions and their state ancestry" do
    name = "statediagram_v2_spec-c351b77a"
    parent = parser.parse(source(name)).find_state("s2")
    model = parent.children.map { |region| region.children.map(&:id) }
    figure = rendered_hierarchy(name)

    expect([model, figure]).to eq(concurrent_evidence)
  end

  it "clears every reference-backed State behavior failure" do
    expect(live_behavior_rows.map do |row|
      [row.fetch("case"), row.dig("summary", "hard_failure")]
    end).to all(end_with(false))
  end

  it "matches nested composite geometry in each duplicate corpus row" do
    metrics = composite_geometry_rows.map do |row|
      row.dig("summary", "metrics").values_at(
        "worst_e_c", "worst_e_w", "worst_e_h", "worst_e_a"
      )
    end

    expect(metrics).to eq(Array.new(3) { [0.0, 0.0, 0.0, 0.0] })
  end

  def concurrent_evidence
    model = [%w[s3], %w[s4], %w[55]]
    figure = [
      [:composite, nil, "s2"],
      [:composite, "s2", "concurrent-region-1"],
      [:state, "concurrent-region-1", "s3"],
      [:composite, "s2", "concurrent-region-2"],
      [:state, "concurrent-region-2", "s4"],
      [:composite, "s2", "concurrent-region-3"],
      [:state, "concurrent-region-3", "55"],
    ]
    [model, figure]
  end
end
