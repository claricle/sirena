# frozen_string_literal: true

require "spec_helper"
require "sirena"

RSpec.describe Sirena::Renderer::Treemap::SectionTotal do
  let(:source) do
    <<~MMD
      treemap-beta
      "Products"
          "Electronics"
              "Phones": 50
              "Computers": 30
          "Clothing"
              "Shirts": 10
    MMD
  end
  let(:texts) do
    svg = Sirena::Engine.new.render(source)
    svg.scan(%r{<text[^>]*>([^<]*)</text>}).flatten
  end

  it "prints the summed value on the root section" do
    expect(texts).to include("90")
  end

  it "prints the summed value on a nested section" do
    expect(texts).to include("80")
  end

  it "keeps the leaf values" do
    expect(texts).to include("50", "30", "10")
  end
end
