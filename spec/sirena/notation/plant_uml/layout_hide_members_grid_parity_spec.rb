# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::Layout do
  include_context "with an isolated notation registry"
  include DejaVuText

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  let(:document) do
    id = "resources.vega.migration.HideShow004_Test--16625d433c68"
    source = File.read("spec/plantuml/class/#{id}.puml")
    Nokogiri::XML(Sirena.render(source, notation: :plantuml))
      .tap(&:remove_namespaces!)
  end

  let(:groups) do
    document.xpath("//g[starts-with(@id, 'class-')]")
  end

  let(:boxes) do
    fields = %w[x y width height]
    groups.to_h do |group|
      rect = group.at_xpath("./rect")
      [group["id"].delete_prefix("class-"),
       fields.map { |field| rect[field].to_f }]
    end
  end

  def signature
    { order: groups.map { |group| group["id"].delete_prefix("class-") },
      dimensions: boxes.transform_values { |box| rounded(box.last(2)) },
      gaps: rounded(gaps), alignments: rounded(alignments) }
  end

  def expected
    { order: %w[B A C D],
      dimensions: { "B" => [padded("run(): boolean", 26.0), 56.4883],
                    "A" => [padded("A", 32.0), 32.0],
                    "C" => [padded("C", 32.0), 32.0],
                    "D" => [padded("D", 32.0), 32.0] },
      gaps: [35.0, 35.0, 60.0], alignments: [0.0, 0.0, 0.0] }
  end

  def padded(text, padding)
    (dejavu(text, size: 14) + padding).round(4)
  end

  def gaps
    b, a, c, d = boxes.values_at("B", "A", "C", "D")
    [gap(b, a, 0), gap(c, d, 0), c[1] - [edge(b, 1), edge(a, 1)].max]
  end

  def alignments
    b, a, c, d = boxes.values_at("B", "A", "C", "D")
    [row_offset(a, b), row_offset(d, c),
     span_center(c, d) - span_center(b, a)]
  end

  def row_offset(box, reference)
    center(box, 1) - center(reference, 1)
  end

  def gap(first, second, axis)
    second[axis] - edge(first, axis)
  end

  def edge(box, axis)
    box[axis] + box[axis + 2]
  end

  def center(box, axis)
    box[axis] + (box[axis + 2] / 2)
  end

  def span_center(first, last)
    (first[0] + edge(last, 0)) / 2
  end

  def rounded(values)
    values.map { |value| value.round(4) }
  end

  it "packs re-shown members ahead of hidden-member classes" do
    expect(signature).to eq(expected)
  end
end
