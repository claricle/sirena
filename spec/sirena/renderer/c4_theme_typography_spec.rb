# frozen_string_literal: true

require "digest"
require "rexml/document"
require "spec_helper"

RSpec.describe Sirena::Renderer::C4 do
  let(:source) { File.read("examples/c4/02-container-diagram.mmd") }
  let(:default_svg) { Sirena.render(source) }
  let(:contrast_svg) { Sirena.render(source, theme: :high_contrast) }
  let(:expected_contrast_styles) do
    {
      "Container Diagram - E-commerce System" => [18.0, nil],
      "Customer" => [18.0, nil],
      "Online shopper" => [16.0, "middle"],
      "<<person>>" => [14.0, "middle"],
      "Uses" => [14.0, "middle"],
      "E-commerce System" => [18.0, nil],
    }
  end

  def text_styles(svg)
    document = REXML::Document.new(svg)
    REXML::XPath.match(document, "//text").to_h do |text|
      [text.text, [text.attributes["font-size"].to_f,
                   text.attributes["text-anchor"]]]
    end
  end

  def canvas(svg)
    root = REXML::Document.new(svg).root
    [root.attributes["width"].to_f, root.attributes["height"].to_f]
  end

  it "preserves the exact default SVG" do
    expect(Digest::SHA256.hexdigest(default_svg))
      .to eq("ae42d7be69d02d8fa8133d587e3cd59d1f477dd64b680234518056be1611fdf3")
  end

  it "renders every C4 text role with high-contrast typography" do
    expect(text_styles(contrast_svg)).to include(expected_contrast_styles)
  end

  it "resizes the public canvas height for the larger typography" do
    default_width, default_height = canvas(default_svg)
    contrast_width, contrast_height = canvas(contrast_svg)

    expect([contrast_width >= default_width,
            contrast_height > default_height]).to eq([true, true])
  end
end
