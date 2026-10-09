# frozen_string_literal: true

require "spec_helper"
require "timeout"

module PathPointsSpecHelpers
  TOKENS = ["M", "m", "L", "Z", "z", "H", "V", "C", "S", "Q", "T", "A",
            "0", "1", "5", "-2.5", "1e2", ","].freeze

  def self.outcome(data)
    Timeout.timeout(2) do
      SpecSupport::LayoutParity::PathPoints.new(data).points
    end
    :returned
  rescue ArgumentError
    :refused
  end

  def self.random_paths(count)
    random = Random.new(42)
    Array.new(count) do
      Array.new(random.rand(1..8)) { TOKENS[random.rand(TOKENS.size)] }
        .join(" ")
    end
  end
end

RSpec.describe SpecSupport::LayoutParity::PathPoints do
  def outcome(data)
    PathPointsSpecHelpers.outcome(data)
  end

  it "refuses a number after Z instead of looping" do
    expect(outcome("M 0 0 L 5 5 Z 5")).to eq(:refused)
  end

  it "refuses a number after a lowercase z" do
    expect(outcome("M 0 0 l 5 5 z 5 5")).to eq(:refused)
  end

  it "still accepts a command after Z" do
    expect(outcome("M 0 0 L 5 5 Z M 1 1")).to eq(:returned)
  end

  it "terminates on every random token string" do
    stuck = PathPointsSpecHelpers.random_paths(2000).reject do |data|
      outcome(data)
    rescue Timeout::Error
      false
    end
    expect(stuck).to eq([])
  end
end
