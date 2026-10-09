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
  # now reads. The other class cases still raise UnsupportedConstructError
  # or are cases PlantUML itself refuses.
  rendered_ids = %w[
    java.net.sourceforge.plantuml.explain.DiagramExplainerTest--d715317341a6
    resources.vega.migration.HideShow001_Test--9be85612e170
    resources.vega.migration.HideShow004_Test--16625d433c68
    resources.vega.nonreg.group2712.down_direction--b7562ecaf08a
    resources.vega.nonreg.group2712.left_direction--817e051688df
    resources.vega.nonreg.group2712.reported_case--4d4d68cc75f8
    resources.vega.nonreg.group2712.right_direction--4bc244e3377d
    resources.vega.nonreg.group2814.class_level_note_unaffected--8b789ec547c0
    resources.vega.nonreg.group2814.field_and_method_note--dad15be25c38
    resources.vega.nonreg.group2814.reported_case--cab9ac83dbb5
    resources.vega.nonreg.group2814.reversed_order--0dac1bb4078f
    resources.vega.nonreg.group2814.stereotype_colors--2b02c27ca536
    resources.vega.nonreg.group2814.three_members--15d11a71125a
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
    resources.vega.nonreg.simple.QualifiedAssoc002--d57fb49a9920
    resources.vega.svg.interactive.SVG0006_Svek--70f5757ed2ca
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

  describe "members written type first" do
    it "reads a field as its type then its name" do
      member = parse_corpus("class A {\n+int x\n}").classes.first.body.first

      expect(member).to have_attributes(kind: :field, name: "x", type: "int",
                                        visibility: :public)
    end

    it "reads a method as its return type, name and parameters" do
      member = parse_corpus("class A {\nvoid run(int a)\n}")
               .classes.first.body.first

      expect(member).to have_attributes(kind: :method, name: "run",
                                        type: "void", parameters: "int a")
    end

    it "still refuses three words, which PlantUML reads differently" do
      expect { parse_corpus("class A {\nfinal int x\n}") }
        .to raise_error(described_class::UnsupportedConstructError)
    end
  end

  describe "notes" do
    let(:note) { parse_corpus("class A\nNOTE Left of A #red : hi").notes.first }

    it "reads the side, target, colour and inline text" do
      expect(note).to have_attributes(side: :left, target: "A", color: "#red",
                                      lines: ["hi"])
    end

    it "reads a block note up to end note" do
      source = "class A\nnote top of A <<tag>>\none\ntwo\nendnote"

      expect(parse_corpus(source).notes.first).to have_attributes(
        stereotype: "<<tag>>", lines: %w[one two]
      )
    end

    it "keeps the member a block note names" do
      source = "class A\nnote right of A::x\nhi\nend note"

      expect(parse_corpus(source).notes.first.member).to eq("x")
    end

    it "refuses inline text on a member note, as PlantUML does" do
      expect { parse_corpus("class A\nnote right of A::x : hi") }
        .to raise_error(described_class::UnsupportedConstructError)
    end

    it "refuses a note on a class not yet mentioned" do
      expect { parse_corpus("note right of Z : hi\nclass Z") }
        .to raise_error(Sirena::Parser::ParseError, /Z, which is not/)
    end

    it "refuses a note that is never closed" do
      expect { parse_corpus("class A\nnote right of A\nhi") }
        .to raise_error(Sirena::Parser::ParseError, /never closed with end/)
    end

    it "refuses a comment inside a note body" do
      expect { parse_corpus("class A\nnote right of A\n' hi\nend note") }
        .to raise_error(described_class::UnsupportedConstructError,
                        /comment in a note/)
    end

    context "when drawn" do
      let(:svg) do
        REXML::Document.new(
          Sirena.render(wrap("class A\nnote right of A #yellow : hi"),
                        notation: :plantuml),
        )
      end

      it "fills the note with its colour" do
        rect = REXML::XPath.first(svg, "//g[@id='note-0']/rect")

        expect(rect.attributes["fill"]).to eq("yellow")
      end

      it "links the note to its class with a line" do
        link = REXML::XPath.first(svg, "//g[@id='note-link-0']/path")

        expect(link).not_to be_nil
      end
    end
  end

  describe "class headers" do
    it "reads each stereotype and the generics" do
      klass = parse_corpus("class A<K,V> <<x>> <<y>>").classes.first

      expect(klass).to have_attributes(stereotypes: %w[x y], generics: "K,V")
    end

    it "reads a qualifier as the text on that end of the relation" do
      relation = parse_corpus("A [k: int] --> \"1\" B").relations.first

      expect([relation.left_multiplicity, relation.right_multiplicity])
        .to eq(["[k: int]", "1"])
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
