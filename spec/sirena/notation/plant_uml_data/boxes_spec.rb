# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

# What each fixture's picture must carry.
module PlantUMLBoxesFixtures
  DIR = File.expand_path("../../../fixtures/plantuml_boxes", __dir__)
  EXPECTED = {
    "lrg-11-1" => ["streetAddress", "212 555-1234", "\u2611 true"],
    "lrg-11-2" => %w[lastName postalCode],
    "lrg-11-3" => %w[firstName 646\ 555-4567],
    "lrg-12-3-1" => ["Creole", "HTML Creole", "stricken-out"],
    "lrg-12-3-2" => ["a deer, a female deer", "turtle-doves", "a pear tree"],
    "lrg-4-2" => %w[Object01 Object08 some\ labels 4],
    "lrg-4-6-3" => ["map: Map<Integer, String>", "Alice", "Charlie"],
    "lrg-4-6-5" => %w[CapitalCity Germany Washington NewYork],
    "lrg-4-7" => ["PERT: Project Name", "Kick.Off", "Label 4", "task.5"],
    "lrg-4-8" => %w[Class Object fruit Green],
  }.freeze
end

RSpec.describe Sirena::Notation::PlantUMLData::Boxes do
  let(:boxes) { described_class }

  include_context "with an isolated notation registry"

  before do
    [Sirena::Notation::PlantUML, Sirena::Notation::PlantUMLData].each do |n|
      Sirena::Notation.register(n) unless Sirena::Notation.ids.include?(n.id)
    end
  end

  def render(source)
    notation = source.match?(/\A@start(json|yaml)/) ? :plantuml_data : :plantuml
    Sirena.render(source, notation: notation)
  end

  def texts(svg)
    REXML::Document.new(svg).get_elements("//text").map(&:text)
  end

  PlantUMLBoxesFixtures::EXPECTED.each do |name, wanted|
    it "renders #{name} as an svg carrying its text", :aggregate_failures do
      svg = render(File.read(File.join(PlantUMLBoxesFixtures::DIR,
                                       "#{name}.puml")))

      expect(REXML::Document.new(svg).root.name).to eq("svg")
      expect(texts(svg)).to include(*wanted)
    end
  end

  it "has a spec for every fixture" do
    names = Dir[File.join(PlantUMLBoxesFixtures::DIR, "*.puml")]
      .map { |path| File.basename(path, ".puml") }

    expect(PlantUMLBoxesFixtures::EXPECTED.keys).to match_array(names)
  end

  describe "json" do
    it "draws a nested object as its own box and links to it",
       :aggregate_failures do
      svg = Sirena.render(%(@startjson\n{"a": {"b": 1}}\n@endjson))
      doc = REXML::Document.new(svg)

      expect(doc.get_elements("//rect").size).to eq(4)
      expect(doc.get_elements("//path").size).to eq(1)
    end

    it "draws an array as a box of value rows" do
      svg = Sirena.render(%(@startjson\n["x", "y"]\n@endjson))

      expect(texts(svg)).to eq(%w[x y])
    end

    it "fills a highlighted row, not the others", :aggregate_failures do
      source = %(@startjson\n#highlight "b"\n{"a": 1, "b": 2}\n@endjson)
      fills = REXML::Document.new(Sirena.render(source))
        .get_elements("//rect").map { |r| r.attributes["fill"] }

      expect(fills).to include("#CCFF02")
      expect(fills.count("#CCFF02")).to eq(1)
    end

    it "colours a highlight from its <style> class" do
      source = "@startjson\n<style>\n.warn { BackGroundColor red }\n" \
               "</style>\n" \
               "#highlight \"a\" <<warn>>\n{\"a\": 1}\n@endjson"

      expect(Sirena.render(source)).to include('fill="red"')
    end

    it "raises a ParseError for text that is not JSON" do
      expect { Sirena.render("@startjson\n{oops\n@endjson") }
        .to raise_error(Sirena::Parser::ParseError, /JSON/)
    end
  end

  describe "yaml" do
    it "keeps a repeated key's first place and last value" do
      value = boxes::YamlReader.new.call("a: 1\nb: 2\na: 3\n")

      expect(value).to eq({ "a" => "3", "b" => "2" })
    end

    it "reads nested mappings and sequences" do
      value = boxes::YamlReader.new
        .call("k:\n  - x\n  - \"y z\"\nm:\n  n: true\n")

      expect(value)
        .to eq({ "k" => ["x", "y z"], "m" => { "n" => "true" } })
    end

    it "reads a line that is not valid YAML as PlantUML does" do
      value = boxes::YamlReader.new.call(%(m: ""mono""\n))

      expect(value).to eq({ "m" => "\"mono\"" })
    end
  end

  describe "claiming" do
    it "claims @startjson and @startyaml but not @startuml" do
      notation = Sirena::Notation::PlantUMLData

      claims = ["@startjson\n{}", "@startyaml\na: 1", "@startuml\n"]
        .map { |source| notation.claims?(source) }

      expect(claims).to eq([true, true, false])
    end

    it "keeps class diagrams on the class reader" do
      svg = render("@startuml\nclass A\nA --> B\n@enduml")

      expect(texts(svg)).to include("A", "B")
    end

    it "shows YAML booleans and null as the plain words PlantUML shows",
       :aggregate_failures do
      svg = render("@startyaml\nt: true\nf: false\nn: null\nz: ~\n@endyaml")

      expect(texts(svg)).to include("true", "false", "null", "~")
      expect(texts(svg)).not_to include("\u2610 false", "\u2611 true",
                                        "\u2400")
    end

    it "leaves an empty YAML value blank, not as a null mark",
       :aggregate_failures do
      svg = render("@startyaml\na:\nb: 1\n@endyaml")

      expect(texts(svg)).to include("   ")
      expect(texts(svg)).not_to include("\u2400")
    end

    it "keeps JSON booleans and null as check boxes and the null mark" do
      svg = render(%(@startjson\n{"t":true,"f":false,"n":null}\n@endjson))

      expect(texts(svg)).to include("\u2611 true", "\u2610 false", "\u2400")
    end

    context "with creole spans in a value" do
      let(:runs) do
        svg = render(<<~PUML)
          @startyaml
          b: **bold**
          i: //it//
          s: --gone--
          w: ~~wavy~~
          c: <color:blue>Blue
          @endyaml
        PUML
        REXML::Document.new(svg).get_elements("//tspan")
          .to_h { |t| [t.text, t.attributes] }
      end

      it "styles bold, italic, strike and wave runs", :aggregate_failures do
        expect(runs["bold"]["font-weight"]).to eq("bold")
        expect(runs["it"]["font-style"]).to eq("italic")
        expect(runs["gone"]["text-decoration"]).to eq("line-through")
        expect(runs["wavy"]["text-decoration"]).to eq("underline")
      end

      it "colours a run" do
        expect(runs["Blue"]["fill"]).to eq("blue")
      end
    end

    it "keeps __ and a tilde-escaped marker literal, and reads <U+..>",
       :aggregate_failures do
      svg = render("@startyaml\ne: ~__plain__\nu: __kept__\n" \
                   "x: This is <U+221E> long\n@endyaml")

      expect(texts(svg)).to include("__plain__", "__kept__",
                                    "This is \u221E long")
    end

    it "reads a bare scalar JSON root" do
      expect(texts(render("@startjson\n42\n@endjson"))).to include("42")
    end

    it "reads a plain object body row" do
      svg = render("@startuml\nobject A {\n  plain row\n}\n@enduml")

      expect(texts(svg)).to include("plain row")
    end

    it "keeps a map row with no value or link as its own key" do
      svg = render("@startuml\nmap M {\n  lonely\n}\n@enduml")

      expect(texts(svg)).to include("lonely")
    end

    it "rejects an unclosed object body" do
      expect { render("@startuml\nobject A {\n  row\n@enduml") }
        .to raise_error(Sirena::Parser::ParseError, /unclosed \{/)
    end

    it "refuses an object diagram line outside its subset" do
      source = "@startuml\nobject A\nnote right of A : hi\n@enduml"

      expect { render(source) }
        .to raise_error(Sirena::Notation::PlantUML::UnsupportedConstructError,
                        /note/)
    end
  end

  describe "a tree link's head" do
    let(:head) do
      svg = render("@startjson\n{\"a\": {\"b\": 1}}\n@endjson")
      REXML::Document.new(svg).get_elements("//polygon")
        .find { |poly| poly.attributes["stroke"] == "none" }
    end

    it "is the small notched arrow, filled and not outlined" do
      points = head.attributes["points"].split.map(&:to_f)

      expect(points.size).to eq(4)
    end

    it "is 7.6 long" do
      xs = head.attributes["points"].split.map { |pt| pt.split(",").first.to_f }

      expect(xs.max - xs.min).to be_within(0.01).of(7.6)
    end
  end

  describe "edges" do
    it "reads an empty YAML document as nothing" do
      expect(boxes::YamlReader.new.call("# only a comment\n---\n")).to be_nil
    end

    it "reads a bare scalar YAML document" do
      expect(boxes::YamlReader.new.call("hello")).to eq("hello")
    end

    it "stops a mapping at a line that is not an entry" do
      value = boxes::YamlReader.new.call("a: 1\n@@@ b\n")

      expect(value).to eq({ "a" => "1" })
    end

    it "nests a block under a bare dash" do
      value = boxes::YamlReader.new.call("-\n  a: 1\n- 2\n")

      expect(value).to eq([{ "a" => "1" }, "2"])
    end

    it "reads a key with no value at the document end as an empty string" do
      value = boxes::YamlReader.new.call("a: 1\nb:\n")

      expect(value).to eq({ "a" => "1", "b" => "" })
    end

    it "reads a key with no value before a shallower line as an empty string" do
      value = boxes::YamlReader.new.call("a:\n  b:\nc: 1\n")

      expect(value).to eq({ "a" => { "b" => "" }, "c" => "1" })
    end

    it "reads a sequence at the same indent as its key" do
      value = boxes::YamlReader.new.call("a:\n- x\n- y\n")

      expect(value).to eq({ "a" => %w[x y] })
    end

    it "keeps a null YAML scalar as its text" do
      svg = render("@startyaml\nk: null\n@endyaml")

      expect(texts(svg)).to include("null")
    end

    it "shows an tag-only scalar as the blank marker" do
      expect(boxes::Text.scalar("<b></b>")).to eq(boxes::Text::BLANK)
    end

    it "gives a head with no length along the line a default axis" do
      marks = boxes::Heads.call(:association, [5.0, 5.0], [5.0, 5.0])

      expect(marks.size).to eq(1)
    end

    it "lays out a relation cycle without looping", :aggregate_failures do
      svg = render("@startuml\nobject A\nobject B\nA --> B\nB --> A\n@enduml")

      expect(texts(svg)).to include("A", "B")
    end

    it "draws a relation from an object to itself" do
      svg = render("@startuml\nobject A\nA --> A\n@enduml")

      expect(REXML::Document.new(svg).root.name).to eq("svg")
    end

    it "reads a top to bottom direction line" do
      svg = render("@startuml\ntop to bottom direction\nobject A\n@enduml")

      expect(texts(svg)).to include("A")
    end
  end
end
