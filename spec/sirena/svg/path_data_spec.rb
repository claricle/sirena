# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Svg::Path, '.build_path_data' do
  {
    'move' => [{ type: :move, x: 1, y: 2 }, 'M 1 2'],
    'line' => [{ type: :line, x: 3, y: 4 }, 'L 3 4'],
    'curve' => [{ type: :curve, cx: 5, cy: 6, x: 7, y: 8 }, 'Q 5 6 7 8'],
    'bezier' => [
      { type: :bezier, c1x: 1, c1y: 2, c2x: 3, c2y: 4, x: 5, y: 6 },
      'C 1 2 3 4 5 6'
    ],
    'close' => [{ type: :close }, 'Z']
  }.each do |name, (command, expected)|
    it "renders a #{name} command as #{expected.inspect}" do
      expect(described_class.build_path_data([command])).to eq(expected)
    end
  end

  it 'joins commands with single spaces, in the order given' do
    commands = [
      { type: :move, x: 0, y: 0 },
      { type: :bezier, c1x: 1, c1y: 1, c2x: 2, c2y: 2, x: 3, y: 3 },
      { type: :line, x: 4, y: 4 },
      { type: :close }
    ]

    expect(described_class.build_path_data(commands))
      .to eq('M 0 0 C 1 1 2 2 3 3 L 4 4 Z')
  end

  it 'is empty for no commands' do
    expect(described_class.build_path_data([])).to eq('')
  end

  it 'keeps the bezier control points in c1, c2 order' do
    command = { type: :bezier, c1x: 10, c1y: 20, c2x: 30, c2y: 40, x: 50, y: 60 }

    expect(described_class.build_path_data([command]))
      .to start_with('C 10 20 30 40')
  end
end
