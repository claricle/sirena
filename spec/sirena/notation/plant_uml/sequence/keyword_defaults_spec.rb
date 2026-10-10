# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/sequence"

RSpec.describe Sirena::Notation::PlantUML::Sequence::KeywordDefaults do
  subject(:resolved) { described_class.resolve(given, a: 1, b: 2) }

  context "when a default is overridden" do
    let(:given) { { b: 3 } }

    it { is_expected.to eq(a: 1, b: 3) }
  end

  context "when a keyword is unknown" do
    let(:given) { { c: 3 } }

    it "names it" do
      expect { resolved }.to raise_error(ArgumentError, /unknown keyword: :c/)
    end
  end

  describe "a constructor that uses it" do
    it "refuses a typo'd keyword" do
      expect do
        Sirena::Notation::PlantUML::Sequence::ArrowStyle.new(
          head: nil, hiden: true,
        )
      end.to raise_error(ArgumentError, /hiden/)
    end
  end
end
