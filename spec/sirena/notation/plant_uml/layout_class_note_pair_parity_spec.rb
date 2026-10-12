# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Layout do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:source) do
    <<~PLANTUML
      @startuml
      class C
      note right of C #yellow
        yellow class note
      end note
      class D
      note right of D #lightblue
        lightblue class note
      end note
      @enduml
    PLANTUML
  end

  def box(extractor, id)
    group = extractor.doc.at_xpath("//g[@id='#{id}']")
    path = group.at_xpath("./path[@d]")
    return note_body(path) if path

    bounds = extractor.bbox(group)
    { "x" => bounds.min_x, "y" => bounds.min_y,
      "width" => bounds.width, "height" => bounds.height }
  end

  def note_body(path)
    points = SpecSupport::LayoutParity::PathPoints.new(path["d"]).points
    left, top = points.first
    { "x" => left, "y" => top,
      "width" => points.map(&:first).max - left,
      "height" => points.map(&:last).max - top }
  end

  def rendered_boxes
    recognizer = SpecSupport::LayoutParity::PlantumlClassRecognizer.new
    extractor = SpecSupport::LayoutParity::SvgFigureExtractor.new(recognizer)
    extractor.extract(Sirena.render(source, notation: :plantuml))
    %w[class-C note-0 class-D note-1].map do |id|
      box(extractor, id)
    end
  end

  def pair_geometry
    boxes = rendered_boxes
    { gaps: class_note_gaps(boxes), note_sizes: note_sizes(boxes) }
  end

  def class_note_gaps(boxes)
    boxes.each_cons(2).map { |left, right| horizontal_gap(left, right) }
  end

  def horizontal_gap(left, right)
    right["x"] - left["x"] - left["width"]
  end

  def note_sizes(boxes)
    boxes.values_at(1, 3).map { |note| note.values_at("width", "height") }
  end

  def expected_geometry
    gap = be_within(0.01).of(35.0)
    height = be_within(0.01).of(25.3105)
    {
      gaps: [gap, gap, gap],
      note_sizes: [
        [be_within(0.01).of(127.7866), height],
        [be_within(0.01).of(144.0366), height],
      ],
    }
  end

  it "places each class-level note beside its class" do
    expect(pair_geometry).to match(expected_geometry)
  end
end
