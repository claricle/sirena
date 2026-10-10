# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Block, "#render" do
  let(:source) { "block-beta\n  block:group\n    a\n  end\n" }
  let(:scene) do
    Sirena::Layout::Block.new.call(Sirena::Parser::Block.new.parse(source))
  end
  let(:inner) { scene.children.first.children.first }
  let(:xml) { described_class.new.render(scene).to_xml }

  it "labels a block nested in a compound block" do
    expect(xml).to include(">a<")
  end

  it "renders a nested block without labels and without its text" do
    inner.labels = []

    expect(xml).not_to include(">a<")
  end
end
