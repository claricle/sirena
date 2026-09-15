# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sirena::Transform::Kanban do
  let(:transform) { described_class.new }

  describe '#build_graph' do
    it 'treats nil columns the same as empty columns, matching Diagram::Kanban#valid?' do
      diagram = Sirena::Diagram::Kanban.new
      diagram.columns = nil

      expect(diagram.valid?).to be(true)
      expect(transform.build_graph(diagram)).to eq(
        columns: [], cards: [], width: 0, height: 0
      )
    end

    it 'returns an empty graph for an empty (bare-header) board' do
      diagram = Sirena::Diagram::Kanban.new

      expect(transform.build_graph(diagram)).to eq(
        columns: [], cards: [], width: 0, height: 0
      )
    end
  end
end
