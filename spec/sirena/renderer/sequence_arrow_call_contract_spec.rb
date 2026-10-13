# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Renderer::Sequence do
  subject(:renderer) { described_class.new }

  let(:group) { Sirena::Svg::Group.new }
  let(:arguments) { [10, 50, 90, 50, { line: "solid", head: "arrow" }, group] }

  it "preserves six-positional arrow calls and their visible geometry" do
    renderer.send(:render_arrow, *arguments)

    shaft, head = group.children
    expect([shaft.x1, shaft.y1, shaft.x2, shaft.y2, head.points])
      .to eq([11, 50, 82, 50, "90,50 82,46 82,54"])
  end

  def rejected_call(supplied)
    renderer.send(:render_arrow, *supplied)
  rescue ArgumentError => e
    [e.message, group.children]
  end

  [5, 7].each do |count|
    it "rejects #{count} arrow arguments before changing the group" do
      supplied = count == 5 ? arguments.first(5) : arguments + [nil]

      expect(rejected_call(supplied))
        .to eq(["wrong number of arguments (given #{count}, expected 6)", []])
    end
  end
end
