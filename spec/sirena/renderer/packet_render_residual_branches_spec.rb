# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Packet, "#render" do
  let(:source) { "packet-beta\n  0-31: \"Wide field\"\n  32-32: \"flag\"\n" }
  let(:scene) do
    diagram = Sirena::Parser::Packet.new.parse(source)
    Sirena::Layout::Packet.new.call(diagram)
  end
  let(:renderer) { described_class.new }

  def anchors
    renderer.render(scene).children.grep(Sirena::Svg::Text)
            .select { |t| Array(t.content).join.match?(/\A\d+\z/) }
            .map { |t| [Array(t.content).join, t.text_anchor] }
  end

  it "writes start and end numbers for a multi-bit block, one for a single bit" do
    expect(anchors).to eq(
      [["0", "start"], ["31", "end"], ["32", "middle"]]
    )
  end
end
