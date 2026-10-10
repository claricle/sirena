# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Svg::Tspan do
  let(:run) do
    lambda do |content, shift|
      described_class.new.tap do |t|
        t.content = content
        t.line_shift = shift
      end
    end
  end

  let(:text) do
    Sirena::Svg::Text.new.tap do |t|
      t.x = 5.0
      t.y = 10.0
      t.font_size = "10"
      t.tspans = [run.("a", nil), run.("b", 1), run.("c", 2)]
    end
  end

  it "has no dy attribute for a caller to set" do
    expect(described_class.new).not_to respond_to(:dy=)
  end

  it "never writes dy, whatever the line shift" do
    expect(text.to_xml).not_to include("dy=")
  end

  it "writes no y for a run that continues the line" do
    expect(text.to_xml).to include("<tspan>a</tspan>")
  end

  it "writes the next line at one line height below the text" do
    expect(text.to_xml).to include('<tspan y="22.0">b</tspan>')
  end

  it "accumulates the shifts of later lines" do
    expect(text.to_xml).to include('<tspan y="46.0">c</tspan>')
  end

  it "writes the same output when serialised twice" do
    first = text.to_xml
    expect(text.to_xml).to eq(first)
  end
end
