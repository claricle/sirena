# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "json"
require "svg_conform"

RSpec.describe Sirena::Renderer::Flowchart do
  let(:source) do
    File.read(SpecSupport::RepositoryPaths.path(
                "spec/fixtures/flowchart/inline_paint/subgraph_overlap.mmd",
              ))
  end
  let(:theme) { "default" }
  let(:document) do
    REXML::Document.new(Sirena::Engine.new(theme: theme).render(source))
  end
  let(:shape) { REXML::XPath.first(document, "//*[@id='node-E']/*[1]") }

  it "paints the shared Embed SVG node with its declared fill and stroke" do
    expect([shape.attributes["fill"], shape.attributes["stroke"]])
      .to eq(["#e8f4ea", "#3f7f55"])
  end

  context "with a serialized notation-neutral graph" do
    let(:graph) do
      Sirena::Notation::Mermaid::IRAdapters::Flowchart.call(
        Sirena::Parser::Flowchart.new.parse(source),
      )
    end

    it "retains paints across the JSON boundary" do
      restored = Sirena::IR::Graph.new(JSON.parse(graph.to_json))
      scene = Sirena::Layout::Flowchart.new.call(restored)
      node = scene.children.find { |candidate| candidate.id == "E" }
      expect([restored.valid?, node.fill, node.stroke])
        .to eq([true, "#e8f4ea", "#3f7f55"])
    end
  end

  context "with a dark theme" do
    let(:theme) { "dark" }

    it "keeps explicit node paints independent of theme" do
      expect([shape.attributes["fill"], shape.attributes["stroke"]])
        .to eq(["#e8f4ea", "#3f7f55"])
    end
  end

  %w[default dark].each do |selected_theme|
    context "with an unstyled #{selected_theme} node" do
      let(:theme) { selected_theme }
      let(:source) { "flowchart TD\nE[Unstyled]\nstyle E opacity:0.5\n" }
      let(:colors) do
        YAML.safe_load_file(SpecSupport::RepositoryPaths.path(
                              "lib/sirena/theme/builtin/#{theme}.yml",
                            )).fetch("colors")
      end

      it "preserves both themed paint attributes" do
        expect([shape.attributes["fill"], shape.attributes["stroke"]])
          .to eq(colors.values_at("node_fill", "node_stroke"))
      end
    end
  end

  context "with styles before the node declaration and repeated properties" do
    let(:source) do
      <<~MERMAID
        flowchart TD
        style E fill:red,stroke:blue
        E[Later label]
        style E fill:green,fill:gold
        style E stroke:rgb(12, 34, 56)
        style E fill:invalidcolor
      MERMAID
    end

    it "retains the explicit label and last valid paints" do
      node = Sirena::Parser::Flowchart.new.parse(source).find_node("E")

      expect([node.label, node.fill, node.stroke])
        .to eq(["Later label", "gold", "rgb(12, 34, 56)"])
    end

    it "emits function colors without splitting their commas" do
      expect([shape.attributes["fill"], shape.attributes["stroke"]])
        .to eq(["gold", "rgb(12, 34, 56)"])
    end
  end

  %w[E[Rect] E(Rounded) E((Circle)) E{Decision} E{{Hexagon}}].each do |node|
    context "with a styled #{node} shape" do
      let(:source) { "flowchart TD\n#{node}\nstyle E fill:#abc,stroke:navy\n" }

      it "applies both paints to its actual outline" do
        expect([shape.attributes["fill"], shape.attributes["stroke"]])
          .to eq(["#abc", "navy"])
      end
    end
  end

  ["fill:#f9f;B", "fill:", "fill:unknownpaint",
   'fill:red&blue,stroke:a"b', "red"].each do |properties|
    context "with a browser-ignored declaration #{properties.inspect}" do
      let(:source) { "flowchart TD\nE\nstyle E #{properties}\n" }

      it "keeps themed paint" do
        expect([shape.attributes["fill"], shape.attributes["stroke"]])
          .to eq(["#ffffff", "#000000"])
      end

      it "emits conformant XML" do
        report = SvgConform.validate(
          document.to_s, profile: Sirena::Svg::CONFORMANCE_PROFILE
        )
        expect(report).to be_valid
      end

      it "preserves the existing node set" do
        diagram = Sirena::Parser::Flowchart.new.parse(source)
        expect(diagram.nodes.map(&:id)).to eq(["E"])
      end
    end
  end

  context "when a style names only an earlier edge" do
    let(:source) { "flowchart TD\nA e1@--> B\nstyle e1 fill:red\n" }

    it "preserves edge targeting without creating a styled node" do
      diagram = Sirena::Parser::Flowchart.new.parse(source)
      expect(diagram.nodes.map(&:id)).to eq(%w[A B])
    end
  end
end
