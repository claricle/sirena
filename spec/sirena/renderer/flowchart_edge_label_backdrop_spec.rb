# frozen_string_literal: true

require "spec_helper"
require "rexml/document"

RSpec.describe Sirena::Renderer::Flowchart do
  let(:theme) { "default" }
  let(:source) { "flowchart LR\nA -->|gyp long descender label| B\n" }
  let(:document) do
    REXML::Document.new(Sirena::Engine.new(theme: theme).render(source))
  end
  let(:edge) { REXML::XPath.first(document, "//g[@id='edge-A_to_B']") }

  { "default" => "#ffffff", "dark" => "#1e1e1e" }.each do |name, color|
    context "with the #{name} theme" do
      let(:theme) { name }

      it "paints an opaque background between the shaft and label text" do
        expect(edge.elements.map(&:name)).to eq(%w[path polygon rect text])
      end

      it "uses the existing theme background and no visible border" do
        rect = edge.elements["rect"]
        expect([rect.attributes["fill"], rect.attributes["stroke"]])
          .to eq([color, "none"])
      end
    end
  end

  {
    "a typography-only model" => Sirena::Theme.new(
      typography: Sirena::Theme::Typography.new(flowchart_font_size: 20),
    ),
    "a typography-only hash" => { typography: { flowchart_font_size: 20 } },
  }.each do |name, partial_theme|
    context "with #{name}" do
      let(:theme) { partial_theme }
      let(:source) { "flowchart LR\nA -->|gyp| B\n" }

      it "keeps a white backdrop behind the implicit black text" do
        expect([edge.elements["rect"].attributes["fill"],
                edge.elements["text"].attributes["fill"]])
          .to eq(["#ffffff", nil])
      end

      it "scales the backdrop with the supplied font size" do
        expect([edge.elements["rect"].attributes["height"],
                edge.elements["text"].attributes["font-size"]])
          .to eq(["25.0", "20.0"])
      end
    end
  end

  ["#345678", "none", "transparent"].each do |background|
    context "with an explicit #{background} background" do
      let(:theme) { { colors: { background: background } } }

      it "preserves the caller's background paint" do
        expect(edge.elements["rect"].attributes["fill"]).to eq(background)
      end
    end
  end

  context "with a measured long label containing descenders" do
    let(:label) do
      diagram = Sirena::Parser::Flowchart.new.parse(source)
      Sirena::Layout::Flowchart.new.call(diagram).edges.first.labels.first
    end

    it "covers measured text width plus font-scaled ink padding" do
      rect = edge.elements["rect"]
      bounds = rect.attributes.values_at("x", "width")
        .map { |value| value.value.to_f }
      expect(bounds).to eq([label.x - (label.width / 2) - 2, label.width + 4])
    end

    it "covers ascent and descenders around the existing alphabetic baseline" do
      rect = edge.elements["rect"]
      bounds = rect.attributes.values_at("y", "height")
        .map { |value| value.value.to_f }
      top = label.y - (label.height / 2) - (0.35 * label.font_size) - 2
      expect(bounds).to eq([top, label.height + 4])
    end

    it "preserves the existing text and its baseline" do
      text = edge.elements["text"]
      expect([text.text, text.attributes["x"].to_f, text.attributes["y"].to_f])
        .to eq([label.text, label.x, label.y])
    end
  end

  context "with the layout's existing arrow geometry" do
    let(:arrow) do
      diagram = Sirena::Parser::Flowchart.new.parse(source)
      Sirena::Layout::Flowchart.new.call(diagram).edges.first
    end

    it "preserves the shaft path" do
      expect(edge.elements["path"].attributes["d"]).to eq(arrow.path)
    end

    it "preserves the arrowhead polygon" do
      expect(edge.elements["polygon"].attributes["points"])
        .to eq(arrow.heads.first.points)
    end
  end

  context "with an unlabeled edge" do
    let(:source) { "flowchart LR\nA-->B\n" }

    it "retains only the existing shaft and arrowhead" do
      expect(edge.elements.map(&:name)).to eq(%w[path polygon])
    end
  end

  context "with missing label metrics" do
    let(:document) { REXML::Document.new(described_class.new.render(scene).to_xml) }
    let(:edge) { REXML::XPath.first(document, "//g[@id='edge-loop']") }

    context "with a text-only label in the hand-positioned graph adapter" do
      let(:scene) do
        graph = { id: "hand-positioned", children: [
          { id: "A", x: 30, y: 70, width: 0, height: 0 },
        ], edges: [
          { id: "loop", sources: ["A"], targets: ["A"],
            labels: [{ text: "x" }], metadata: { arrow_type: "arrow" } },
        ] }
        Sirena::Layout::Flowchart.from_graph(graph)
      end

      it "retains the existing text position" do
        text = edge.elements["text"]
        expect([text.text, text.attributes["x"], text.attributes["y"]])
          .to eq(["x", "30.0", "70.0"])
      end

      it "measures the missing dimensions for the backdrop" do
        rect = edge.elements["rect"]
        expect([rect.attributes["width"], rect.attributes["height"]])
          .to eq(["12.0", "20.0"])
      end
    end

    context "with a directly constructed typed label lacking all metrics" do
      let(:scene) do
        label = Sirena::Layout::Flowchart::Label.new(text: "edge", x: 5, y: 4)
        arrow = Sirena::Layout::Flowchart::Edge.new(
          id: "loop", path: "M 0 0 L 10 10",
          arrow_type: "arrow", labels: [label]
        )
        Sirena::Layout::Flowchart::Scene.new(
          width: 50, height: 50, children: [], edges: [arrow],
        )
      end

      it "renders a measured backdrop without changing the typed label" do
        label = scene.edges.first.labels.first
        described_class.new.render(scene)
        expect([label.width, label.height, label.font_size])
          .to eq([nil, nil, nil])
      end

      it "preserves the text's implicit SVG font size and arrow path" do
        expect([edge.elements["text"].attributes["font-size"],
                edge.elements["path"].attributes["d"]])
          .to eq(["", "M 0 0 L 10 10"])
      end

      it "uses the document's standard medium font to measure the backdrop" do
        rect = edge.elements["rect"]
        expect([rect.attributes["width"], rect.attributes["height"]])
          .to eq(["39.584", "20.0"])
      end
    end
  end
end
