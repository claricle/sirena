# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe Sirena::Layout::UserJourney::Scene do
  let(:source) do
    <<~MERMAID
      journey
        title Checkout
        section Shop
        Browse: 5: Customer
    MERMAID
  end
  let(:diagram) { Sirena::Parser::UserJourney.new.parse(source) }
  let(:scene) { Sirena::Layout::UserJourney.new.call(diagram) }
  let(:renderer) { Sirena::Renderer::UserJourney.new }
  let(:task) { scene.tasks.first }

  it "publishes final label coordinates and anchors" do
    evidence = box_labels.map do |label|
      [rendered_y.fetch(label.text), rendered_anchor.fetch(label.text)] ==
        [label.y, label.text_anchor]
    end

    expect(evidence).to all(be(true))
  end

  it "publishes every actor-dot and eye radius" do
    radii = [scene.legend.first.dot.radius, task.dots.first.radius,
             *task.face.eyes.map(&:radius)]

    expect(radii).to eq([7.0, 7.0, 1.5, 1.5])
  end

  it "copies mutated Scene label, dot, and eye geometry" do
    mutate_geometry

    expect(renderer.render(scene).to_xml)
      .to include('r="9.0"', 'r="4.0"', 'y="333.25"',
                  'text-anchor="start"')
  end

  def box_labels
    scene.sections.flat_map(&:labels) + scene.tasks.flat_map(&:labels)
  end

  def rendered_text
    document = REXML::Document.new(renderer.render(scene).to_xml)
    document.get_elements("//text").to_h { |text| [text.text, text] }
  end

  def rendered_y
    rendered_text.transform_values do |text|
      text.attributes.fetch("y").value.to_f
    end
  end

  def rendered_anchor
    rendered_text.transform_values { |text| text.attributes["text-anchor"] }
  end

  def mutate_geometry
    mutate_point_geometry
    mutate_label_geometry
  end

  def mutate_point_geometry
    scene.legend.first.dot.radius = 9
    task.face.eyes.first.radius = 4
  end

  def mutate_label_geometry
    task.labels.first.y = 333.25
    task.labels.first.text_anchor = "start"
  end
end
