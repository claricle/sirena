# frozen_string_literal: true

require "spec_helper"

# Entity centres and canvas sizes that mmdc (Mermaid's dagre) drew for the
# sources below. Each inline case was rendered with `mmdc -i case.mmd -o
# case.svg`; centres are the `translate` of each `entity-<name>` node and the
# canvas is the root viewBox.
module ErPlacementCases
  ENTITY = "{ int id }"

  CASES = {
    "a cycle of three entities" => {
      source: <<~MMD,
        erDiagram
            A ||--o{ B : has
            B ||--o{ C : has
            C ||--o{ A : back
            A #{ENTITY}
            B #{ENTITY}
            C #{ENTITY}
      MMD
      centres: { "A" => [117.645, 50.75], "B" => [49.570, 237.25],
                 "C" => [117.645, 423.75] },
      canvas: [208.297, 474.5],
    },
    "a diamond with a relation that skips a rank" => {
      source: <<~MMD,
        erDiagram
            A ||--o{ B : l1
            A ||--o{ C : l2
            B ||--o{ D : l3
            C ||--o{ D : l4
            A ||--o{ D : skip
            A #{ENTITY}
            B #{ENTITY}
            C #{ENTITY}
            D #{ENTITY}
      MMD
      centres: { "A" => [272.711, 50.75], "B" => [49.570, 237.25],
                 "C" => [272.711, 237.25], "D" => [272.711, 423.75] },
      canvas: [426.813, 474.5],
    },
    "one entity fanning out to four" => {
      source: <<~MMD,
        erDiagram
            HUB ||--o{ A : x
            HUB ||--o{ B : y
            HUB ||--o{ C : z
            HUB ||--o{ D : w
            HUB #{ENTITY}
            A #{ENTITY}
            B #{ENTITY}
            C { string longer_name }
            D #{ENTITY}
      MMD
      centres: { "HUB" => [409.234, 50.75], "A" => [49.570, 237.25],
                 "B" => [272.711, 237.25], "C" => [545.758, 237.25],
                 "D" => [818.805, 237.25] },
      canvas: [868.375, 288.0],
    },
    "an unrelated entity beside two related ones" => {
      source: <<~MMD,
        erDiagram
            A ||--o{ B : has
            D {
              int id
            }
            C ||--|| B : owns
            A #{ENTITY}
            B #{ENTITY}
            C #{ENTITY}
      MMD
      centres: { "A" => [49.570, 50.75], "B" => [272.711, 237.25],
                 "D" => [272.711, 50.75], "C" => [495.852, 50.75] },
      canvas: [545.422, 288.0],
    },
  }.freeze

  # Corpus sources that have no committed reference SVG; centres and canvas
  # are from `mmdc -i spec/mermaid/er/<name>.mmd`.
  UNREFERENCED = {
    "001_rendering_erdiagram_spec_er_0" => {
      centres: { "PRODUCT" => [71.664, 50.0], "ORDER-ITEM" => [71.664, 235.0],
                 "1.5" => [315.695, 50.0], "u" => [555.695, 50.0],
                 "1" => [795.695, 50.0] },
      canvas: [853.695, 285.0],
    },
    "057_parser_should_handle_complex_diagram_with_special_entity_names_56" => {
      centres: { "CUSTOMER" => [83.164, 50.0], "1" => [83.164, 257.125],
                 "u" => [83.164, 486.375], "2.5" => [341.992, 50.0],
                 "ORDER" => [341.992, 257.125] },
      canvas: [418.820, 558.5],
    },
  }.freeze

  # Corpus case numbers that have a reference SVG in fixtures_mermaid/er.
  CORPUS = %w[002 003 058].freeze

  def corpus_path(number, directory, extension)
    Dir["spec/#{directory}/er/#{number}_*.#{extension}"].fetch(0)
  end

  def scene_for(source)
    diagram = Sirena::Parser::ErDiagram.new.parse(source)
    Sirena::Layout::ErDiagram.new.call(diagram)
  end

  def centres_of(scene)
    scene.children.to_h do |node|
      [node.id, [node.x + (node.width / 2), node.y + (node.height / 2)]]
    end
  end

  def reference_centres(svg)
    svg.scan(/id="(?:my-svg-)?entity-(.+?)-\d+"
              [^>]*transform="translate\(([\d.]+),\s([\d.]+)\)"/x)
      .to_h { |name, x, y| [name, [x.to_f, y.to_f]] }
  end

  def reference_canvas(svg)
    svg[/viewBox="([^"]*)"/, 1].split.map(&:to_f).drop(2)
  end

  def expect_scene_to_match(scene, centres, canvas)
    expect(centres_of(scene).keys).to match_array(centres.keys)
    expect_centres(centres_of(scene), centres)
    expect_canvas(scene, canvas)
  end

  def expect_canvas(scene, canvas)
    expect([scene.width, scene.height])
      .to match([be_within(1).of(canvas[0]), be_within(0.1).of(canvas[1])])
  end

  def expect_centres(actual, expected)
    expected.each do |name, (x, y)|
      expect(actual[name]).to match([be_within(1).of(x), be_within(0.1).of(y)])
    end
  end
end

RSpec.describe Sirena::Layout::ErDiagramPlacement do
  include ErPlacementCases

  ErPlacementCases::CASES.each do |title, mmdc|
    it "places #{title} where mmdc does" do
      scene = scene_for(mmdc[:source])

      expect_scene_to_match(scene, mmdc[:centres], mmdc[:canvas])
    end
  end

  ErPlacementCases::CORPUS.each do |number|
    it "places corpus case #{number} where mmdc does" do
      svg = File.read(corpus_path(number, "fixtures_mermaid", "svg"))
      source = File.read(corpus_path(number, "mermaid", "mmd"))

      expect_scene_to_match(
        scene_for(source), reference_centres(svg), reference_canvas(svg)
      )
    end
  end

  ErPlacementCases::UNREFERENCED.each do |name, mmdc|
    it "places corpus case #{name[0, 3]} where mmdc does, unreferenced" do
      source = File.read("spec/mermaid/er/#{name}.mmd")

      expect_scene_to_match(scene_for(source), mmdc[:centres], mmdc[:canvas])
    end
  end

  it "leaves a graph with no entities untouched" do
    graph = { children: [], edges: [] }

    expect(described_class.apply(graph))
      .to equal(graph).and eq(children: [], edges: [])
  end
end
