# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Packet, "#render" do
  let(:source) { "packet-beta\n  0-31: \"Wide field\"\n" }
  let(:scene) do
    diagram = Sirena::Parser::Packet.new.parse(source)
    Sirena::Layout::Packet.new.call(diagram)
  end
  let(:renderer) { described_class.new }

  def text_count
    renderer.render(scene).children.grep(Sirena::Svg::Text).size
  end

  it "writes a range label for a field that has one" do
    expect(scene.fields.first.range_label).not_to be_nil
  end

  it "writes one text fewer for a field without a range label" do
    with_label = text_count
    scene.fields.first.range_label = nil

    expect(text_count).to eq(with_label - 1)
  end
end
