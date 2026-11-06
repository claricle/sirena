# frozen_string_literal: true

require "spec_helper"
require_relative "activity/activity_helpers"

RSpec.describe Sirena::Notation::PlantUML::Activity do
  include ActivityHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  rendered = %w[5-4 5-12 6-3 6-4 6-10-4 6-15 6-19 6-25-2]
  refused = { "5-7" => "image" }

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

  it "draws the swimlane names and lane fill of corpus 6-19, not the " \
     "old-syntax node colours", :aggregate_failures do
    svg = render_fixture("6-19")

    expect(svg_texts(svg)).to include("Actor_For_red", "Final_Actor")
    expect(svg).to include('fill="pink"', 'fill="lightgray"')
    expect(svg).not_to include('fill="palegreen"', 'fill="lightblue"')
  end

  it "draws every swimlane title of corpus 6-19 at 18, in a band that " \
     "holds it", :aggregate_failures do
    svg = render_fixture("6-19")

    expect(lane_title_sizes(svg)).to eq(%w[18] * 4)
    expect(svg).to include('width="165.7355839572847"',
                           'width="108.9296875"', 'width="109.474609375"')
  end

  def lane_title_sizes(svg)
    REXML::Document.new(svg).get_elements("//text")
      .select { |t| t.text.to_s.match?(/\A[A-Z][a-z]+_[A-Za-z_]+\z/) }
      .map { |t| t.attributes["font-size"] }
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
