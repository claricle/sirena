# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::KanbanCardText do
  it "drops whitespace that would start a newly wrapped line" do
    lines = described_class.lines("alpha beta", width: 40, font_size: 16)

    expect(lines.map { |line| line.map(&:text).join })
      .to eq(%w[alpha beta])
  end

  it "preserves an empty hard line without producing an empty run" do
    lines = described_class.lines("", width: 40, font_size: 16)

    expect(lines).to eq([[]])
  end
end
