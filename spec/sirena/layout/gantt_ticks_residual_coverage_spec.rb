# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::GanttTicks, ".times" do
  it "uses the first hourly ladder rung for a sub-hour range" do
    start_time = Time.utc(2024, 1, 1, 12)

    expect(described_class.times(start_time, start_time + 600))
      .to eq([start_time])
  end
end
