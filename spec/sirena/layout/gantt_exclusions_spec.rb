# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::GanttExclusions do
  def settle(entries, start, stop, weekend: nil)
    described_class.new(entries, weekend, "YYYY-MM-DD")
      .settle(Time.utc(*start), Time.utc(*stop)).map { |time| time&.day }
  end

  {
    "no exclusions leave the end alone" =>
      [[], [2024, 3, 4], [2024, 3, 8], [8, nil]],
    "a weekend inside the span pushes the end by two days" =>
      [%w[weekends], [2024, 3, 6], [2024, 3, 11], [13, 13]],
    "a bar that would end in a weekend is drawn to its start" =>
      [%w[weekends], [2024, 3, 7], [2024, 3, 9], [11, 9]],
    "a weekday name skips every such day" =>
      [%w[monday], [2024, 3, 1], [2024, 3, 6], [7, 7]],
    "a date skips only that day" =>
      [%w[weekdays 2024-03-08], [2024, 3, 6], [2024, 3, 9], [10, 10]],
  }.each do |name, (entries, start, stop, expected)|
    it name do
      expect(settle(entries, start, stop)).to eq(expected)
    end
  end

  it "takes Friday and Saturday as the weekend after weekend friday" do
    expect(settle(%w[weekends], [2024, 2, 28], [2024, 3, 9], weekend: "friday"))
      .to eq([13, 13])
  end

  it "gives up instead of looping when every day is excluded" do
    all_days = %w[monday tuesday wednesday thursday friday saturday sunday]
    expect(settle(all_days, [2024, 1, 1], [2024, 1, 2]).first).not_to be_nil
  end
end
