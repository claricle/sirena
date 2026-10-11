# frozen_string_literal: true

require "rexml/document"
require "spec_helper"

RSpec.describe Sirena::Renderer::Sankey do
  let(:palette) do
    %w[#3794ff #4ec9b0 #f48771 #dcdcaa #89d185 #9cdcfe #fbbf24 #969696]
  end
  let(:source) do
    flows = 8.times.map { |index| "source#{index},target#{index},1" }
    (["sankey-beta"] + flows).join("\n")
  end

  it "uses every dark flow colour in order" do
    document = REXML::Document.new(Sirena.render(source, theme: :dark))
    fills = REXML::XPath.match(document, "//path[@fill-opacity='0.4']/@fill")
      .map(&:value)

    expect(fills).to eq(palette)
  end
end
