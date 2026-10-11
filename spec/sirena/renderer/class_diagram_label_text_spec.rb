# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

module ClassLabelTextHelpers
  module_function

  # The text of every <text> element the engine draws for the source.
  def drawn_texts(source)
    doc = REXML::Document.new(Sirena::Engine.new.render(source))
    REXML::XPath.match(doc, "//*[local-name()='text']").map do |node|
      node.texts.map(&:value).join
    end
  end
end

# The expected texts are what mermaid's own SVG draws for the same source
# (spec/fixtures_mermaid/class_diagram/<case>.svg).
RSpec.describe Sirena::Renderer::ClassDiagram do
  {
    "a member without a visibility mark (yari-3e69d3e6)" => [
      "classDiagram\nclass ClassName {\n  test\n}\n", ["test"]
    ],
    "a typed attribute as written (yari-ca7091fd)" => [
      "classDiagram\nclass Duck {\n  +String beakColor\n}\n",
      ["+String beakColor"],
    ],
    "a method return type after a spaced colon (yari-3e69d3e6)" => [
      "classDiagram\nclass C {\n  + GetAttribute() type\n}\n",
      ["+ GetAttribute() : type"],
    ],
    "an attribute with no space after the colon (yari-3e69d3e6)" => [
      "classDiagram\nclass C {\n  -attribute:type\n}\n", ["-attribute:type"]
    ],
    "a generic in a member (should_handle_generic_types-994062c2)" => [
      "classDiagram\nclass Car\nCar : -List~Wheel~ wheels\n",
      ["-List<Wheel> wheels"],
    ],
    "a colon member without the class name (should_handle_method_definition-168bb5b6)" => [
      "classDiagram\nclass Car\nCar : GetSize()\n", ["GetSize()"]
    ],
    "an entity-coded annotation member (classdiagram_elk_v3_spec-c57d14a6)" => [
      "classDiagram\nclass C {\n  &lt;&lt;interface&gt;&gt;\n}\n",
      ["<<interface>>"],
    ],
    "an annotation (yari-635beb05)" => [
      "classDiagram\nclass Shape\n<<interface>> Shape\n", ["«interface»"]
    ],
    "a generic in a class name (should_handle_generic_class-0b14c539)" => [
      "classDiagram\nclass Car~T~\n", ["Car<T>"]
    ],
  }.each do |label, (source, expected)|
    it "draws #{label} as mermaid does" do
      expect(ClassLabelTextHelpers.drawn_texts(source)).to include(*expected)
    end
  end
end
