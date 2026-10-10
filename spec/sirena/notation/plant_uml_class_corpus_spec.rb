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

  # The x, y, width and height of the first rect under the group.
  def bounds(svg, group)
    rect = REXML::XPath.first(svg, "//g[@id='#{group}']/rect")
    %w[x y width height].to_h { |key| [key, rect.attributes[key].to_f] }
  end

  # True when the rectangle `inner` lies strictly inside `outer`.
  def enclosed?(inner, outer)
    inside, around = [inner, outer].map { |r| corners(r) }

    inside.first(2).zip(around.first(2)).all? { |i, o| i > o } &&
      inside.last(2).zip(around.last(2)).all? { |i, o| i < o }
  end

  def corners(rectangle)
    [rectangle["x"], rectangle["y"], rectangle["x"] + rectangle["width"],
     rectangle["y"] + rectangle["height"]]
  end

  # True when the rectangle `box` lies wholly above or below `other`.
  def clear_vertically?(box, other)
    box["y"] + box["height"] < other["y"] ||
      box["y"] > other["y"] + other["height"]
  end

  def circle_centre(group)
    %w[cx cy].map { |name| group.elements["circle"].attributes[name].to_f }
  end

  # The middle of each bar of the plus sign: the path runs left, right,
  # then top, bottom.
  def cross_bar_centres(group)
    d = group.get_elements("path").last.attributes["d"]
    left, y, right, _, x, top, _, bottom = d.scan(/[\d.]+/).map(&:to_f)
    [[(left + right) / 2, y], [x, (top + bottom) / 2]]
  end

  def rendered_document(body)
    REXML::Document.new(Sirena.render(wrap(body), notation: :plantuml))
  end

  def group_ids(document)
    REXML::XPath.match(document, "//g/@id").map(&:value)
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
    resources.vega.nonreg.group2846.correct_code--c4f1bf12e099
    resources.vega.nonreg.group2904.all_visibilities--00480b0ff655
    resources.vega.nonreg.group2904.diamond_at_tail--bb82b36b91be
    resources.vega.nonreg.group2904.icon_size_zero--5d137d5deadd
    resources.vega.nonreg.group2904.left_to_right--4e7a191e1721
    resources.vega.nonreg.group2904.role_tail_only--c95e6006dcac
    resources.vega.nonreg.group2904.role_without_visibility--6318bda823a1
    resources.vega.nonreg.group2917.smetana_hide_class--cda3c6a5e269
    resources.vega.nonreg.simple.QualifiedAssoc001--8c3b78057dc3
    resources.vega.nonreg.simple.QualifiedAssoc002--d57fb49a9920
    resources.vega.svg.interactive.SVG0006_Svek--70f5757ed2ca
    resources.vega.xmi.clazz.XMI0002_class--9616cd0e75d4
    resources.vega.xmi.clazz.XMI0003_class--d50636ffecaf
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
      "A -down-> B" => %i[association right],
      "A <-up- B" => %i[association left],
      "A o--------- B" => %i[aggregation left],
      "A *.r. B" => %i[composition left],
      "A ..> B" => %i[dependency right],
      "A .. B" => [:dependency, nil],
      "A -->B" => %i[association right],
      "A <|-l- B" => %i[extension left],
      "A ..|> B" => %i[implementation right],
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

    {
      "A <|-u-> B" => { left: :extension, right: :association },
      "A *.r.> B" => { left: :composition, right: :dependency },
      "A +-l-> B" => { left: :nesting, right: :association },
      "A o--|> B" => { left: :aggregation, right: :extension },
      "A --+ B" => { right: :nesting },
    }.each do |line, markers|
      it "reads the markers of #{line.inspect}" do
        relation = parse_corpus("class A\n#{line}").relations.first

        expect(relation.markers).to eq(markers)
      end
    end

    it "reads a dotted body as dashed whatever the markers" do
      relations = parse_corpus("A *.r.> B\nA *--> C").relations

      expect(relations.map(&:dashed?)).to eq([true, false])
    end

    ["A <-> B", "A <--> B"].each do |line|
      it "still refuses #{line.inspect}, which a sequence diagram also has" do
        expect { parse_corpus("class A\n#{line}") }
          .to raise_error(described_class::UnsupportedConstructError,
                          /<-> arrow/)
      end
    end

    context "when drawn with a marker on each end" do
      let(:svg) do
        rendered_document("class A\nclass B\nA <|--> B\nA *.. B\nA +-- B")
      end

      it "puts one polygon at each end of the line" do
        polygons = REXML::XPath.match(svg, "//g[@id='relation-0']/polygon")

        expect(polygons.map { |p| p.attributes["fill"] })
          .to eq(["#ffffff", "#000000"])
      end

      it "dashes a dotted line that ends in a diamond" do
        path = REXML::XPath.first(svg, "//g[@id='relation-1']/path")

        expect(path.attributes["stroke-dasharray"]).to eq("6,4")
      end

      it "draws a nested class as a circle with a cross through its centre" do
        group = REXML::XPath.first(svg, "//g[@id='relation-2']")

        expect(cross_bar_centres(group)).to eq([circle_centre(group)] * 2)
      end
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

  describe "quoted class names" do
    ['class "pkg.Name"', 'abstract class "A B"'].each do |line|
      it "names #{line.inspect} as a quoted class name" do
        expect { parse_corpus(line) }
          .to raise_error(described_class::UnsupportedConstructError,
                          /quoted class name/)
      end
    end
  end

  describe "member modifiers" do
    let(:member) do
      parse_corpus("class A {\n#{line}\n}").classes.first.body.first
    end

    {
      "{method}{abstract}{static} + run" =>
        [:method, "run", %i[abstract static]],
      "{static} count : int" => [:field, "count", [:static]],
      "{abstract} run()" => [:method, "run", [:abstract]],
      "{field} +x" => [:field, "x", []],
    }.each do |text, (kind, name, modifiers)|
      context "with #{text.inspect}" do
        let(:line) { text }

        it "reads the kind, name and modifiers" do
          expect([member.kind, member.name, member.modifiers])
            .to eq([kind, name, modifiers])
        end
      end
    end

    ["{field} run()", "{field}{method} x", "{static} int x",
     "{classifier} x", "x {static}"].each do |text|
      it "still refuses #{text.inspect}" do
        expect { parse_corpus("class A {\n#{text}\n}") }
          .to raise_error(described_class::UnsupportedConstructError)
      end
    end

    context "when drawn" do
      let(:source) do
        wrap("class A {\n{abstract} a()\n{static} s\nplain\n}")
      end
      let(:svg) do
        REXML::Document.new(Sirena.render(source, notation: :plantuml))
      end

      it "sets an abstract member in italic and no other" do
        styles = REXML::XPath.match(svg, "//text[@font-style='italic']")

        expect(styles.map(&:text)).to eq(["a()"])
      end

      it "underlines a static member" do
        lines = REXML::XPath.match(svg, "//g[@id='class-A']/line")

        expect(lines.size).to eq(2)
      end
    end

    it "draws a method written without parentheses without them" do
      svg = Sirena.render(wrap("class A {\n{method} run\n}"),
                          notation: :plantuml)

      expect(svg).to include(">run<")
    end

    it "reads static class as a class" do
      expect(parse_corpus("static class C").classes.first.kind).to eq(:class)
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
        stereotype: "<<tag>>", lines: %w[one two],
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
    let(:restyled_source) do
      "!pragma layout smetana\nhide empty members\n" \
        "skinparam nodesep 60\nleft to right direction\nclass A"
    end

    it "records each restyling line in order and applies none" do
      expect(parse_corpus(restyled_source).directives).to eq(
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

  describe "tags and hide" do
    let(:diagram) do
      parse_corpus("class A\nclass B $x $y\nB --> A\nA --> C\nhide $y")
    end

    it "reads each tag after the class header" do
      expect(parse_corpus("class B<T> <<s>> $x $y {\n}").classes.first.tags)
        .to eq(%w[x y])
    end

    it "removes a class carrying the tag, declared before the hide line" do
      expect(diagram.classes.map(&:name)).to eq(%w[A C])
    end

    it "removes the relations that touch it and keeps the rest" do
      expect(diagram.relations.map(&:right)).to eq(%w[C])
    end

    it "removes a class tagged after the hide line" do
      source = "hide $x\nclass B $x\nclass A"

      expect(parse_corpus(source).classes.map(&:name)).to eq(%w[A])
    end

    it "does nothing for a tag no class carries" do
      expect(parse_corpus("class A\nhide $z").classes.size).to eq(1)
    end

    it "refuses to hide a class that has a note" do
      source = "class A $x\nnote right of A : hi\nhide $x"

      expect { parse_corpus(source) }
        .to raise_error(described_class::UnsupportedConstructError,
                        /hide of a class with a note/)
    end

    it "draws no box for the hidden class" do
      svg = Sirena.render(wrap("class A\nclass B $x\nA --> B\nhide $x"),
                          notation: :plantuml)

      expect(svg).not_to include("class-B")
    end
  end

  describe "packages" do
    let(:source) do
      ["+package \"Hi\" as p <<Frame>> {", "class A", "}",
       "package q {", "class B", "class C", "}", "class D", "A --> D"]
        .join("\n")
    end
    let(:diagram) { parse_corpus(source) }

    it "reads the id, title, shape and icon" do
      expect(diagram.packages.first).to have_attributes(
        id: "p", title: "Hi", shape: :frame, icon: true,
      )
    end

    it "reads a bare name as both id and title, drawn as a folder" do
      expect(diagram.packages.last).to have_attributes(
        id: "q", title: "q", shape: :folder, icon: false,
      )
    end

    it "gives each class the package it was declared in" do
      expect(diagram.classes.map(&:package)).to eq(["p", "q", "q", nil])
    end

    {
      "package p {\npackage q {\n}\nclass A\n}" => /empty package/,
      "package p {\n}" => /empty package/,
      "package p <<Cloud>> {\nclass A\n}" => /package stereotype/,
      "package p {\nclass A\n}\npackage p {\nclass B\n}" => /twice/,
      "A --> B\npackage p {\nclass A\n}" => /more than one place/,
      "package p {\nA --> B\n}" => /first mentioned in a package/,
    }.each do |text, message|
      it "refuses #{text.inspect}" do
        expect { parse_corpus(text) }
          .to raise_error(described_class::UnsupportedConstructError, message)
      end
    end

    it "refuses a package that is never closed" do
      expect { parse_corpus("package p {\nclass A") }
        .to raise_error(Sirena::Parser::ParseError, /never closed with }/)
    end

    context "when drawn" do
      let(:svg) do
        REXML::Document.new(Sirena.render(wrap(source), notation: :plantuml))
      end

      it "titles each package" do
        titles = REXML::XPath.match(svg,
                                    "//g[starts-with(@id,'package-')]/text")

        expect(titles.map(&:text)).to eq(%w[Hi q])
      end

      it "draws the icon only for the + package" do
        circles = REXML::XPath.match(svg, "//g[@id='package-p']/circle")

        expect(circles.size).to eq(1)
      end

      it "gives a folder a tab and a frame none" do
        counts = %w[p q].map do |id|
          REXML::XPath.match(svg, "//g[@id='package-#{id}']/rect").size
        end

        expect(counts).to eq([1, 2])
      end

      it "encloses its own classes" do
        frame = bounds(svg, "package-q")
        box = bounds(svg, "class-C")

        expect([box["x"] > frame["x"], box["y"] > frame["y"],
                box["y"] + box["height"] < frame["y"] + frame["height"]])
          .to eq([true] * 3)
      end

      it "keeps a class outside every package clear of the frames" do
        frame = bounds(svg, "package-p")
        box = bounds(svg, "class-D")

        expect(box["y"] + box["height"]).to be < frame["y"]
      end
    end
  end

  describe "package colours" do
    {
      "#yellow" => "#FFFF00", "#FFEE00" => "#FFEE00", "#abc" => "#AABBCC"
    }.each do |written, hex|
      it "reads #{written} as #{hex} and fills the frame with it" do
        source = "package p <<Frame>> #{written} {\nclass A\n}"

        expect([parse_corpus(source).packages.first.color,
                REXML::XPath.first(rendered_document(source),
                                   "//g[@id='package-p']/rect/@fill").value])
          .to eq([hex, hex])
      end
    end

    it "leaves a package with no colour unfilled" do
      fill = REXML::XPath.first(rendered_document("package p {\nclass A\n}"),
                                "//g[@id='package-p']/rect/@fill").value

      expect(fill).to eq("none")
    end

    it "refuses a colour name it does not know" do
      expect { parse_corpus("package p #chartreuse {\nclass A\n}") }
        .to raise_error(described_class::UnsupportedConstructError,
                        /package colour name/)
    end

    it "refuses the colour written before the stereotype, as PlantUML does" do
      expect { parse_corpus("package p #red <<Frame>> {\nclass A\n}") }
        .to raise_error(described_class::UnsupportedConstructError)
    end
  end

  describe "nested packages" do
    let(:source) do
      ["package outer {", "class A", "package inner {", "class B", "}",
       "class C", "}", "class D"].join("\n")
    end
    let(:svg) { rendered_document(source) }

    it "records the package each one is written inside" do
      expect(parse_corpus(source).packages.map { |p| [p.id, p.parent] })
        .to eq([["outer", nil], ["inner", "outer"]])
    end

    it "gives each class its innermost package" do
      expect(parse_corpus(source).classes.map(&:package))
        .to eq(%w[outer inner outer] + [nil])
    end

    it "refuses an outer package whose only content is an empty one" do
      expect { parse_corpus("package o {\npackage i {\n}\n}") }
        .to raise_error(described_class::UnsupportedConstructError,
                        /empty package/)
    end

    it "draws the inner frame inside the outer one" do
      inner = bounds(svg, "package-inner")

      expect(enclosed?(inner, bounds(svg, "package-outer"))).to be(true)
    end

    it "keeps the outer package's own classes out of the inner frame" do
      inner = bounds(svg, "package-inner")
      own = %w[A C].map { |name| bounds(svg, "class-#{name}") }

      expect(own.map { |box| clear_vertically?(box, inner) })
        .to eq([true, true])
    end

    it "keeps every frame and box inside the canvas" do
      canvas = REXML::XPath.first(svg, "/svg/@height").value.to_f
      frame = bounds(svg, "package-outer")

      expect(frame["y"] + frame["height"]).to be < canvas
    end

    it "leaves the canvas margin above frames opened together" do
      stacked = rendered_document("package o {\npackage i {\nclass B\n}\n}")

      expect(bounds(stacked, "package-o")["y"]).to be >= 36.0
    end

    it "keeps the class outside every package clear of the outer frame" do
      outer = bounds(svg, "package-outer")
      loose = bounds(svg, "class-D")

      expect(loose["y"] + loose["height"]).to be < outer["y"]
    end

    it "keeps a hidden inner package's classes from drawing its frame" do
      hidden = "#{source.sub('class B', 'class B $x')}\nhide $x"

      ids = group_ids(rendered_document(hidden))

      expect([ids.include?("package-outer"), ids.include?("package-inner")])
        .to eq([true, false])
    end
  end

  describe "a package whose classes are all hidden" do
    let(:source) do
      ["package p {", "class A $x", "}", "package q {", "class C", "}",
       "class B", "hide $x"].join("\n")
    end
    let(:svg) { rendered_document(source) }

    it "draws no frame for it" do
      expect(group_ids(svg)).not_to include("package-p")
    end

    it "still draws the other package and the loose class" do
      expect(group_ids(svg)).to include("package-q", "class-C", "class-B")
    end

    it "leaves no room for the missing frame" do
      without = rendered_document("package q {\nclass C\n}\nclass B")

      expect(svg.root.attributes["height"])
        .to eq(without.root.attributes["height"])
    end
  end

  describe "association classes" do
    let(:diagram) { parse_corpus("A -- B\n(A, B) .. C") }

    it "records the pair and the owner" do
      expect(diagram.junctions.first).to have_attributes(
        from: "A", to: "B", owner: "C",
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
