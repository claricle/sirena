# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

# PlantUML draws a `json` element mixed into another diagram as ONE box: a
# nested object or array fills its row's value cell. A `@startjson` diagram
# draws each nested value as a box of its own, joined by a dashed line.
RSpec.describe Sirena::Notation::PlantUMLData::Boxes do
  include_context "with an isolated notation registry"

  let(:boxes) { described_class }
  let(:inline) { boxes::InlineRows }
  let(:row_height) { boxes::InlineRows::ROW }
  let(:fruit) do
    %({"fruit":"Apple","size":"Large","color":["Red","Green"]})
  end

  before do
    [Sirena::Notation::PlantUML, Sirena::Notation::PlantUMLData].each do |n|
      Sirena::Notation.register(n) unless Sirena::Notation.ids.include?(n.id)
    end
  end

  def mixed(head, json)
    Sirena.render("@startuml\n#{head}\njson JSON #{json}\n@enduml",
                  notation: :plantuml)
  end

  def standalone(json)
    Sirena.render("@startjson\n#{json}\n@endjson", notation: :plantuml_data)
  end

  def rects(svg)
    REXML::Document.new(svg).get_elements("//rect")
  end

  def texts(svg)
    REXML::Document.new(svg).get_elements("//text").map(&:text)
  end

  def heights(svg)
    rects(svg).map { |rect| rect.attributes["height"].to_f }
  end

  def dashed(svg)
    REXML::Document.new(svg).get_elements("//path").count do |path|
      path.attributes["stroke-dasharray"]
    end
  end

  def table(json)
    value = boxes::JsonReader.new.call(json)
    boxes::TreeBuilder.new(boxes::Highlights.new, inline: true).call(value)
  end

  shared_examples "an element drawn as one box" do |others = 0|
    it "keeps the nested array in one box", :aggregate_failures do
      expect(rects(render).size).to eq(1 + others)
      expect(heights(render)).to include(be_within(0.01).of(5 * row_height))
      expect(texts(render)).to include("JSON", "fruit", "Red", "Green")
      expect(dashed(render)).to eq(0)
    end
  end

  context "with a use case diagram after allowmixing" do
    let(:render) { mixed("allowmixing\nactor Actor\nusecase Usecase", fruit) }

    it_behaves_like "an element drawn as one box"
  end

  context "with an object diagram" do
    let(:render) { mixed("class Class\nobject Object", fruit) }

    it_behaves_like "an element drawn as one box", 2

    it "draws the class and object boxes beside it" do
      expect(texts(render)).to include("Class", "Object")
    end
  end

  describe "the rows of a nested value" do
    it "stack in the cell of their key" do
      rows = table(%({"a":["x","y","z"]})).rows

      expect(inline.height(rows)).to eq(3 * row_height)
    end

    it "flatten an array of arrays", :aggregate_failures do
      rows = table(%({"a":[[1,2],[3]]})).rows

      expect(inline.height(rows)).to eq(3 * row_height)
      expect(rows.first.inline.rows.filter_map(&:inline).size).to eq(2)
    end

    it "keep a key column of their own for an object in an array" do
      inner = table(%({"o":[{"a":1},{"long":2}]})).rows.first.inline.rows
      keys = inner.map { |row| inline.key_width(row.inline.rows) }

      expect(keys.first).to be < keys.last
    end

    it "leave an empty array or object as an empty cell", :aggregate_failures do
      rows = table(%({"e":[],"o":{}})).rows

      expect(rows.map(&:inline)).to eq([nil, nil])
      expect(rows.map(&:value)).to eq(["", ""])
      expect(inline.height(rows)).to eq(2 * row_height)
    end

    it "show null and booleans as JSON writes them" do
      rows = table(%({"n":null,"t":true,"f":false})).rows

      expect(rows.map(&:value)).to eq(%w[null true false])
    end

    it "widen the box to the widest nested cell" do
      narrow = table(%({"k":"v"})).rows
      nested = table(%({"k":{"inner key":"a long value here"}})).rows

      expect(inline.width(nested))
        .to be > inline.width(narrow)
    end
  end

  describe "draw" do
    let(:marks) do
      rows = table(%({"a":1,"b":[2,3]})).rows
      inline.draw(rows, 0.0, 0.0, inline.width(rows))
    end

    it "rules each row off and divides keys from values", :aggregate_failures do
      lines = marks.select { |m| m[:kind] == :line }

      expect(lines.count { |m| m[:y1] == m[:y2] }).to eq(2)
      expect(lines.count { |m| m[:x1] == m[:x2] }).to eq(1)
    end

    it "writes each key and value" do
      expect(marks.select { |m| m[:kind] == :text }.map { |m| m[:content] })
        .to eq(%w[a 1 b 2 3])
    end

    it "draws nothing for a box with no rows" do
      expect(inline.draw([], 0.0, 0.0, 0.0)).to eq([])
    end
  end

  describe "a @startjson diagram" do
    it "still draws a nested array as a box of its own", :aggregate_failures do
      svg = standalone(fruit)

      expect(rects(svg).size).to eq(4)
      expect(dashed(svg)).to eq(1)
    end

    it "draws an empty array or object as a small empty box",
       :aggregate_failures do
      svg = standalone(%({"e":[],"o":{}}))
      small = rects(svg).select { |r| r.attributes["width"].to_i == 30 }

      expect(small.size).to eq(4)
      expect(dashed(svg)).to eq(2)
      expect(texts(svg)).not_to include("[]", "{}")
    end

    it "keeps the check box and null marks of a scalar" do
      expect(texts(standalone(%({"t":true,"n":null}))))
        .to include("☑ true", "␀")
    end
  end
end
