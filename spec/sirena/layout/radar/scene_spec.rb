# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe Sirena::Layout::Radar::Scene do
  let(:source) { File.read("examples/radar/01-simple-radar.mmd") }
  let(:diagram) { Sirena::Parser::Radar.new.parse(source) }
  let(:scene) { Sirena::Layout::Radar.new.call(diagram) }
  let(:renderer) { Sirena::Renderer::Radar.new }

  it "publishes the exact y coordinate written for every label" do
    evidence = scene_labels.map do |label|
      [rendered_y.fetch(label.text) == label.y,
       label.respond_to?(:dominant_baseline)]
    end

    expect(evidence).to all(eq([true, false]))
  end

  it "publishes every data-point radius" do
    expect(scene.curves.flat_map(&:points).map(&:radius).uniq).to eq([3.0])
  end

  it "copies mutated Scene label and point geometry" do
    mutate_geometry

    expect(renderer.render(scene).to_xml)
      .to include('r="9.0"', 'y="123.25"')
  end

  def scene_labels
    [scene.title, *scene.axes.map(&:label), *scene.legend.map(&:label)].compact
  end

  def rendered_y
    document = REXML::Document.new(renderer.render(scene).to_xml)
    document.get_elements("//text").to_h do |text|
      [text.text, text.attributes.fetch("y").value.to_f]
    end
  end

  def mutate_geometry
    scene.curves.first.points.first.radius = 9
    scene.axes.first.label.y = 123.25
  end
end
