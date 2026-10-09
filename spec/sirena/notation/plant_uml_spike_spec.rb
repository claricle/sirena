# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rexml/document"
require "yaml"
require "sirena/notation/plantuml"

# Requiring an external notation registers it. Restore the suite's baseline
# here, then register inside the isolated context for each example so this
# spec cannot change another spec's notation inventory through load order.
Sirena::Notation.send(:entries).delete(:plantuml)

# Reads the committed case set under spec/plantuml_spike/ and summarises a
# parsed diagram the way expected.yml writes it. The arrow glyphs are spelled
# out here, independently of the parser's own table, so a parser that maps an
# arrow to the wrong kind or head cannot agree with itself.
module PlantUmlSpikeHelpers
  SPIKE_DIR = File.expand_path("../../plantuml_spike", __dir__)

  ARROW_GLYPHS = {
    extension: { left: "<|--", right: "--|>" },
    implementation: { left: "<|..", right: "..|>" },
    association: { right: "-->", left: "<--", nil => "--" },
    aggregation: { left: "o--", right: "--o" },
    composition: { left: "*--", right: "--*" },
  }.freeze

  VISIBILITY_MARKS = {
    public: "+", private: "-", protected: "#", package: "~", nil => ""
  }.freeze

  def spike_cases
    Dir.glob(File.join(SPIKE_DIR, "cases", "*.puml"))
  end

  def case_name(path)
    File.basename(path, ".puml")
  end

  def case_source(name)
    File.read(File.join(SPIKE_DIR, "cases", "#{name}.puml"))
  end

  # The case's source with its `'` comment lines removed, so a construct is
  # only credited to a case whose code, not its comment, shows it.
  def code_source(name)
    case_source(name).lines.grep_v(/\A[ \t]*'/).join
  end

  def expected_summaries
    YAML.load_file(File.join(SPIKE_DIR, "expected.yml"))
  end

  def subset
    YAML.load_file(File.join(SPIKE_DIR, "subset.yml"))
  end

  def parse_plantuml(source)
    Sirena::Notation::PlantUML::Parser.new.parse(source)
  end

  def summary(diagram)
    class_lines = diagram.classes.flat_map do |klass|
      ["#{klass.kind} #{klass.name}",
       *klass.body.map { |member| "  #{member_line(member)}" }]
    end
    class_lines + diagram.relations.map { |relation| relation_line(relation) }
  end

  def member_line(member)
    line = "#{VISIBILITY_MARKS.fetch(member.visibility)}#{member.name}"
    line += "(#{member.parameters})" if member.kind == :method
    line += " : #{member.type}" if member.type
    line
  end

  def relation_line(relation)
    glyph = ARROW_GLYPHS.fetch(relation.kind).fetch(relation.head)
    [relation.left, quoted(relation.left_multiplicity), glyph,
     quoted(relation.right_multiplicity), relation.right,
     relation.label && ": #{relation.label}"].compact.join(" ")
  end

  def quoted(multiplicity)
    multiplicity && %("#{multiplicity}")
  end

  def wrap(*lines)
    ["@startuml", *lines, "@enduml", ""].join("\n")
  end

  # The names of the cases whose parsed summary is not the one expected.yml
  # holds.
  def case_mismatches
    spike_cases.filter_map do |path|
      name = case_name(path)
      actual = summary(parse_plantuml(File.read(path)))
      [name, actual] unless actual == expected_summaries.fetch(name)
    end
  end

  # One message per construct whose listed case lacks the construct's code.
  # `line_comment` is the one construct that lives in a comment, so it is
  # matched against the whole source.
  def subset_misses
    subset.flat_map do |id, entry|
      entry["cases"].flat_map do |name|
        source = id == "line_comment" ? case_source(name) : code_source(name)
        entry["patterns"].filter_map do |pattern|
          "#{id}: #{name} lacks /#{pattern}/" unless
            source.match?(Regexp.new(pattern))
        end
      end
    end
  end

  # The UnsupportedConstructError parsing `source` raises, or nil when the
  # parse succeeds, so a spec can assert on its attributes in one expectation.
  def refusal_of(source)
    parse_plantuml(source)
    nil
  rescue Sirena::Notation::PlantUML::UnsupportedConstructError => e
    e
  end

  # True when parsing `source` accepts it as PlantUML, including by refusing
  # a construct; false only when the engine's detection error says it is not.
  def parsed_as_plantuml?(source)
    parse_plantuml(source)
    true
  rescue Sirena::Engine::DiagramTypeError
    false
  rescue Sirena::Error
    true
  end

  # Runs `code` in a fresh Ruby that sees only lib/; returns whether it
  # exited cleanly and its output.
  def ruby_output(code)
    out, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-e", code)
    [status.success?, out]
  end

  def rendering_failures
    spike_cases.filter_map { |path| rendering_failure(path) }
  end

  def rendering_failure(path)
    source = File.read(path)
    explicit = Sirena.render(source, notation: :plantuml)
    inferred = Sirena.render(source, path: path)
    document = REXML::Document.new(explicit)
    diagram = parse_plantuml(source)

    case_name(path) unless rendering_matches?(explicit, inferred, document,
                                              diagram)
  rescue REXML::ParseException
    case_name(path)
  end

  def rendering_matches?(explicit, inferred, document, diagram)
    explicit == inferred && preserved_text?(document, diagram) &&
      rendered_relation_count(document) == diagram.relations.size
  end

  def preserved_text?(document, diagram)
    texts = REXML::XPath.match(document, "//text").map(&:text)
    (expected_render_texts(diagram) - texts).empty?
  end

  def expected_render_texts(diagram)
    class_texts = diagram.classes.flat_map do |klass|
      [klass.name, *klass.body.map { |member| member_line(member) }]
    end
    relation_texts = diagram.relations.flat_map do |relation|
      [relation.label, relation.left_multiplicity,
       relation.right_multiplicity].compact
    end
    class_texts + relation_texts
  end

  def rendered_relation_count(document)
    REXML::XPath.match(
      document, "//g[starts-with(@id, 'relation-')]/path"
    ).size
  end

  def pipeline_attributes(notation)
    have_attributes(
      type: :class_diagram,
      diagram: an_instance_of(notation::Diagram),
      transform: notation::Layout,
      renderer: notation::Renderer,
    )
  end
end

RSpec.describe Sirena::Notation::PlantUML do
  include PlantUmlSpikeHelpers

  include_context "with an isolated notation registry"

  let(:plantuml) { described_class }
  let(:unsupported_error) { plantuml::UnsupportedConstructError }

  before { Sirena::Notation.register(plantuml) }

  describe "the notation's public surface" do
    it "identifies as :plantuml" do
      expect(plantuml.id).to eq(:plantuml)
    end

    it "claims the .puml extension, lowercase, dotted and frozen" do
      expect(plantuml.extensions).to eq([".puml"]).and be_frozen
    end

    it "lists the class and sequence diagram types" do
      expect(plantuml.types)
        .to eq(%i[class_diagram sequence_diagram]).and be_frozen
    end
  end

  describe ".claims?" do
    {
      "@startuml opener" => ["@startuml\nclass A\n@enduml\n", true],
      "opener after blank and comment lines" =>
        ["\n  \n' note\n@startuml\n", true],
      "opener with CRLF line ends" => ["@startuml\r\nclass A\r\n", true],
      "opener with lone CR line ends" => ["' c\r@startuml\rclass A\r", true],
      "opener after a byte order mark" => ["\uFEFF@startuml\n", true],
      "opener with a diagram name" => ["@startuml foo\n", true],
      "Mermaid source" => ["classDiagram\n  class A\n", false],
      "empty source" => ["", false],
      "opener after real content" => ["class A\n@startuml\n", false],
      "a lookalike word" => ["@startumlx\n", false],
      "a lookalike word with an underscore" => ["@startuml_x\n", false],
      "an upper-case opener" => ["@STARTUML\n", false],
      "an indented opener" => ["  @startuml\n", true],
      "an opener after a form feed" => ["\f@startuml\nclass A\n", true],
      "an opener after a NUL" => ["\0@startuml\nclass A\n", true],
      "an opener after a vertical tab and blank line" =>
        ["\v\n@startuml\n", true],
      "an opener after a padded comment line" =>
        ["\f' c\n@startuml\n", true],
      "an opener after a CRLF blank line" => ["\r\n@startuml\r\n", true],
    }.each do |label, (source, claimed)|
      it "is #{claimed} for #{label}" do
        expect(plantuml.claims?(source)).to be(claimed)
      end
    end

    # 10a section 4: claims? never raises for any String, because the CLI
    # reads raw bytes.
    [
      ["binary-tagged high bytes", "\xFF\xFE@startuml".b],
      ["invalid UTF-8", "@startuml\n\xC3(\n"],
      ["UTF-16 tagged", "@startuml".encode(Encoding::UTF_16LE)],
    ].each do |label, source|
      it "does not raise for #{label}" do
        expect { plantuml.claims?(source) }.not_to raise_error
      end
    end

    it "claims a binary-tagged source that holds a valid opener" do
      expect(plantuml.claims?("@startuml\n".b)).to be(true)
    end

    it "is false for something that is not a String" do
      expect(plantuml.claims?(nil)).to be(false)
    end
  end

  describe "the committed case set" do
    it "holds 15 to 20 cases" do
      expect(spike_cases.size).to be_between(15, 20)
    end

    it "has an expected summary for every case and no orphan summary" do
      expect(expected_summaries.keys.sort)
        .to eq(spike_cases.map { |path| case_name(path) }.sort)
    end

    it "parses every case to exactly its expected summary" do
      expect(case_mismatches).to eq([])
    end

    it "renders every case through explicit and extension resolution" do
      expect(rendering_failures).to eq([])
    end
  end

  describe "the public notation pipeline" do
    it "is registered through the public registry" do
      expect(Sirena::Notation.fetch(:plantuml)).to equal(plantuml)
    end

    it "returns a frozen Parsed naming its local layout and renderer" do
      parsed = plantuml.parse(case_source("01-empty-class"))

      expect(parsed).to be_frozen.and pipeline_attributes(plantuml)
    end

    it "propagates unsupported constructs instead of partially rendering" do
      source = wrap("class A", "enum Color")

      expect { Sirena.render(source, notation: :plantuml) }
        .to raise_error(unsupported_error, /enum is not yet supported/)
    end
  end

  describe "the enumerated subset" do
    it "maps every construct to at least one case" do
      expect(subset.reject { |_, entry| entry["cases"].any? }.keys).to eq([])
    end

    it "lists, for every construct, only cases that exercise it" do
      expect(subset_misses).to eq([])
    end

    it "names only cases that exist" do
      named = subset.values.flat_map { |entry| entry["cases"] }.uniq

      expect(named - spike_cases.map { |path| case_name(path) }).to eq([])
    end

    it "uses every case for at least one construct" do
      named = subset.values.flat_map { |entry| entry["cases"] }.uniq

      expect(spike_cases.map { |path| case_name(path) } - named).to eq([])
    end
  end

  describe "a construct outside the subset" do
    {
      "package Domain #red {" => ["package", 3],
      "+package Domain #red {" => ["package", 3],
      "namespace Domain {" => ["namespace", 3],
      "enum Color" => ["enum", 3],
      "title My diagram" => ["title", 3],
      "!include other.puml" => ["preprocessor directive", 3],
      "/' block comment '/" => ["block comment", 3],
      "class A extends B" => ["class declaration form", 3],
      "class \"Long Name\" as L" => ["class declaration form", 3],
      "class A { +x : int }" => ["class declaration form", 3],
      "participant Alice" => ["participant", 3],
      "A-->B" => ["statement", 3],
      "A --> B :" => ["statement", 3],
      'A "" --> B' => ["statement", 3],
      "}" => ["statement", 3],
      "@startuml" => ["second diagram", 3],
      "final class A" => ["statement", 3],
      "hide A --> B" => ["hide", 3],
      "A --> B C" => ["statement", 3],
      "left to right direction x" => ["statement", 3],
      "abstract A" => ["class declaration form", 3],
      "A ->> B" => ["single-dash arrow", 3],
      "A <<- B" => ["single-dash arrow", 3],
      "titles x" => ["statement", 3],
      "@STARTUML" => ["statement", 3],
      "@startuml_x" => ["statement", 3],
      "ENUM Color" => ["enum", 3],
      "PACKAGE Domain #red {" => ["package", 3],
      "CLASS A extends B" => ["class declaration form", 3],
      "CLASS A <<entity>>" => ["stereotype", 3],
      "STATIC CLASS A" => ["class declaration form", 3],
      "STATIC CLASS A <<entity>>" => ["stereotype", 3],
      "A -DOWN-> B" => ["arrow direction or length", 3],
      "State --> Idle :" => ["statement", 3],
      "A --> A : owns /' c '/" => ["block comment", 3],
      "A /' c '/ --> A" => ["block comment", 3],
      "A --> A /' c '/" => ["block comment", 3],
      "class B /' c '/" => ["block comment", 3],
      "class B /' opens here" => ["block comment", 3],
      "A --> A : label \\" => ["line continuation", 3],
      "class B \\" => ["line continuation", 3],
      "' comment \\" => ["line continuation", 3],
      "\\" => ["line continuation", 3],
      "Set <|-- B C" => ["statement", 3],
      'Node "1" --> B C' => ["statement", 3],
    }.each do |line, (construct, number)|
      it "names #{construct.inspect} for #{line.inspect}" do
        expect(refusal_of(wrap("class A", line)))
          .to have_attributes(construct: construct, line: number)
      end
    end

    {
      "-- " => ["member separator", 3],
      "==" => ["member separator", 3],
      ".." => ["member separator", 3],
      "+run(" => ["member declaration", 3],
      "x : a(b" => ["member declaration", 3],
      "+cb : Func(int)" => ["member declaration", 3],
      "x : int {abstract}" => ["member modifier", 3],
      "+foo() : void {static}" => ["member modifier", 3],
      "x : int <<ro>>" => ["stereotype", 3],
      "__" => ["member separator", 3],
      "____" => ["member separator", 3],
      "+run() junk" => ["member declaration", 3],
      "x :" => ["member declaration", 3],
      "+m(a(b)) : x" => ["member declaration", 3],
      "{classifier} x" => ["member modifier", 3],
      "x : int {STATIC}" => ["member modifier", 3],
      "x : int {Static}" => ["member modifier", 3],
      "{CLASSIFIER} x" => ["member modifier", 3],
      "@startuml" => ["second diagram", 3],
      "@startuml_x" => ["member declaration", 3],
      "x : int {field}" => ["member modifier", 3],
      "x : int {METHOD}" => ["member modifier", 3],
      "!define X +x" => ["preprocessor directive", 3],
      "!define X {static}" => ["preprocessor directive", 3],
      "!define X <<s>>" => ["preprocessor directive", 3],
      "/' << '/" => ["block comment", 3],
      "/' {static} '/" => ["block comment", 3],
      "x : int /' c '/" => ["block comment", 3],
      "+run() /' c '/" => ["block comment", 3],
      "x /' c '/" => ["block comment", 3],
      "x : int /' opens here" => ["block comment", 3],
      "x : int \\" => ["line continuation", 3],
      "+run() \\" => ["line continuation", 3],
      "' comment \\" => ["line continuation", 3],
      "/' block comment '/" => ["block comment", 3],
    }.each do |line, (construct, number)|
      it "names #{construct.inspect} for the member #{line.inspect}" do
        expect(refusal_of(wrap("class A {", line, "}")))
          .to have_attributes(construct: construct, line: number)
      end
    end

    # Written out here, not read from the implementation's own list, so a
    # keyword dropped from the implementation cannot also drop out of the spec.
    %w[
      action actor agent analog annotation archimate artifact binary boundary
      card circle cloud clock collections component concise control database
      dataclass diamond entity enum exception file folder frame hexagon json
      label map metaclass network node nwdiag object package packetdiag
      participant person port portin portout process protocol queue record
      rectangle relationship robust stack state storage struct usecase yaml
      allow_mixing allowmixing caption footer header hide hnote legend
      namespace newpage note remove restore rnote scale set show skinparam
      stereotype title together
    ].each do |keyword|
      it "names the keyword #{keyword.inspect} as its own construct" do
        expect(refusal_of(wrap("class A", "#{keyword} x")))
          .to have_attributes(construct: keyword, line: 3)
      end
    end

    it "is a Sirena::Error so the engine propagates it unwrapped" do
      expect(unsupported_error.ancestors).to include(Sirena::Error)
    end

    it "says not yet supported, names the construct, the line and the text" do
      expect { parse_plantuml(wrap("class A", "enum Color")) }
        .to raise_error(unsupported_error,
                        "PlantUML enum is not yet supported (line 3): " \
                        '"enum Color"')
    end

    it "keeps a lone apostrophe after text as text, as PlantUML does" do
      diagram = parse_plantuml(wrap("class A {", "x : int ' not a comment", "}",
                                    "A --> A : it's"))

      expect(summary(diagram)).to eq(["class A", "  x : int ' not a comment",
                                      "A --> A : it's"])
    end

    it "takes a backslash-ended comment before the opener as PlantUML does" do
      source = "' note \\\n#{wrap('class A')}"

      expect(parse_plantuml(source).classes.map(&:name)).to eq(["A"])
    end

    it "keeps escape sequences and markup in text as written" do
      diagram = parse_plantuml(wrap('A "1\\n2" --> A : <b>left</b>\\nright'))

      expect(diagram.relations.first).to have_attributes(
        left_multiplicity: '1\\n2', label: '<b>left</b>\\nright',
      )
    end

    it "quotes the offending text so control bytes cannot reach a terminal" do
      expect { parse_plantuml(wrap("enum \e[31mX")) }
        .to raise_error(unsupported_error, /"enum \\e\[31mX"/)
    end

    it "shortens a very long offending line" do
      expect(refusal_of(wrap("enum #{'x' * 500}"))).to have_attributes(
        message: "PlantUML enum is not yet supported (line 2): " \
                 "\"enum #{'x' * 52}...\"",
      )
    end

    it "never returns a partial diagram when the unsupported line is last" do
      full = case_source("16-full-example")
      source = full.sub("@enduml", "enum Late\n@enduml")

      expect { parse_plantuml(source) }.to raise_error(unsupported_error)
    end

    it "reports the first unsupported line when several are present" do
      expect(refusal_of(wrap("enum A", "note over B")))
        .to have_attributes(construct: "enum", line: 2)
    end

    it "refuses to redeclare a class as another kind" do
      expect(refusal_of(wrap("class A", "interface A")))
        .to have_attributes(construct: "redeclaration as another kind",
                            line: 3)
    end

    it "refuses to redeclare a class declared by an earlier body" do
      expect(refusal_of(wrap("abstract class A {", "}", "class A")))
        .to have_attributes(construct: "redeclaration as another kind")
    end
  end

  describe "classes" do
    it "keeps a class once, in order of first mention" do
      diagram = parse_plantuml(wrap("B --> A", "class A", "A --> C"))

      expect(diagram.classes.map(&:name)).to eq(%w[B A C])
    end

    %w[A1 Order_Line _x].each do |name|
      it "accepts the class name #{name.inspect}" do
        diagram = parse_plantuml(wrap("class #{name}"))

        expect(diagram.classes.map(&:name)).to eq([name])
      end
    end

    %w[1A a.b].each do |name|
      it "refuses the class name #{name.inspect}" do
        expect { parse_plantuml(wrap("class #{name}")) }
          .to raise_error(unsupported_error)
      end
    end

    it "gives a member to the class whose body holds it, not an earlier one" do
      diagram = parse_plantuml(wrap("A --> B", "class A {", "+x", "}"))

      expect(summary(diagram)).to eq(["class A", "  +x", "class B", "A --> B"])
    end

    # PlantUML 1.2026.6 reads `A --> B` alone as a sequence diagram and each
    # of these as a class diagram (data-diagram-type in the SVG it writes).
    {
      "a declaration" => ["class C", "A --> B"],
      "a left multiplicity" => ['A "1" --> B'],
      "a right multiplicity" => ['A --> "*" B'],
      "a plain association" => ["A --> B", "B -- C"],
      "an extension" => ["A --> B", "C <|-- A"],
      "an aggregation" => ["A --> B", "C o-- A"],
      "a declaration after the arrows" => ["A --> B : uses", "interface B"],
    }.each do |evidence, lines|
      it "reads arrows as a class diagram once it holds #{evidence}" do
        expect { parse_plantuml(wrap(*lines)) }.not_to raise_error
      end
    end

    {
      "one arrow" => [["A --> B"], 2],
      "a reversed arrow" => [["A <-- B"], 2],
      "a label" => [["A --> B : uses"], 2],
      "two arrows" => [["A --> B", "B <-- C : x"], 2],
      "a title line and an arrow" => [["title --> T", "A --> B"], 3],
      "an arrow and a title line" => [["A --> B", "title --> T"], 2],
      "a word that only starts with title" => [["titled --> T"], 2],
      "title on the right" => [["T --> title"], 2],
      "title inside a label" => [["A --> B : see title here"], 2],
    }.each do |shape, (lines, line)|
      it "refuses #{shape} alone, which PlantUML draws as a sequence diagram" do
        expect(refusal_of(wrap(*lines)))
          .to have_attributes(construct: "sequence diagram", line: line)
      end
    end

    # PlantUML reads a line that starts with one of these words and a space as
    # that global command in a sequence diagram, so it is no arrow there. With
    # no other sequence arrow the source is a class diagram and the line is a
    # link between classes of those names.
    {
      "title" => ["title --> T"],
      "upper case Caption" => ["Caption --> T"],
      "a tab after footer" => ["footer\t--> T"],
      "header and a reversed arrow" => ["header <-- T"],
      "legend and mainframe" => ["legend --> T", "mainframe --> U"],
      "the same word twice" => ["title --> T", "title --> U"],
    }.each do |shape, lines|
      it "reads #{shape} before an arrow as a class diagram" do
        expect(parse_plantuml(wrap(*lines)).relations.map(&:left))
          .to eq(lines.map { |line| line.split(/[ \t]/).first })
      end
    end

    it "gives an implicit class the :class kind" do
      expect(summary(parse_plantuml(wrap("A -- B"))))
        .to eq(["class A", "class B", "A -- B"])
    end

    it "lets a declaration give an implicit class its kind" do
      diagram = parse_plantuml(wrap("A --> B", "interface B"))

      expect(summary(diagram))
        .to eq(["class A", "interface B", "A --> B"])
    end

    it "merges the members of a class opened twice" do
      diagram = parse_plantuml(wrap("class A {", "+x : int", "}",
                                    "class A {", "+y : int", "}"))

      expect(diagram.classes.first.body.map(&:name)).to eq(%w[x y])
    end

    it "keeps a field's type text whole, brackets and generics included" do
      diagram = parse_plantuml(wrap("class A {", "+items : List<String>[]",
                                    "}"))

      expect(diagram.classes.first.body.first.type).to eq("List<String>[]")
    end

    it "accepts tabs and extra spaces around the statements" do
      diagram = parse_plantuml(wrap("\tclass   A  {  ", "\t\t+x\t:\tint", "}",
                                    "A  \"1\"  -->  \"2\"  A"))

      expect(summary(diagram)).to eq(["class A", "  +x : int",
                                      'A "1" --> "2" A'])
    end

    it "freezes the diagram, its collections and its records" do
      diagram = parse_plantuml(wrap("class A {", "+x", "}", "A --> A"))

      klass = diagram.classes.first

      expect([diagram, diagram.classes, klass, klass.body, klass.body.first,
              diagram.relations, diagram.relations.first])
        .to all(be_frozen)
    end
  end

  describe "the wrapper" do
    {
      "no @startuml" => ["class A\n", Sirena::Engine::DiagramTypeError],
      "an empty source" => ["", Sirena::Engine::DiagramTypeError],
      "Mermaid source" => ["classDiagram\n  class A\n",
                           Sirena::Engine::DiagramTypeError],
    }.each do |label, (source, error_class)|
      it "raises the engine's own detection error for #{label}" do
        expect { parse_plantuml(source) }.to raise_error(
          error_class,
          "Unable to detect diagram type from source. " \
          "Source must start with one of: @startuml",
        )
      end
    end

    it "raises a ParseError when @enduml is missing" do
      expect { parse_plantuml("@startuml\nclass A\n") }
        .to raise_error(Sirena::Parser::ParseError, /missing @enduml/)
    end

    it "reports missing @enduml, not an unclosed body, once the body closed" do
      expect { parse_plantuml("@startuml\nclass A {\n}\n") }
        .to raise_error(Sirena::Parser::ParseError, /missing @enduml/)
    end

    it "reports an unclosed body when the source ends inside it" do
      expect { parse_plantuml("@startuml\nclass A {\n+x\n") }
        .to raise_error(Sirena::Parser::ParseError,
                        /class A.*opened on line 2.*never closed/)
    end

    it "raises a ParseError when a class body is never closed" do
      expect { parse_plantuml(wrap("class A {", "+x")) }
        .to raise_error(Sirena::Parser::ParseError,
                        /class A.*opened on line 2.*never closed/)
    end

    it "refuses real content after @enduml" do
      expect(refusal_of("@startuml\nclass A\n@enduml\nclass B\n"))
        .to have_attributes(construct: "content after @enduml", line: 4)
    end

    it "accepts blank lines and comments after @enduml" do
      diagram = parse_plantuml("@startuml\nclass A\n@enduml\n\n' done\n")

      expect(diagram.classes.map(&:name)).to eq(["A"])
    end

    {
      "an empty body" => "@startuml\n@enduml\n",
      "a comment-only body" => "@startuml\n' only a comment\n@enduml\n",
      "a blank-line body" => "@startuml\n\n  \n@enduml\n",
    }.each do |label, source|
      it "refuses #{label}, which PlantUML draws as a welcome page" do
        expect(refusal_of(source))
          .to have_attributes(construct: "empty diagram")
      end
    end

    it "reads a body with one class and no relation" do
      expect(parse_plantuml(wrap("class A")).classes.map(&:name)).to eq(["A"])
    end

    it "reads a body with one relation and no declaration" do
      expect(parse_plantuml(wrap("A <|-- B")).relations.size).to eq(1)
    end

    it "refuses a second diagram in the same file" do
      source = "@startuml\nclass A\n@enduml\n@startuml\n@enduml\n"

      expect { parse_plantuml(source) }
        .to raise_error(unsupported_error, /second diagram/)
    end

    it "refuses a diagram name after @startuml" do
      expect(refusal_of("@startuml foo\n@enduml\n"))
        .to have_attributes(construct: "diagram name")
    end

    it "accepts CRLF line ends" do
      diagram = parse_plantuml("@startuml\r\nclass A\r\nA --> B\r\n@enduml\r\n")

      expect(diagram.classes.map(&:name)).to eq(%w[A B])
    end

    it "reads abstract and class separated by any tabs and spaces" do
      kinds = ["abstract class", "abstract\tclass", "abstract\t class",
               "abstract \t  class"].map do |keyword|
        parse_plantuml(wrap("#{keyword} A")).classes.first.kind
      end

      expect(kinds).to all(eq(:abstract))
    end

    it "accepts a byte order mark before @startuml" do
      expect(parse_plantuml("\uFEFF@startuml\nclass A\n@enduml\n").classes.size)
        .to eq(1)
    end

    it "accepts a lone CR as a line end" do
      diagram = parse_plantuml("@startuml\rclass A\rA --> B\r@enduml\r")

      expect(diagram.classes.map(&:name)).to eq(%w[A B])
    end

    it "accepts a source with no final newline" do
      expect(parse_plantuml("@startuml\nclass A\n@enduml").classes.size)
        .to eq(1)
    end

    it "raises a ParseError for source that is not valid UTF-8" do
      expect { parse_plantuml("@startuml\nclass \xC3(\n@enduml\n") }
        .to raise_error(Sirena::Parser::ParseError, /not valid UTF-8/)
    end

    it "reads a binary-tagged source that holds valid UTF-8" do
      expect(parse_plantuml("@startuml\nclass A\n@enduml\n".b).classes.size)
        .to eq(1)
    end

    it "refuses invalid UTF-8 inside a comment in a binary-tagged source" do
      expect { parse_plantuml("@startuml\n' \xC3(\nclass A\n@enduml\n".b) }
        .to raise_error(Sirena::Parser::ParseError, /not valid UTF-8/)
    end

    it "leaves the encoding of an unfrozen source as it found it" do
      source = "@startuml\nclass A\n@enduml\n".b
      parse_plantuml(source)

      expect(source.encoding).to eq(Encoding::BINARY)
    end

    ["@startuml\n@enduml\n", "@startuml foo\n@enduml\n",
     "\f@startuml\n@enduml\n", "\0@startuml\n@enduml\n",
     "\v\n@startuml\n@enduml\n", "\f' c\n@startuml\n@enduml\n",
     "@startumlé\n@enduml\n", "@startuml_x\n", "@STARTUML\n",
     "class A\n"].each do |source|
      it "treats #{source.inspect} as the opener exactly when claims? does" do
        expect(parsed_as_plantuml?(source)).to eq(plantuml.claims?(source))
      end
    end
  end

  describe "loading" do
    let(:both_errors_script) do
      <<~RUBY
        require "sirena/notation/plantuml"
        parser = Sirena::Notation::PlantUML::Parser.new
        ["class A\\n", "@startuml\\nclass A\\n"].each do |source|
          parser.parse(source)
        rescue StandardError => e
          puts e.class
        end
      RUBY
    end

    # 10a section 3: an external notation is loaded by its consumer. The
    # spike must therefore add nothing to what `require "sirena"` loads.
    it "is not loaded by require \"sirena\"" do
      code = 'require "sirena"; ' \
             "puts defined?(Sirena::Notation::PlantUML).inspect"

      expect(ruby_output(code)).to eq([true, "nil\n"])
    end

    it "loads and parses when required on its own" do
      code = 'require "sirena/notation/plantuml"; ' \
             "puts Sirena::Notation::PlantUML::Parser.new.parse(" \
             '"@startuml\nclass A\n@enduml\n").classes.size'

      expect(ruby_output(code)).to eq([true, "1\n"])
    end

    it "registers and renders when required on its own" do
      code = 'require "sirena/notation/plantuml"; ' \
             'puts Sirena.render("@startuml\\nclass A\\n@enduml\\n", ' \
             'notation: :plantuml).start_with?("<svg")'

      expect(ruby_output(code)).to eq([true, "true\n"])
    end

    it "raises the engine's and the parser's errors when required on its own" do
      expect(ruby_output(both_errors_script)).to eq(
        [true, "Sirena::Engine::DiagramTypeError\nSirena::Parser::ParseError\n"],
      )
    end
  end
end
