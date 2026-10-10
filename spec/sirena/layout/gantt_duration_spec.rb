# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sirena::Layout::GanttDuration do
  let(:start) { Time.utc(2024, 1, 31) }

  {
    "days" => ["2d", Time.utc(2024, 2, 2)],
    "hours without rounding up" => ["20h", Time.utc(2024, 1, 31, 20)],
    "minutes" => ["90m", Time.utc(2024, 1, 31, 1, 30)],
    "seconds" => ["30s", Time.utc(2024, 1, 31, 0, 0, 30)],
    "weeks" => ["1w", Time.utc(2024, 2, 7)],
    "a fraction of a day" => ["1.5d", Time.utc(2024, 2, 1, 12)],
    "calendar months" => ["1M", Time.utc(2024, 2, 29)],
    "calendar years" => ["1y", Time.utc(2025, 1, 31)],
    "a bare number as days" => ["3", Time.utc(2024, 2, 3)],
    "text it cannot read as no time" => ["soon", Time.utc(2024, 1, 31)],
  }.each do |name, (text, expected)|
    it "reads #{name}" do
      expect(described_class.add(start, text)).to eq(expected)
    end
  end
end
