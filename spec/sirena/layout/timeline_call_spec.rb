# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Timeline, "#call" do
  include TimelineSceneHelpers

  # Stacked multi-line events: the sums here carry float noise unrounded.
  let(:source) { File.read(fixture_path) }
  let(:fixture_path) do
    File.expand_path("../../mermaid/timeline/#{fixture}.mmd", __dir__)
  end
  let(:fixture) { "timeline_spec-c4dfe5d4" }
  let(:scene) { lay_out(source) }
  let(:published) { floats_in(scene.to_hash) }

  def floats_in(value)
    case value
    when Float then [value]
    when Hash then value.values.flat_map { |each| floats_in(each) }
    when Array then value.flat_map { |each| floats_in(each) }
    else []
    end
  end

  it "rounds every coordinate to four places" do
    expect(published.reject { |value| value.round(4) == value }).to be_empty
  end

  it "keeps the measured text widths finer than two places" do
    expect(scene.cards.map(&:text_width).reject { |v| v.round(2) == v })
      .not_to be_empty
  end

  it "serializes the published digits unchanged" do
    svg = Sirena::Renderer::Timeline.new.render(scene).to_xml

    expect(svg).not_to match(/\d\.\d{5,}|\de-\d/)
  end
end
