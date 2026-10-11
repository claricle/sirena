# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::C4::Scene do
  let(:source) { File.read("examples/c4/01-context-diagram.mmd") }
  let(:diagram) { Sirena::Parser::C4.new.parse(source) }
  let(:scene) { Sirena::Layout::C4.new.call(diagram) }
  let(:renderer) { Sirena::Renderer::C4.new }
  let(:person) { scene.children.find { |node| node.kind == "person" } }

  it "publishes final box and person-icon sizes" do
    expect(scene_geometry).to eq([10.0, 10.0, 18.0, 12.0, [5.0, 5.0, 5.0]])
  end

  it "publishes the exact y coordinate written for every label" do
    evidence = scene_labels.map do |label|
      [rendered_labels[label.text] == label.y, label.respond_to?(:baseline)]
    end

    expect(evidence).to all(eq([true, false]))
  end

  it "copies mutated Scene geometry without recreating it" do
    mutate_scene_geometry

    expect(renderer.render(scene).to_xml)
      .to include('rx="17.0" ry="17.0"', 'r="6.0"',
                  'rx="13.0" ry="9.0"', 'y="321.25"')
  end

  it "rejects anything other than a typed C4 Scene" do
    expect { renderer.render({ width: 10, height: 10 }) }
      .to raise_error(Sirena::Renderer::RenderError,
                      "C4 renderer requires Layout::C4::Scene")
  end

  def scene_geometry
    [*person_geometry, other_corner_radii]
  end

  def person_geometry
    [person.corner_radius, person.head.radius,
     person.body.radius_x, person.body.radius_y]
  end

  def other_corner_radii
    scene.children.reject { |node| node.kind == "person" }
      .map(&:corner_radius)
  end

  def scene_labels
    scene.children.flat_map(&:labels) + scene.edges.flat_map(&:labels)
  end

  def rendered_labels
    renderer.render(scene).to_xml
      .scan(/<text[^>]* y="([^"]+)"[^>]*>([^<]*)<\/text>/)
      .to_h { |y_coord, text| [text, y_coord.to_f] }
  end

  def mutate_scene_geometry
    mutate_person_geometry
    scene.edges.first.labels.first.y = 321.25
  end

  def mutate_person_geometry
    person.corner_radius = 17
    person.head.radius = 6
    person.body.radius_x = 13
    person.body.radius_y = 9
  end
end
