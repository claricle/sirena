# frozen_string_literal: true

require "digest"
require "rexml/document"
require "spec_helper"

RSpec.describe Sirena::Renderer::ClassDiagram do
  let(:source) do
    <<~MERMAID
      classDiagram
      namespace N {
        class A {
          +name: string
          +run()
        }
        class B
      }
      note for A "hello"
      A "1" <|-- "many" B : owns
    MERMAID
  end
  let(:graph) do
    {
      id: "class_diagram",
      children: [
        {
          id: "A", x: 10, y: 10, width: 150, height: 100,
          metadata: {
            name: "A", stereotype: "interface",
            attributes: [{ text: "+name: string" }],
            methods: [{ text: "+run()" }]
          }
        },
        {
          id: "B", x: 200, y: 10, width: 150, height: 100,
          metadata: {
            name: "B", stereotype: "interface",
            attributes: [{ text: "+name: string" }],
            methods: [{ text: "+run()" }]
          }
        },
      ],
      edges: [{
        id: "B_to_A", sources: ["B"], targets: ["A"],
        labels: [
          { text: "owns" }, { text: "many", position: "source" },
          { text: "1", position: "target" }
        ],
        metadata: { relationship_type: "inheritance" }
      }],
    }
  end
  let(:scene_palette) do
    document = REXML::Document.new(Sirena.render(source, theme: :dark))
    namespace = REXML::XPath.first(document, "//*[@id='namespace-N']")
    relationship = REXML::XPath.first(document, "//*[@id='rel-B_to_A']")
    node = REXML::XPath.first(document, "//*[@id='class-A']")
    note = REXML::XPath.first(document, "//*[@id='note-0']")
    actual = {
      generic: [namespace.elements[1].attributes["stroke"],
                namespace.elements[2].attributes["fill"],
                relationship.elements[1].attributes["stroke"],
                relationship.elements[2].attributes["stroke"],
                relationship.elements[3].attributes["fill"],
                node.elements[1].attributes["fill"],
                node.elements[1].attributes["stroke"],
                node.elements[3].attributes["stroke"],
                node.elements[2].attributes["fill"]],
      note: [note.elements[1].attributes["stroke"],
             note.elements[2].attributes["fill"],
             note.elements[2].attributes["stroke"],
             note.elements[3].attributes["fill"]],
    }
    expected = {
      generic: ["#858585", "#d4d4d4", "#858585", "#858585", "#d4d4d4",
                "#2d2d30", "#858585", "#858585", "#d4d4d4"],
      note: ["#aaaa33", "#fff5ad", "#aaaa33", "#000000"],
    }
    [actual, expected]
  end
  let(:legacy_palette) do
    theme = Sirena::Theme::Registry.get(:dark)
    renderer = described_class.new(theme: theme)
    document = REXML::Document.new(renderer.render(graph).to_xml)
    relationship = REXML::XPath.first(document, "//*[@id='rel-B_to_A']")
    node = REXML::XPath.first(document, "//*[@id='class-A']")
    actual = [
      relationship.elements[1].attributes["stroke"],
      relationship.elements[2].attributes["stroke"],
      relationship.elements[3].attributes["fill"],
      node.elements[1].attributes["fill"],
      node.elements[1].attributes["stroke"],
      node.elements[4].attributes["stroke"],
      node.elements[2].attributes["fill"],
    ]
    expected = ["#858585", "#858585", "#d4d4d4", "#2d2d30", "#858585",
                "#858585", "#d4d4d4"]
    [actual, expected]
  end

  it "preserves the default SVG bytes" do
    digest = Digest::SHA256.hexdigest(Sirena.render(source))

    expect(digest)
      .to eq("b9263601cde08adaa3e5ed9d1a48f51868495ed9220b10388085ef1fb6d9c813")
  end

  it "applies dark theme roles while retaining the note palette" do
    expect(scene_palette.first).to eq(scene_palette.last)
  end

  it "applies the same dark theme roles through the legacy path" do
    expect(legacy_palette.first).to eq(legacy_palette.last)
  end
end
