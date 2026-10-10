# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Sequence do
  let(:source) do
    <<~MERMAID
      sequenceDiagram
          participant A
          participant B
          A->>B: first
          Note over A,B: line one<br>line two
          B->>A: second
    MERMAID
  end
  let(:xml) { Sirena.render(source) }
  let(:note_rect) { xml[/<rect[^>]*fff5ad[^>]*>/] }
  let(:note_y) { note_rect[/ y="([\d.]+)"/, 1].to_f }
  let(:message_ys) do
    xml.scan(/stroke-width="2" x1="[\d.]+" y1="([\d.]+)"/)
      .flatten.map(&:to_f)
  end

  it "draws the note box in mermaid's note colours" do
    expect(note_rect).to include('stroke="#aaaa33"')
  end

  it "draws each note line as its own text" do
    texts = xml.scan(/>(line one|line two)</)
    expect(texts).to eq([["line one"], ["line two"]])
  end

  it "keeps <br> out of the drawn text" do
    expect(xml).not_to include("&lt;br")
  end

  it "places the note box between the two message rows" do
    expect(message_ys.first).to be < note_y
  end

  it "keeps the second message below the note box" do
    height = note_rect[/ height="([\d.]+)"/, 1].to_f
    expect(message_ys.last).to be > note_y + height
  end

  it "draws notes for a hand-built graph too" do
    layout = Sirena::Layout::Sequence.new
    graph = layout.build_graph(Sirena::Parser::Sequence.new.parse(source))

    expect(described_class.new.render(graph).to_xml).to include("fff5ad")
  end
end
