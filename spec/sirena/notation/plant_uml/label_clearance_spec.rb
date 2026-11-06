# frozen_string_literal: true

require "spec_helper"
require "sirena/notation/plantuml"

RSpec.describe Sirena::Notation::PlantUML::LabelClearance do
  describe ".top_between" do
    it "gives the highest point of a rising line under the text" do
      expect(described_class.top_between([0.0, 100.0], [100.0, 0.0],
                                         20.0, 60.0)).to eq(40.0)
    end

    it "holds the line to its own ends" do
      expect(described_class.top_between([0.0, 100.0], [100.0, 0.0],
                                         -50.0, 200.0)).to eq(0.0)
    end

    it "gives the top of a vertical line" do
      expect(described_class.top_between([10.0, 80.0], [10.0, 20.0],
                                         0.0, 20.0)).to eq(20.0)
    end
  end

  describe ".right_between" do
    it "gives the rightmost point of a line leaning right over the text" do
      expect(described_class.right_between([0.0, 0.0], [50.0, 100.0],
                                           20.0, 40.0)).to eq(20.0)
    end

    it "holds the line to its own ends" do
      expect(described_class.right_between([0.0, 0.0], [50.0, 100.0],
                                           -10.0, 300.0)).to eq(50.0)
    end

    it "gives the right end of a flat line" do
      expect(described_class.right_between([0.0, 5.0], [70.0, 5.0],
                                           0.0, 10.0)).to eq(70.0)
    end
  end
end
