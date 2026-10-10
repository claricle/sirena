# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::C4ShapeMetrics do
  def sized(**options)
    described_class.new(label: "Name", **options).then do |metrics|
      [metrics.width, metrics.height]
    end
  end

  # 216x60 is mmdc's minimum; 216x86 and 216x134 are the system and person
  # boxes of c4/007 that hold a one line description.
  it "never goes below the 216x60 minimum" do
    expect(sized).to eq([216, 60])
  end

  it "grows a system with a one line description to 86" do
    expect(sized(description: "Main application")).to eq([216, 86])
  end

  it "grows a person with a description to 134" do
    expect(sized(description: "A user", person: true)).to eq([216, 134])
  end

  it "makes room for a technology line" do
    expect(sized(technology: "Ruby", description: "Main")).to eq([216, 107])
  end

  it "widens the box to the description plus padding" do
    text = "Allows customers to view information about their accounts"
    width = Sirena::Layout::C4Text.width(text, 14)
    expect(sized(description: text).first).to eq(width + 20)
  end

  it "offsets the label 8 px below the person icon" do
    metrics = described_class.new(label: "N", person: true)
    expect(metrics.label_offset - metrics.image_offset).to eq(56)
  end

  it "keeps the stereotype 20 px from the top" do
    expect(described_class.new(label: "N").stereotype_offset).to eq(20)
  end
end
