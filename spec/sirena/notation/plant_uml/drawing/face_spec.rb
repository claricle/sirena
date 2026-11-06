# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml/drawing"

RSpec.describe Sirena::Notation::PlantUML::Drawing::Face do
  describe ".widest_line" do
    let(:widest) { described_class.width("longest", size: 13) }

    it "splits at a literal backslash-n" do
      expect(described_class.widest_line("longest\\nshort", size: 13))
        .to eq(widest)
    end

    it "splits at a newline" do
      expect(described_class.widest_line("short\nlongest", size: 13))
        .to eq(widest)
    end

    it "measures bold in the DejaVu bold table" do
      expect(described_class.widest_line("Alice", size: 26, bold: true))
        .to be > described_class.widest_line("Alice", size: 26)
    end
  end
end
