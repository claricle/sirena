# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Layout do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def rendered_geometry
    source = File.read(
      "spec/plantuml/class/" \
      "resources.vega.svg.interactive.SVG0004_Svek--d500aa856a7e.puml",
    )
    extractor = SpecSupport::LayoutParity::SvgFigureExtractor.new(
      SpecSupport::LayoutParity::PlantumlClassRecognizer.new,
    )
    extractor.extract(Sirena.render(source, notation: :plantuml))
    [extractor, extractor.doc]
  end

  def class_geometry(extractor, document)
    group = document.at_xpath("//g[starts-with(@id,'class-')]")
    bounds = extractor.bbox(group)
    baselines = group.xpath(".//text").map { |text| text["y"].to_f }
    cadences = baselines.each_cons(2).map { |first, last| last - first }
    { class_width: bounds.width, class_height: bounds.height,
      title_cadences: cadences }
  end

  def relation_geometry(extractor, document)
    group = document.at_xpath("//g[starts-with(@id,'relation-')]")
    bounds = extractor.bbox(group)
    class_box = document.at_xpath("//g[starts-with(@id,'class-')]/rect")
    class_right = class_box["x"].to_f + class_box["width"].to_f
    label = group.at_xpath(".//text")
    { loop_width: bounds.width, loop_height: bounds.height,
      label_gap: label["x"].to_f - class_right }
  end

  def actual_geometry
    extractor, document = rendered_geometry
    class_geometry(extractor, document)
      .merge(relation_geometry(extractor, document))
  end

  def expected_geometry
    {
      class_width: be_within(0.5).of(725.6865),
      class_height: be_within(0.01).of(75.4648),
      title_cadences: all(be_within(0.01).of(16.4883)),
      loop_width: be_within(0.5).of(34.76),
      loop_height: be_within(0.5).of(22.55),
      label_gap: be_within(0.5).of(40.99),
    }
  end

  it "matches PlantUML's multiline class and self-loop cadence" do
    expect(actual_geometry).to match(expected_geometry)
  end
end
