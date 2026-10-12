# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Layout do
  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:document) do
    id = "resources.vega.xmi.clazz.XMI0003_class--d50636ffecaf"
    source = File.read("spec/plantuml/class/#{id}.puml")
    Nokogiri::XML(Sirena.render(source, notation: :plantuml))
      .tap(&:remove_namespaces!)
  end

  let(:boxes) do
    fields = %w[x y width height]
    %w[A B C].to_h do |name|
      rect = document.at_xpath("//g[@id='class-#{name}']/rect")
      [name, fields.map { |field| rect[field].to_f }]
    end
  end

  def signature
    a, b, c = boxes.values_at("A", "B", "C")
    dimensions = boxes.transform_values { |box| rounded(box.last(2)) }
    gaps = [b[0] - (a[0] + a[2]), c[1] - (a[1] + a[3])]
    alignments = [center(c, 0) - center(a, 0),
                  center(b, 1) - center(a, 1)]
    { dimensions: dimensions, gaps: rounded(gaps),
      alignments: rounded(alignments),
      abstract_rows: document.xpath("//g[@id='class-B']/text").map(&:text) }
  end

  def rounded(values)
    values.map { |value| value.round(4) }
  end

  def center(box, axis)
    box[axis] + (box[axis + 2] / 2)
  end

  it "uses standard chrome and per-column packing for isolated class kinds" do
    expected = {
      dimensions: { "A" => [78.2061, 64.4883],
                    "B" => [40.0527, 48.0],
                    "C" => [41.6865, 48.0] },
      gaps: [35.0, 60.0], alignments: [0.0, 0.0], abstract_rows: ["B"]
    }

    expect(signature).to eq(expected)
  end
end
