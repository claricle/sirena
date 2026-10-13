# frozen_string_literal: true

require "spec_helper"

module ClassNameAdvancesSpecHelpers
  def class_width(label, theme: nil)
    source = "classDiagram\nclass C[\"#{label}\"]\n"
    diagram = Sirena::Parser::ClassDiagram.new.parse(source)
    Sirena::Layout::ClassDiagram.new.call(diagram, theme: theme)
      .children.first.width
  end

  def fallback_width(font_size)
    advance = Sirena::TextMeasurement.measure_in(
      :trebuchet, "!", font_size: font_size
    )[:width]
    24 + (advance * described_class::FALLBACK_RATIO)
  end
end

RSpec.describe Sirena::Layout::ClassNameAdvances do
  include ClassNameAdvancesSpecHelpers

  it "uses the fitted bold advance for a known character" do
    expected = 24 + (described_class::TABLE.fetch("W") * 16 / 1000.0)

    expect(class_width("W")).to be_within(0.001).of(expected)
  end

  it "uses widened Trebuchet for an unobserved character" do
    expect(class_width("!")).to be_within(0.001).of(fallback_width(16))
  end

  it "scales fallback advances with a custom name font size" do
    theme = Sirena::Theme::Registry.get(:high_contrast)
    expect(class_width("!", theme: theme))
      .to be_within(0.001).of(fallback_width(18))
  end
end
