# frozen_string_literal: true

require "spec_helper"

# Annotations and free-text members inside a class body, and after a colon.
# Every accept and reject below was checked against mmdc 11.12.0.
RSpec.describe Sirena::Parser::ClassDiagramParser, "#parse annotations and members" do
  include ClassBodyParsing

  let(:parser) { described_class.new }

  describe "an annotation in a class body" do
    {
      "alone" => ["<<interface>>", "interface"],
      "before a member" => ["<<interface>>\n+m()", "interface"],
      "after a member" => ["+m()\n<<interface>>", "interface"],
      "indented" => ["  <<interface>>  ", "interface"],
      "with a space in it" => ["<<a b>>", "a b"],
      "empty" => ["<<>>", ""],
      "closed by the last >>" => ["<<a>>b>>", "a>>b"]
    }.each do |name, (body, stereotype)|
      it "reads #{name} as the stereotype #{stereotype.inspect}" do
        expect(parse_class(body).stereotype).to eq(stereotype)
      end
    end

    it "keeps the first annotation, as mmdc does" do
      expect(parse_class("<<interface>>\n<<abstract>>").stereotype)
        .to eq("interface")
    end

    it "keeps the first annotation over a later header or standalone one" do
      diagram = parser.parse("classDiagram\nclass A {\n<<interface>>\n}\nclass A <<abstract>>\n<<enum>> A\n")

      expect(diagram.entities.first.stereotype).to eq("interface")
    end

    it "reads an annotation after a colon at the end of the source" do
      diagram = parser.parse("classDiagram\nA : <<interface>>")

      expect([diagram.entities.first.stereotype, diagram.entities.first.attributes]).to eq(["interface", []])
    end

    it "keeps the annotation on the class header over one in the body" do
      diagram = parser.parse("classDiagram\nclass A <<interface>> {\n<<abstract>>\n}\n")

      expect(diagram.entities.first.stereotype).to eq("interface")
    end

    it "reads an annotation on the closing brace line" do
      diagram = parser.parse("classDiagram\nclass A {\n<<interface>>}\n")

      expect(diagram.entities.first.stereotype).to eq("interface")
    end

    it "reads an annotation after a colon" do
      diagram = parser.parse("classDiagram\nA : <<interface>>\n")

      expect(diagram.entities.first.stereotype).to eq("interface")
    end

    it "does not read an annotation followed by text as one" do
      entity = parse_class("<<interface>> +m()")

      expect(entity.stereotype).to be_nil
      expect(entity.class_methods.map(&:name)).to eq(["<<interface>> +m"])
    end

    it "is not a member" do
      entity = parse_class("<<interface>>\n+m()")

      expect([entity.attributes, entity.class_methods.map(&:name)])
        .to eq([[], ["m"]])
    end
  end

  describe "a free-text member in a class body" do
    {
      "a return type first" => ["void methods()", "void methods", "", nil],
      "a return type after" => ["+getWheels() List~Wheel~", "getWheels", "", "List~Wheel~"],
      "a generic parameter" => ["setWheels(List~Wheel~ wheels)", "setWheels", "List~Wheel~ wheels", nil],
      "an abstract mark" => ["someMethod()*", "someMethod", "", nil],
      "a static mark" => ["someMethod()$", "someMethod", "", nil],
      "a return type after a mark" => ["getPoints()* List~int~", "getPoints", "", "List~int~"]
    }.each do |name, (line, method_name, parameters, return_type)|
      it "reads #{name} as a method" do
        method = parse_class(line).class_methods.first

        expect([method.name, method.parameters, method.return_type])
          .to eq([method_name, parameters, return_type])
      end
    end

    {
      "an entity-encoded annotation" => ["&lt;&lt;interface&gt;&gt;", "&lt;&lt;interface&gt;&gt;"],
      "a separator" => [".. Simple Getter ..", ".. Simple Getter .."],
      "a bare rule" => ["==", "=="],
      "a spaced visibility" => ["-            attribute : type", "attribute : type"],
      "a lone visibility symbol" => ["-", "-"],
      "text with a quote inside" => ['a "b" c', 'a "b" c']
    }.each do |name, (line, attribute_name)|
      it "reads #{name} as an attribute named #{attribute_name.inspect}" do
        expect(parse_class(line).attributes.map(&:name)).to eq([attribute_name])
      end
    end

    it "reads the visibility symbol off a free-text member" do
      entity = parse_class("-   void hidden()\n#guarded")

      expect([entity.class_methods.first.visibility, entity.attributes.first.visibility])
        .to eq(%w[private protected])
    end

    # Keep: the base already reads these two; they fail if the free-text
    # fallback is tried before the structured member rules, or member_end
    # stops accepting a closing brace.
    it "still reads a typed attribute in full" do
      attribute = parse_class("+int age").attributes.first

      expect([attribute.name, attribute.type]).to eq(%w[age int])
    end

    it "closes the body at a brace after the text" do
      diagram = parser.parse("classDiagram\nclass A {\n+x }\nB\n")

      expect(diagram.entities.map(&:id)).to eq(%w[A B])
    end

    it "reads an indented quoted line as a member, as mmdc does" do
      expect(parse_class(' "quoted"').attributes.map(&:name)).to eq(['"quoted"'])
    end

    it "drops a static or abstract mark from an attribute name" do
      expect(parse_class("field$\nfield2*").attributes.map(&:name)).to eq(%w[field field2])
    end

    it "drops a static or abstract mark from the return type" do
      methods = parse_class("foo() void$\nbar() int*").class_methods

      expect(methods.map(&:return_type)).to eq(%w[void int])
    end

    # Keep: each is a syntax error to mmdc; they guard the free-text fallback
    # from growing to accept braces or a leading quote.
    {
      "a brace inside the text" => "a { b",
      "a line that is one brace" => "{",
      "a line starting with a quote" => '"quoted"',
      "an unclosed quote" => '"a',
      "a call with no name" => "(x) void",
      "a stray closing paren" => "abc)"
    }.each do |name, line|
      it "rejects #{name}, as mmdc does" do
        expect { parse_class(line) }.to raise_error(Sirena::Parser::ParseError)
      end
    end
  end

  describe "a trailing %% comment on a member" do
    it "strips a comment after a method call, keeping return_type nil" do
      method = parse_class("+foo() %% comment").class_methods.first

      expect([method.name, method.return_type]).to eq(["foo", nil])
    end

    it "strips a comment after a typed attribute, keeping the name and type" do
      attribute = parse_class("+int age %% comment").attributes.first

      expect([attribute.name, attribute.type]).to eq(%w[age int])
    end

    it "strips a comment after an annotation, keeping the stereotype" do
      expect(parse_class("<<interface>> %% comment").stereotype).to eq("interface")
    end

    it "strips a comment after a static-mark attribute, dropping the mark and the comment" do
      attribute = parse_class("field$ %% comment").attributes.first

      expect([attribute.name, attribute.type]).to eq(["field", nil])
    end
  end

  describe "a free-text member after a colon" do
    {
      "a return type after" => ["Object : getObject() Object", "getObject", "", "Object"],
      "a return type as an array" => ["Object : getObjects() Object[]", "getObjects", "", "Object[]"],
      "a type before the name" => ["Car : +ArrayList size()", "ArrayList size", "", nil],
      "an abstract mark" => ["Class1 : someMethod()*", "someMethod", "", nil],
      "a static mark" => ["Class1 : someMethod()$", "someMethod", "", nil],
      "a generic return type" => ["Car : +getWheels() List~Wheel~", "getWheels", "", "List~Wheel~"]
    }.each do |name, (statement, method_name, parameters, return_type)|
      it "reads #{name} as a method" do
        method = parser.parse("classDiagram\n#{statement}\n").entities.first.class_methods.first

        expect([method.name, method.parameters, method.return_type])
          .to eq([method_name, parameters, return_type])
      end
    end

    # Keep: each is a syntax error to mmdc; they guard the colon fallback
    # from accepting a second colon or a semicolon.
    {
      "a second colon" => "A : x: y: z",
      "a shorthand-looking colon" => "A:::s",
      "a colon then a shorthand" => "A : ::s",
      "a semicolon inside" => "A : a ; b",
      "a semicolon inside an annotation" => "A : <<a;b>>",
      "a colon inside an annotation" => "A : <<a:b>>"
    }.each do |name, statement|
      it "rejects #{name}, as mmdc does" do
        expect { parser.parse("classDiagram\n#{statement}\n") }.to raise_error(Sirena::Parser::ParseError)
      end
    end
  end

  describe "a method name that holds its own parentheses" do
    it "splits at the LAST paren pair, not the first" do
      method = parse_class("+foo()bar()").class_methods.first

      expect([method.name, method.parameters]).to eq(["foo()bar", ""])
    end
  end

  describe "a mark that does not touch the closing paren" do
    it "keeps a $ that is separated from the paren by a space, as return type text" do
      method = parse_class("foo() $bar").class_methods.first

      expect(method.return_type).to eq("$bar")
    end

    it "still drops a $ that touches the paren directly" do
      method = parse_class("foo()$ bar").class_methods.first

      expect(method.return_type).to eq("bar")
    end
  end

  # Each of these was a failing valid class case before this change.
  describe "the corpus cases this change cleared" do
    %w[003 009 015 021 033 035 065 076 077 092 093 099 100 102 103 105 106
       111 112 129 130 132 133 160 166].each do |number|
      it "parses class case #{number}" do
        path = Dir[File.expand_path("../../mermaid/class/#{number}_*.mmd", __dir__)].first

        expect { parser.parse(File.read(path)) }.not_to raise_error
      end
    end
  end
end
