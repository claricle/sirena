# frozen_string_literal: true

require "digest"
require "rexml/document"
require "spec_helper"

RSpec.describe Sirena::Layout::Quadrant do
  subject(:svg) { Sirena.render(source, theme: theme) }

  let(:theme) { Sirena::Theme::Registry.get(:default) }

  def source
    <<~MERMAID
      quadrantChart
        title Reach and engagement of campaigns
        x-axis Low Reach --> High Reach
        y-axis Low Engagement --> High Engagement
        quadrant-1 We should expand
        quadrant-2 Need to promote
        quadrant-3 Re-evaluate
        quadrant-4 May be improved
        Campaign A: [0.3, 0.6]
        Campaign B: [0.45, 0.23]
        Campaign C: [0.57, 0.69]
        Campaign D: [0.78, 0.34]
        Campaign E: [0.40, 0.34]
        Campaign F: [0.35, 0.78]
    MERMAID
  end

  def document
    REXML::Document.new(svg)
  end

  def font_sizes(path)
    REXML::XPath.match(document, path).map do |text|
      text.attributes["font-size"].to_f
    end.uniq
  end

  def first_quadrant_bounds
    rectangle = REXML::XPath.first(document, "//g[@class='quadrant']/rect")
    %w[x y width height].map { |name| rectangle.attributes[name].to_f }
  end

  def render_summary
    {
      title: font_sizes("//g[@class='title']/text"),
      axes: font_sizes("//g[@class='labels']//text"),
      quadrants: font_sizes("//g[@class='quadrant']/text"),
      points: font_sizes("//g[@class='data-point']/text"),
      first_quadrant: first_quadrant_bounds,
    }
  end

  def expected_summary
    title, large, small = theme_sizes
    {
      title: [title], axes: [large], quadrants: [large], points: [small],
      first_quadrant: plot_bounds(title, large)
    }
  end

  def theme_sizes
    typography = theme.typography
    [typography&.font_size_title || 20,
     typography&.font_size_large || 16,
     typography&.font_size_small || 12]
  end

  def plot_bounds(title, large)
    plot_width = 490 - large - 10
    plot_height = 490 - large - 10 - title - 20
    [15 + large + (plot_width / 2.0), 25 + title,
     plot_width / 2.0, plot_height / 2.0]
  end

  %i[default light dark high_contrast].each do |theme_name|
    context "with the #{theme_name} theme" do
      let(:theme) { Sirena::Theme::Registry.get(theme_name) }

      it "uses its typography to size labels and plot rooms" do
        expect(render_summary).to eq(expected_summary)
      end
    end
  end

  it "preserves the representative default SVG" do
    expect(Digest::SHA256.hexdigest(svg)).to eq(
      "ea08c36eaca566f355e102a06a4d3de74b75c0d45ec11fb86af78909f6e86174",
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
