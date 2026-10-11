# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Notation::Mermaid::ClassDiagramConfig do
  let(:courier) do
    "%%{init: {'theme': 'base', 'fontFamily': 'courier'}}%%"
  end

  {
    "no directive" => [[], nil],
    "an init without fontFamily" => [["%%{init: {'theme': 'base'}}%%"], nil],
    "a malformed init payload" => [["%%{init: {'fontFamily': }%%"], nil],
    "an empty fontFamily" => [["%%{init: {'fontFamily': ''}}%%"], nil],
  }.each do |name, (directives, expected)|
    it "reads no font family from #{name}" do
      expect(described_class.font_family(directives)).to eq(expected)
    end
  end

  it "reads the init directive's fontFamily" do
    expect(described_class.font_family([courier])).to eq("courier")
  end

  it "lets the last init directive win" do
    later = "%%{init: {'fontFamily': 'Arial'}}%%"
    expect(described_class.font_family([courier, later])).to eq("Arial")
  end
end
