# frozen_string_literal: true

require "spec_helper"

RSpec.describe BoxOverlap do
  let(:box) { Struct.new(:x, :y, :width, :height) }
  let(:base) { box.new(0, 0, 10, 10) }

  [
    ["a box inside another", [2, 2, 3, 3], true],
    ["a box crossing a corner", [8, 8, 10, 10], true],
    ["a box sharing only an edge", [10, 0, 10, 10], false],
    ["a box clear on x but level on y", [20, 0, 10, 10], false],
    ["a box clear on y but level on x", [0, 20, 10, 10], false],
  ].each do |name, geometry, expected|
    it "reports #{name} as #{expected ? 'overlapping' : 'apart'}" do
      other = box.new(*geometry)
      results = [described_class.overlap?(base, other),
                 described_class.overlap?(other, base)]
      expect(results).to eq([expected, expected])
    end
  end
end
