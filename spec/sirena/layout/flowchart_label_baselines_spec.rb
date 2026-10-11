# frozen_string_literal: true

require "digest"
require "spec_helper"

RSpec.describe Sirena::Layout::Flowchart do
  let(:source) { "flowchart TD\n  A[\"one<br>two\"]\n" }
  let(:diagram) { Sirena::Parser::Flowchart.new.parse(source) }
  let(:theme) { Sirena::Theme::Registry.get(:default) }
  let(:scene) { described_class.new.call(diagram, theme: theme) }
  let(:label) { scene.children.first.labels.first }

  def rendered_xml(scene)
    Sirena::Renderer::Flowchart.new(theme: theme).render(scene).to_xml
  end

  def rendered_baselines(xml)
    first = xml[/<text[^>]* y="([^"]+)"/, 1]
    following = xml.scan(/<tspan[^>]* y="([^"]+)"/).flatten
    [first, *following].map(&:to_f)
  end

  def labels_for(labels)
    graph = {
      id: "flowchart",
      children: [
        {
          id: "A", x: 10, y: 20, width: 90, height: 60,
          labels: labels,
          metadata: { shape: "rect" }
        },
      ],
      edges: [],
    }
    described_class.from_graph(graph, theme: theme)
      .children.first.labels
  end

  it "publishes the drawn lines, font size, and final absolute baselines" do
    expect([label.lines, label.font_size, label.line_ys])
      .to eq([["one ", "two"], 16.0, [40.6, 64.6]])
  end

  it "keeps empty and one-line labels out of the multiline representation" do
    one_line = labels_for([{ text: "one", width: 30, height: 24 }]).first

    expect([labels_for([]), one_line.lines, one_line.line_ys])
      .to eq([[], [], []])
  end

  it "serializes mutated Scene baselines without recomputing them" do
    label.line_ys = [11.0, 222.0]

    expect(rendered_baselines(rendered_xml(scene))).to eq([11.0, 222.0])
  end

  it "preserves the exact default SVG bytes" do
    digest = "a9dfe17a70c654244cc6120e3401d2fc" \
             "5bbaaf734e5c9c7451ae1ed1796ff634"

    expect(Digest::SHA256.hexdigest(rendered_xml(scene))).to eq(digest)
  end
end
