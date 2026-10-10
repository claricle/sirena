# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::StateDiagramRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  subject(:recognizer) { described_class.new }

  def recognized(svg)
    extract(svg, recognizer).elements.map do |element|
      [element.kind, element.key, element.parent, element.identity]
    end.sort_by { |item| item.map(&:to_s) }
  end

  def synthetic_reference
    <<~SVG
      <svg viewBox="0 0 100 100">
        <g class="statediagram-cluster" id="checkout"><rect width="100" height="100"/></g>
        <g class="node" id="state-order-2026-7"><rect width="20" height="20"/></g>
        <g class="node" id="state-checkout_start-8"><circle cx="10" cy="10" r="5"/></g>
      </svg>
    SVG
  end

  def synthetic_sirena
    <<~SVG
      <svg viewBox="0 0 100 100">
        <g id="state-checkout"><rect width="100" height="100"/>
          <g id="state-order-2026"><rect width="20" height="20"/></g>
          <g id="state-start_3"><circle cx="40" cy="10" r="5"/></g>
        </g>
      </svg>
    SVG
  end

  def synthetic_elements
    [
      [:composite, "checkout", nil, :id],
      [:state, "order-2026", "checkout", :id],
      [:"terminal-start", "[*]", "checkout", :id],
    ].sort_by { |item| item.map(&:to_s) }
  end

  def real_sides
    name = "020_parser_should_handle_state_definitions_with_separation_of_id_19"
    [reference_svg("state/#{name}.svg"),
     Sirena.render(corpus_source("state/#{name}.mmd"))]
  end

  def real_reference_elements
    [
      [:composite, "NotShooting", nil, :id],
      [:state, "Configuring", "NotShooting", :id],
      [:state, "Idle", "NotShooting", :id],
      [:"terminal-start", "[*]", "NotShooting", :id],
    ].sort_by { |item| item.map(&:to_s) }
  end

  def real_sirena_elements
    [
      [:state, "Configuring", nil, :id],
      [:state, "Idle", nil, :id],
      [:state, "NotShooting", nil, :id],
      [:"terminal-start", "[*]", nil, :id],
    ].sort_by { |item| item.map(&:to_s) }
  end

  def simple_terminal_match
    name = "002_example_state_1"
    reference = extract(reference_svg("state/#{name}.svg"), recognizer)
    sirena = extract(Sirena.render(corpus_source("state/#{name}.mmd")),
                     recognizer)

    SpecSupport::LayoutParity::ElementMatcher.match(
      reference: reference,
      sirena: sirena,
    )
  end

  it "normalizes generated ordinals and keeps composite ancestry" do
    actual = [recognized(synthetic_reference), recognized(synthetic_sirena),
              recognizer.container_kinds]

    expect(actual).to eq([synthetic_elements, synthetic_elements, [:composite]])
  end

  it "exposes missing composite metadata in a real Sirena render" do
    reference, sirena = real_sides

    expect([recognized(reference), recognized(sirena)])
      .to eq([real_reference_elements, real_sirena_elements])
  end

  it "matches terminal roles by their fixed contract key" do
    terminal_failures = simple_terminal_match[:failures].select do |failure|
      failure[:group].first.to_s.start_with?("terminal-")
    end

    expect(terminal_failures).to be_empty
  end
end
