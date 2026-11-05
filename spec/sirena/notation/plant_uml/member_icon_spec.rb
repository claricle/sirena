# frozen_string_literal: true

require "spec_helper"
require "rexml/document"
require "sirena/notation/plantuml"
Sirena::Notation.send(:entries).delete(:plantuml)

# Geometry below is measured from PlantUML 1.2026.6 (the pinned reference).
RSpec.describe Sirena::Notation::PlantUML::MemberIcon do
  describe ".enabled?" do
    it "is true without a skinparam" do
      expect(described_class.enabled?(["hide circle"])).to be(true)
    end

    it "is false under `skinparam classAttributeIconSize 0`" do
      expect(described_class.enabled?(["skinparam classAttributeIconSize 0"]))
        .to be(false)
    end

    it "stays true for a nonzero size" do
      expect(described_class.enabled?(["skinparam classAttributeIconSize 8"]))
        .to be(true)
    end
  end

  describe ".insets" do
    let(:kinds) { %i[field field method separator] }
    let(:visibilities) { [:public, nil, nil, nil] }

    it "pushes a whole group in when one of its members carries an icon" do
      expect(described_class.insets(kinds, visibilities, true))
        .to eq([20.0, 20.0, 6.0, nil])
    end

    it "keeps every row at the plain inset when icons are off" do
      expect(described_class.insets(kinds, visibilities, false))
        .to eq([6.0, 6.0, 6.0, nil])
    end
  end

  describe ".visible_text" do
    it "drops the prefix an icon replaces" do
      expect(described_class.visible_text("+run()", :public, true))
        .to eq("run()")
    end

    it "keeps the prefix when icons are off" do
      expect(described_class.visible_text("+run()", :public, false))
        .to eq("+run()")
    end

    it "leaves a row without visibility alone" do
      expect(described_class.visible_text("run()", nil, true)).to eq("run()")
    end
  end

  describe ".at" do
    it "has no icon for a member without visibility" do
      expect(described_class.at(nil, :field, 10.0, 50.0)).to be_nil
    end

    it "centres a circle 11 in and 3.79 above the baseline" do
      icon = described_class.at(:public, :method, 7.0, 106.0)

      expect([icon.shape, icon.cx, icon.cy, icon.filled])
        .to eq(["circle", 18.0, 102.21, true])
    end

    it "hollows a field's icon" do
      expect(described_class.at(:private, :field, 7.0, 56.5).filled)
        .to be(false)
    end

    it "rises 4.79 for a diamond and a triangle" do
      shapes = %i[protected package].map do |visibility|
        described_class.at(visibility, :field, 0.0, 10.0)
      end

      expect(shapes.map { |icon| [icon.shape, icon.cy.round(2)] })
        .to eq([["diamond", 5.21], ["triangle", 5.21]])
    end
  end
end
