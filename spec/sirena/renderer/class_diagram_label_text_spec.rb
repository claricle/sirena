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
# (spec/fixtures_mermaid/class/<case>.svg).
RSpec.describe Sirena::Renderer::ClassDiagram do
  {
    "a member without a visibility mark (class/033)" => [
      "classDiagram\nclass ClassName {\n  test\n}\n", ["test"]
    ],
    "a typed attribute as written (class/031)" => [
      "classDiagram\nclass Duck {\n  +String beakColor\n}\n",
      ["+String beakColor"],
    ],
    "a method return type after a spaced colon (class/033)" => [
      "classDiagram\nclass C {\n  + GetAttribute() type\n}\n",
      ["+ GetAttribute() : type"],
    ],
    "an attribute with no space after the colon (class/033)" => [
      "classDiagram\nclass C {\n  -attribute:type\n}\n", ["-attribute:type"]
    ],
    "a generic in a member (class/097)" => [
      "classDiagram\nclass Car\nCar : -List~Wheel~ wheels\n",
      ["-List<Wheel> wheels"],
    ],
    "a colon member without the class name (class/098)" => [
      "classDiagram\nclass Car\nCar : GetSize()\n", ["GetSize()"]
    ],
    "an entity-coded annotation member (class/003)" => [
      "classDiagram\nclass C {\n  &lt;&lt;interface&gt;&gt;\n}\n",
      ["<<interface>>"],
    ],
    "an annotation (class/034)" => [
      "classDiagram\nclass Shape\n<<interface>> Shape\n", ["«interface»"]
    ],
    "a generic in a class name (class/108)" => [
      "classDiagram\nclass Car~T~\n", ["Car<T>"]
    ],
  }.each do |label, (source, expected)|
    it "draws #{label} as mermaid does" do
      expect(ClassLabelTextHelpers.drawn_texts(source)).to include(*expected)
    end
  end
end
