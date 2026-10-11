# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::ClassNameAdvances do
  def class_width(label, theme: nil)
    source = "classDiagram\nclass C[\"#{label}\"]\n"
    diagram = Sirena::Parser::ClassDiagram.new.parse(source)
    Sirena::Layout::ClassDiagram.new.call(diagram, theme: theme)
      .children.first.width
  end

  it "uses the fitted bold advance for a known character" do
    expected = 24 + (described_class::TABLE.fetch("W") * 16 / 1000.0)

    expect(class_width("W")).to be_within(0.001).of(expected)
  end

  it "uses widened Trebuchet for an unobserved character" do
    advance = Sirena::TextMeasurement.measure_in(
      :trebuchet, "!", font_size: 16
    )[:width]

    expect(class_width("!")).to be_within(0.001).of(
      24 + (advance * described_class::FALLBACK_RATIO),
    )
  end

  it "scales fallback advances with a custom name font size" do
    theme = Sirena::Theme::Registry.get(:high_contrast)
    advance = Sirena::TextMeasurement.measure_in(
      :trebuchet, "!", font_size: 18
    )[:width]

    expect(class_width("!", theme: theme)).to be_within(0.001).of(
      24 + (advance * described_class::FALLBACK_RATIO),
    )
  end
end
