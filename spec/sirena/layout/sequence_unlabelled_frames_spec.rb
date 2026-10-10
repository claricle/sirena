# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::Sequence do
  include SequenceFrameHelpers

  # mmdc: a frame or section without text lacks its 20px label line.
  [
    ["a loop with no text", "A->>B: h\nloop\nB->>A: g\nend", 69],
    ["a loop with text", "A->>B: h\nloop L\nB->>A: g\nend", 89],
    ["an alt with no else text",
     "A->>B: h\nalt a\nB->>A: g\nelse\nB->>A: i\nend", 158],
    ["an alt with no text anywhere",
     "A->>B: h\nalt\nB->>A: g\nelse\nB->>A: i\nend", 138],
  ].each do |name, body, gap|
    it "spaces rows #{gap}px apart across #{name}" do
      expect(row_gap(body)).to eq(gap)
    end
  end
end
