# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

Sirena::Notation.send(:entries).delete(:plantuml)

RSpec.describe Sirena::Notation::PlantUML::PortionVisibility do
  include_context "with an isolated notation registry"

  let(:corpus) { File.expand_path("../../../plantuml/class", __dir__) }
  let(:classes) do
    <<~PUML.chomp
      class A <<s>> <<t>> {
        -name : String
        +run() : void
      }
      class B <<t>> {
        +id : long
        +stop() : void
      }
    PUML
  end

  before { Sirena::Notation.register(Sirena::Notation::PlantUML) }

  def parse(source)
    Sirena::Notation::PlantUML::Parser.new.parse(source)
  end

  def corpus_class(id, name)
    source = File.read(File.join(corpus, "#{id}.puml"))
    parse(source).classes.find { |klass| klass.name == name }
  end

  def shown(*lines)
    diagram = parse("@startuml\n#{classes}\n#{lines.join("\n")}\n@enduml\n")
    diagram.classes.to_h do |klass|
      [klass.name, [klass.body.map(&:name), klass.stereotypes]]
    end
  end

  everything = { "A" => [%w[name run], %w[s t]], "B" => [%w[id stop], %w[t]] }

  {
    [] => everything,
    ["hide members"] => { "A" => [[], %w[s t]], "B" => [[], %w[t]] },
    ["hide attributes"] => { "A" => [%w[run], %w[s t]],
                             "B" => [%w[stop], %w[t]] },
    ["hide fields"] => { "A" => [%w[run], %w[s t]], "B" => [%w[stop], %w[t]] },
    ["hide methods"] => { "A" => [%w[name], %w[s t]],
                          "B" => [%w[id], %w[t]] },
    ["hide B members"] => everything.merge("B" => [[], %w[t]]),
    ["hide <<s>> members"] => everything.merge("A" => [[], %w[s t]]),
    ["hide members", "show B methods"] => { "A" => [[], %w[s t]],
                                            "B" => [%w[stop], %w[t]] },
    ["show B methods", "hide members"] => { "A" => [[], %w[s t]],
                                            "B" => [[], %w[t]] },
    ["hide stereotype"] => { "A" => [%w[name run], []],
                             "B" => [%w[id stop], []] },
    ["hide A stereotype"] => everything.merge("A" => [%w[name run], []]),
    ["hide <<t>> stereotype"] => { "A" => [%w[name run], %w[s]],
                                   "B" => [%w[id stop], []] },
    ["hide stereotype", "show <<s>> stereotype"] =>
      everything.merge("A" => [%w[name run], %w[s]], "B" => [%w[id stop], []]),
    ["hide empty members"] => everything,
    ["hide circle"] => everything,
  }.each do |lines, expected|
    it "keeps #{expected.inspect} after #{lines.inspect}" do
      expect(shown(*lines)).to eq(expected)
    end
  end

  it "applies a rule written before the class it hides" do
    source = "@startuml\nhide members\nclass A {\n  +x : int\n}\n@enduml\n"

    expect(parse(source).classes.first.body).to eq([])
  end

  it "reads hide empty members as itself, not as a class named empty" do
    source = "@startuml\nclass empty {\n  +x : int\n}\n" \
             "hide empty members\n@enduml\n"

    expect(parse(source).classes.first.body.map(&:name)).to eq(%w[x])
  end

  it "keeps the methods of B alone in HideShow004" do
    id = "resources.vega.migration.HideShow004_Test--16625d433c68"

    expect(%w[A B C D].map { |name| corpus_class(id, name).body.map(&:name) })
      .to eq([[], %w[run], [], []])
  end

  it "keeps <<Entity>> but not <<focus>> in HideShow001" do
    id = "resources.vega.migration.HideShow001_Test--9be85612e170"

    expect(corpus_class(id, "Access").stereotypes).to eq(%w[Entity])
  end

  it "draws no text for a hidden member" do
    source = "@startuml\nhide A methods\n#{classes}\n@enduml\n"
    svg = REXML::Document.new(Sirena.render(source, notation: :plantuml))
    texts = REXML::XPath.match(svg, "//g[@id='class-A']//text").map(&:text)

    expect([texts.grep(/name/).size, texts.grep(/run/)]).to eq([1, []])
  end
end
