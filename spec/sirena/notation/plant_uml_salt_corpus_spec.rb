# frozen_string_literal: true

require "spec_helper"
require_relative "plant_uml_salt/salt_helpers"

RSpec.describe Sirena::Notation::PlantUMLSalt do
  include SaltHelpers

  it "has the twelve bpg-tagged-pdf-syntax blocks" do
    expect(fixture_paths.size).to eq(12)
  end

  Dir[File.join(SaltHelpers::FIXTURES, "*.salt")].each do |path|
    context "with corpus block #{File.basename(path)}" do
      let(:source) { File.read(path) }
      let(:svg) { Sirena.render(source) }
      let(:drawn) { svg_texts(svg).join(" ").gsub(/\s+/, " ") }

      it "renders an svg root" do
        expect(REXML::Document.new(svg).root.name).to eq("svg")
      end

      it "draws every cell's text, in source order" do
        expect(in_order?(cell_texts(source), drawn)).to be(true)
      end
    end
  end
end
