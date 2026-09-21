# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Engine do
  include EngineCanvasHelpers

  describe "a flowchart that draws nothing" do
    # Every reference SVG for these four cases is viewBox="-8 -8 16 16",
    # max-width 16px. Sirena keeps its "0 0" origin and matches the extent.
    Dir[File.join(__dir__, "../mermaid/flowchart/*.mmd")].select do |f|
      File.basename(f).match?(
        /\A(147|148|149|150)_parser_should_be_possible_to_declare_/
      )
    end.each do |path|
      it "renders #{File.basename(path, '.mmd')} as the 16x16 canvas" do
        svg = canvas(File.read(path))

        expect([svg.attributes["width"], svg.attributes["height"]])
          .to eq(%w[16.0 16.0])
        expect(svg.elements.to_a).to eq([])
      end
    end

    it "does not shrink a flowchart with a node to the empty canvas" do
      svg = canvas("graph TD\nA\nclassDef a fill:#bbb")

      expect(svg.attributes["width"].to_f).to be > 16
      expect(svg.elements.to_a).not_to eq([])
    end
  end
end
