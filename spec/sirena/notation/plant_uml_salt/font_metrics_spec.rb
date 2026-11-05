# frozen_string_literal: true

require "spec_helper"

# The vertical metrics of DejaVu Sans, from its hhea table, against what
# PlantUML 1.2026.6 draws on Linux, where that is the sans-serif.
RSpec.describe Sirena::Notation::PlantUMLSalt::FontMetrics do
  it "puts a size-12 baseline where PlantUML does, 11.1387 down a line" do
    expect(described_class::ASCENT.round(4)).to eq(11.1387)
  end

  it "makes a size-12 line 13.96875 high: ascent plus descent" do
    expect(described_class::HEIGHT).to eq(13.96875)
  end

  it "scales every salt row constant from those two numbers" do
    marks = Sirena::Notation::PlantUMLSalt::WidgetMarks
    expect([marks::TEXT_HEIGHT, marks::BASELINE])
      .to eq([described_class::HEIGHT, described_class::ASCENT])
  end

  it "gives a button row, which holds a line, nine pixels more" do
    expect(Sirena::Notation::PlantUMLSalt::WidgetMarks::HEIGHTS[:button])
      .to eq(22.96875)
  end
end
