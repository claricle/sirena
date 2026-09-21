# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FixtureLengthBand do
  include described_class

  # A 1000-character reference and a baseline of 0.25 put the centre at 250.
  let(:expected_svg) { 'x' * 1000 }
  let(:baseline) { 0.25 }

  def within?(actual_length)
    within_length_band?('x' * actual_length, expected_svg, baseline)
  end

  {
    'equal to the baseline' => [250, true],
    '1.9x above the baseline' => [475, true],
    '1.9x below the baseline' => [132, true],
    '2.1x above the baseline' => [525, false],
    '2.1x below the baseline' => [119, false],
    '3x above the baseline' => [750, false],
    '3x below the baseline' => [83, false]
  }.each do |label, (length, inside)|
    it "#{inside ? 'accepts' : 'rejects'} output #{label}" do
      expect(within?(length)).to be(inside)
    end
  end
end
