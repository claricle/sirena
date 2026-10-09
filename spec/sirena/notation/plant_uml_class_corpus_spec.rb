# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"

# See the note in plant_uml_spike_spec.rb: restore the baseline registry, then
# register inside each example's isolated context.
Sirena::Notation.send(:entries).delete(:plantuml)

module PlantUmlCorpusHelpers
  CORPUS = File.expand_path("../../plantuml/class", __dir__)

  def corpus_source(id)
    File.read(File.join(CORPUS, "#{id}.puml"))
  end

  def parse_corpus(source)
    Sirena::Notation::PlantUML::Parser.new.parse(wrap(source))
  end

  def wrap(body)
    "@startuml\n#{body}\n@enduml\n"
  end
end

RSpec.describe Sirena::Notation::PlantUML do
  include PlantUmlCorpusHelpers

  include_context "with an isolated notation registry"

  before { Sirena::Notation.register(described_class) }

  # Cases the pinned PlantUML renders as a class diagram and this notation
  # now reads. The other class cases still raise UnsupportedConstructError.
  rendered_ids = %w[
    java.net.sourceforge.plantuml.explain.DiagramExplainerTest--d715317341a6
    resources.vega.migration.HideShow004_Test--16625d433c68
    resources.vega.nonreg.group2712.down_direction--b7562ecaf08a
    resources.vega.nonreg.group2712.left_direction--817e051688df
    resources.vega.nonreg.group2712.reported_case--4d4d68cc75f8
    resources.vega.nonreg.group2712.right_direction--4bc244e3377d
    resources.vega.nonreg.group2903.left_to_right--8310bfc61aae
    resources.vega.nonreg.group2903.nodesep_ranksep--7c073f601760
    resources.vega.nonreg.group2903.reported_case--fd42e1abb616
    resources.vega.nonreg.group2903.two_association_classes--5589df921b7b
    resources.vega.nonreg.group2903.without_association_class--633626f844fa
    resources.vega.nonreg.group2904.all_visibilities--00480b0ff655
    resources.vega.nonreg.group2904.diamond_at_tail--bb82b36b91be
    resources.vega.nonreg.group2904.icon_size_zero--5d137d5deadd
    resources.vega.nonreg.group2904.left_to_right--4e7a191e1721
    resources.vega.nonreg.group2904.role_tail_only--c95e6006dcac
    resources.vega.nonreg.group2904.role_without_visibility--6318bda823a1
    resources.vega.xmi.clazz.XMI0002_class--9616cd0e75d4
    resources.vega.xmi.clazz.XMI0004_class--32636d47dbd7
  ]

  rendered_ids.each do |id|
    it "renders #{id} as well-formed SVG" do
      svg = Sirena.render(corpus_source(id), notation: :plantuml)

      expect(REXML::Document.new(svg).root.name).to eq("svg")
    end
  end

  describe "relation glyphs" do
    {
      "A -down-> B" => [:association, :right],
      "A <-up- B" => [:association, :left],
      "A o--------- B" => [:aggregation, :left],
      "A *.r. B" => [:composition, :left],
      "A ..> B" => [:dependency, :right],
      "A .. B" => [:dependency, nil],
      "A -->B" => [:association, :right],
      "A <|-l- B" => [:extension, :left],
      "A ..|> B" => [:implementation, :right],
    }.each do |line, (kind, head)|
      it "reads #{line.inspect} as #{kind} with head #{head.inspect}" do
        relation = parse_corpus("class A\n#{line}").relations.first

        expect([relation.kind, relation.head]).to eq([kind, head])
      end
    end

    it "keeps the roles beside the multiplicities" do
      relation = parse_corpus('A "1"/"-priv" --> "a"/"+pub" B').relations.first

      expect(relation).to have_attributes(
        left_multiplicity: "1", left_role: "-priv",
        right_multiplicity: "a", right_role: "+pub"
      )
    end

    it "reads a role with no multiplicity" do
      relation = parse_corpus("class A\nA /\"-r\" --> B").relations.first

      expect(relation).to have_attributes(left_multiplicity: nil,
                                          left_role: "-r")
    end

    it "does not read a marker on both ends" do
      expect { parse_corpus("class A\nA <|--|> B") }
        .to raise_error(described_class::UnsupportedConstructError)
    end

    it "reads a trailing o as part of the class name, not a marker" do
      names = parse_corpus("A --oB").classes.map(&:name)

      expect(names).to eq(%w[A oB])
    end
  end

  describe "directives" do
    it "records each restyling line in order and applies none" do
      source = "!pragma layout smetana\nhide empty members\n" \
               "skinparam nodesep 60\nleft to right direction\nclass A"

      expect(parse_corpus(source).directives).to eq(
        ["!pragma layout smetana", "hide empty members",
         "skinparam nodesep 60", "left to right direction"],
      )
    end

    ["!pragma layout elk", "!pragma teoz true", "skinparam class {",
     "hide everything"].each do |line|
      it "still refuses #{line.inspect}" do
        expect { parse_corpus("#{line}\nclass A") }
          .to raise_error(described_class::UnsupportedConstructError)
      end
    end
  end

  describe "association classes" do
    let(:diagram) { parse_corpus("A -- B\n(A, B) .. C") }

    it "records the pair and the owner" do
      expect(diagram.junctions.first).to have_attributes(
        from: "A", to: "B", owner: "C"
      )
    end

    it "gives the owner a class box" do
      expect(diagram.classes.map(&:name)).to eq(%w[A B C])
    end

    it "refuses one whose pair has no relation" do
      expect { parse_corpus("class A\nclass B\n(A, B) .. C") }
        .to raise_error(described_class::UnsupportedConstructError,
                        /association class without its relation/)
    end

    it "draws a dashed line from the owner to the relation" do
      svg = Sirena.render(wrap("A -- B\n(A, B) .. C"), notation: :plantuml)
      ids = REXML::XPath.match(REXML::Document.new(svg), "//g/@id")

      expect(ids.map(&:value)).to include("junction-0")
    end
  end
end
