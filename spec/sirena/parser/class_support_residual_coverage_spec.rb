# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Parser do
  describe Sirena::Parser::ClassNamespaces, ".collect" do
    it "ignores namespace members that were not built as class entities" do
      parser = Sirena::Parser::ClassDiagram.new
      diagram = parser.parse("classDiagram\nclass Known\n")
      tree = [{
        namespace_keyword: "namespace",
        namespace_name: "N",
        namespace_body: [{ class_id: "Known" }, { class_id: "Ghost" }],
      }]

      namespaces = described_class.collect(tree, diagram)

      expect(namespaces.first.class_ids).to eq(["Known"])
    end
  end

  describe Sirena::Parser::ClassDiagram, "#parse" do
    it "resolves an unqualified note target to its unique dotted class id" do
      diagram = described_class.new.parse(<<~MERMAID)
        classDiagram
        class Pkg.A
        note for A "about A"
      MERMAID

      expect(diagram.notes.first.target_id).to eq("Pkg.A")
    end
  end
end
