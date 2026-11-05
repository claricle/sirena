# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::Creole do
  def decorations(text)
    described_class.parse(text).map do |run|
      described_class.decoration(run.style)
    end
  end

  it "draws ~~wave~~ as a wavy underline, as PlantUML does" do
    expect(decorations("a ~~wave~~ b")).to eq([nil, "wavy underline", nil])
  end

  it "draws <w> the same way" do
    expect(decorations("<w>wave</w>")).to eq(["wavy underline"])
  end

  it "keeps __underline__ a plain underline" do
    expect(decorations("__u__")).to eq(["underline"])
  end
end
