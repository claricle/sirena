# frozen_string_literal: true

require "spec_helper"
require "sirena/layout/er_diagram_entity_size"

module ErEntityCells
  def cells(*pairs)
    pairs.map { |type, name| { attribute_type: type, name: name } }
  end
end

RSpec.describe Sirena::Layout::ErDiagramEntitySize do
  include ErEntityCells

  # Each row: entity, attributes, then the width and height mmdc drew,
  # read from spec/fixtures_mermaid/er/{002,003,058}*.svg.
  [
    ["CAR",
     [%w[string registrationNumber], %w[string make], %w[string model]],
     229.6875, 171.0],
    ["PERSON",
     [%w[string firstName], %w[string lastName], %w[int age]],
     160.515625, 171.0],
    ["ENTITY",
     [%w[string name1], %w[int value2], %w[float point3_5]],
     152.703125, 171.0],
    ["ORDER_ITEM", [%w[int quantity], %w[float price]], 143.921875, 128.25],
  ].each do |name, pairs, width, height|
    it "sizes #{name} as mmdc does" do
      size = described_class.call(name, cells(*pairs))

      expect([size[:width], size[:height]])
        .to match([be_within(0.5).of(width), be_within(0.001).of(height)])
    end
  end

  it "widens the columns to a name wider than its attributes" do
    size = described_class.call("A_VERY_LONG_ENTITY_NAME", cells(%w[int a]))

    expect(size[:width])
      .to be_within(0.001)
      .of(described_class.text_width("A_VERY_LONG_ENTITY_NAME") + 50)
  end

  # The key column and the attribute-less box follow mmdc's erBox source;
  # no reference SVG in the corpus has either.
  it "adds a key column only when an attribute has a key" do
    plain = described_class.call("E", cells(%w[int id]))
    keyed = described_class.call(
      "E", [{ attribute_type: "int", name: "id", key_type: "PK" }]
    )

    expect(keyed[:width] - plain[:width])
      .to be_within(0.001).of(described_class.text_width("PK") + 25)
  end

  it "draws an entity with no attributes as a padded label box" do
    size = described_class.call("E", [])

    expect(size).to eq(width: 100.0, height: 84)
  end
end
