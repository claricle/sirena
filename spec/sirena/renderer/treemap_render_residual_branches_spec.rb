# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Treemap, "#render" do
  subject(:renderer) { described_class.new }

  let(:scene) do
    source = "treemap-beta\n  \"A\"\n    \"B\": 5\n"
    diagram = Sirena::Parser::Treemap.new.parse(source)
    Sirena::Layout::Treemap.new.call(diagram)
  end
  let(:fills) do
    renderer.render(scene).to_xml.scan(/<text[^>]*fill="([^"]+)"/).flatten.uniq
  end

  it "takes the label colour from the theme" do
    expect(fills).not_to include("#666", "#333")
  end

  it "falls back to grey for name and value labels without a theme" do
    renderer.theme = nil

    expect(fills).to contain_exactly("#333", "#666")
  end
end
