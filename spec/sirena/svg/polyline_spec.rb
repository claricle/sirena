# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Svg::Polyline do
  describe ".build_points" do
    it "joins coordinate pairs in drawing order" do
      expect(described_class.build_points([[1, 2], [-3.5, 4]]))
        .to eq("1,2 -3.5,4")
    end

    it "is empty when there are no coordinates" do
      expect(described_class.build_points([])).to eq("")
    end
  end
end
