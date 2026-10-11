# frozen_string_literal: true

require "digest"
require "rexml/document"
require "spec_helper"

RSpec.describe Sirena::Layout::Packet do
  subject(:svg) { Sirena.render(source, theme: theme) }

  let(:theme) { Sirena::Theme::Registry.get(:default) }

  def source
    <<~MERMAID
      packet-beta
        title Hello world
        0-10: "hello"
    MERMAID
  end

  def render_summary
    document = REXML::Document.new(svg)
    {
      canvas: numeric_attributes(document, "/svg", %w[width height]),
      box: numeric_attributes(document, "//rect", %w[x y width height]),
      labels: label_sizes(document),
    }
  end

  def numeric_attributes(document, path, names)
    element = REXML::XPath.first(document, path)
    names.map { |name| element.attributes[name].to_f }
  end

  def label_sizes(document)
    REXML::XPath.match(document, "//text").map do |text|
      [text.text, text.attributes["font-size"].to_f]
    end
  end

  def expected_summary
    normal = theme.typography&.font_size_normal || 14
    small = theme.typography&.font_size_small || 12
    bit = small - (normal - small)
    {
      canvas: [1026.0, 94.0],
      box: [1.0, 15.0, 347.0, 32.0],
      labels: [["hello", small], ["0", bit], ["10", bit],
               ["Hello world", normal]],
    }
  end

  %i[default light dark high_contrast].each do |theme_name|
    context "with the #{theme_name} theme" do
      let(:theme) { Sirena::Theme::Registry.get(theme_name) }

      it "uses its typography without changing packet geometry" do
        expect(render_summary).to eq(expected_summary)
      end
    end
  end

  it "preserves the representative default SVG" do
    expect(Digest::SHA256.hexdigest(svg)).to eq(
      "d99488be64d40b2bdc28634feb54907d2db263085c77e284b3e18a17641f292b",
    )
  end

  context "with a scalar-empty partial theme" do
    let(:theme) do
      Sirena::Theme.new(
        colors: Sirena::Theme::ColorPalette.new,
        typography: Sirena::Theme::Typography.new,
      )
    end

    it "retains the established typography and geometry fallbacks" do
      expect(render_summary).to eq(expected_summary)
    end
  end
end
