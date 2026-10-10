# frozen_string_literal: true

require "spec_helper"

# Expected values were read off mmdc's axis for the same task span.
RSpec.describe Sirena::Layout::GanttTicks do
  let(:jan_first) { [2024, 1, 1] }
  let(:jan_second) { [2024, 1, 2] }

  {
    "6-hour ticks for a 3-day span" =>
      [3, nil, ["2024-01-01 00", "2024-01-04 00", 13]],
    "daily ticks for a 14-day span" =>
      [14, nil, ["2024-01-01 00", "2024-01-15 00", 15]],
    "Sunday weeks for a 100-day span" =>
      [100, nil, ["2024-01-07 00", "2024-04-07 00", 14]],
    "first of the month for a 200-day span" =>
      [200, nil, ["2024-01-01 00", "2024-07-01 00", 7]],
    "quarters for a 1000-day span" =>
      [1000, nil, ["2024-01-01 00", "2026-07-01 00", 11]],
    "years once the ladder runs out" =>
      [4000, nil, ["2024-01-01 00", "2034-01-01 00", 11]],
  }.each do |name, (days, interval, expected)|
    it "picks #{name}" do
      expect(GanttTickTexts.summary(jan_first, days, interval))
        .to eq(expected)
    end
  end

  {
    "every Sunday for 1week" =>
      ["1week", ["2024-01-07 00", "2024-02-11 00", 6]],
    "odd days of the month for 2day" =>
      ["2day", ["2024-01-03 00", "2024-02-11 00", 21]],
    "every third day of the month for 3day" =>
      ["3day", ["2024-01-04 00", "2024-02-10 00", 14]],
    "the first of the month for 1month" =>
      ["1month", ["2024-02-01 00", "2024-02-01 00", 1]],
  }.each do |name, (interval, expected)|
    it "follows tickInterval as #{name}" do
      expect(GanttTickTexts.summary(jan_second, 40, interval))
        .to eq(expected)
    end
  end

  it "ignores a tickInterval it cannot read and uses the ladder" do
    expect(GanttTickTexts.summary(jan_first, 14, "fortnightly"))
      .to eq(GanttTickTexts.summary(jan_first, 14))
  end
end
