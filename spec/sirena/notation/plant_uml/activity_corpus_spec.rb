# frozen_string_literal: true

require "spec_helper"
require_relative "activity/activity_helpers"

RSpec.describe Sirena::Notation::PlantUML::Activity do
  include ActivityHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  rendered = %w[5-4 5-12 6-3 6-4 6-10-4 6-15 6-19]
  refused = { "5-7" => "image", "6-25-2" => "style block" }

  rendered.each do |id|
    context "with plantuml-lrg-#{id}" do
      let(:svg) do
        render_fixture(id)
      end

      it "renders valid SVG" do
        expect(svg_root(svg).name).to eq("svg")
      end

      it "draws every activity's text" do
        expect(svg_texts(svg)).not_to be_empty
      end
    end
  end

  it "draws the text of corpus 6-3" do
    svg = render_fixture("6-3")

    expect(svg_texts(svg)).to include("Graphviz installed?", "yes", "no",
                                      "process all", "diagrams")
  end

  it "draws all five cases of corpus 6-4" do
    svg = render_fixture("6-4")

    expect(svg_texts(svg)).to include("Text 1", "Text 5", "condition A",
                                      "condition E")
  end

  it "draws both swimlane names and the lane fill of corpus 6-19",
     :aggregate_failures do
    svg = render_fixture("6-19")

    expect(svg_texts(svg)).to include("Actor_For_red", "Final_Actor")
    expect(svg).to include('fill="pink"', 'fill="palegreen"')
  end

  refused.each do |id, construct|
    it "names the #{construct} it refuses in plantuml-lrg-#{id}" do
      source = File.read(File.join(ActivityHelpers::FIXTURES,
                                   "plantuml-lrg-#{id}.puml"))

      expect do
        Sirena.render(source, notation: :plantuml)
      end.to raise_unsupported(construct)
    end
  end
end
