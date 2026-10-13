# frozen_string_literal: true

require "spec_helper"

RSpec.describe SpecSupport::LayoutParity::PlantumlSequenceRecognizer do
  include SpecSupport::LayoutParity::FigureHelpers

  let(:recognizer) { described_class.new }
  let(:references) do
    File.expand_path("../../plantuml/references/sequence", __dir__)
  end
  let(:svg) { File.read(File.join(references, "#{case_id}.svg")) }
  let(:messages) do
    extract(svg, recognizer).elements.select do |element|
      element.kind == :message
    end
  end

  context "with the pinned legacy actor timeline" do
    let(:case_id) { "resources.vega.asciiverse.timeline_001--18d6381b866f" }

    it "measures the arrow without its label anchor or participant tail" do
      expect(messages.first.bbox.to_a)
        .to eq([136.8882, 111.7988, 215.0132, 119.7988])
    end
  end

  context "with the pinned parallel self-loop" do
    let(:case_id) { "resources.vega.asciiverse.altpar_001--7ff458de0156" }

    it "measures the self-loop shapes without the label anchor" do
      expect(messages.last.bbox.to_a)
        .to eq([66.564, 74.7988, 108.564, 91.7988])
    end
  end

  context "with an actor-like glyph outside a known participant" do
    let(:svg) do
      <<~SVG
        <svg viewBox="0 0 100 100"><g>
          <g><title>Known</title><line x1="50" y1="0" x2="50" y2="100"
            style="stroke-dasharray:5,5"/></g>
          <text x="0" y="50">Decoration</text>
          <ellipse cx="5" cy="0" rx="2" ry="2"/>
          <path d="M 0 2 L 10 2"/>
          <line x1="10" y1="10" x2="20" y2="10"/>
          <text x="0" y="-20">Message</text>
        </g></svg>
      SVG
    end

    it "keeps those shapes in the message geometry" do
      expect(messages.first.bbox.to_a).to eq([0.0, -2.0, 20.0, 10.0])
    end
  end

  context "with the pinned interleaved timeline" do
    let(:case_id) { "resources.vega.asciiverse.timeline_002--f985a9b8f0de" }

    it "preserves all recognized messages through the interleaved fragments" do
      expect(messages.size).to eq(29)
    end
  end
end
